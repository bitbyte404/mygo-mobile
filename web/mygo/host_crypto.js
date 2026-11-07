// host.crypto for plugins in the browser: MD5 and AES-ECB (PKCS#7), both
// synchronous as the host API is (WebCrypto is async and has neither), with
// the same output as the desktop's host.go and the app's Dart PluginHost:
// lowercase hex.

const enc = new TextEncoder();
const hex = (b) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");

// ---------- MD5 (RFC 1321) ----------
const S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
const K = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32) >>> 0);

export function md5Bytes(msg) {
  const n = msg.length;
  const total = (((n + 8) >> 6) + 1) << 6;
  const b = new Uint8Array(total);
  b.set(msg);
  b[n] = 0x80;
  const dv = new DataView(b.buffer);
  dv.setUint32(total - 8, (n * 8) >>> 0, true);
  dv.setUint32(total - 4, Math.floor((n * 8) / 2 ** 32), true);
  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  const M = new Uint32Array(16);
  for (let off = 0; off < total; off += 64) {
    for (let i = 0; i < 16; i++) M[i] = dv.getUint32(off + i * 4, true);
    let A = a0, B = b0, C = c0, D = d0;
    for (let i = 0; i < 64; i++) {
      let F, g;
      if (i < 16) { F = (B & C) | (~B & D); g = i; }
      else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) & 15; }
      else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) & 15; }
      else { F = C ^ (B | ~D); g = (7 * i) & 15; }
      F = (F + A + K[i] + M[g]) >>> 0;
      A = D; D = C; C = B;
      B = (B + ((F << S[i]) | (F >>> (32 - S[i])))) >>> 0;
    }
    a0 = (a0 + A) >>> 0; b0 = (b0 + B) >>> 0; c0 = (c0 + C) >>> 0; d0 = (d0 + D) >>> 0;
  }
  const out = new Uint8Array(16);
  const ov = new DataView(out.buffer);
  ov.setUint32(0, a0, true); ov.setUint32(4, b0, true); ov.setUint32(8, c0, true); ov.setUint32(12, d0, true);
  return out;
}

export const md5 = (text) => hex(md5Bytes(enc.encode(String(text))));

// ---------- AES (FIPS-197), encryption only ----------
const SBOX = new Uint8Array(256);
(() => {
  // Build the S-box from GF(2^8) inverses and the affine transform.
  let p = 1, q = 1;
  do {
    p = p ^ ((p << 1) & 0xff) ^ (p & 0x80 ? 0x1b : 0);
    q ^= q << 1; q ^= q << 2; q ^= q << 4; q &= 0xff;
    if (q & 0x80) q ^= 0x09;
    const x = q ^ ((q << 1) | (q >> 7)) ^ ((q << 2) | (q >> 6)) ^ ((q << 3) | (q >> 5)) ^ ((q << 4) | (q >> 4));
    SBOX[p] = (x ^ 0x63) & 0xff;
  } while (p !== 1);
  SBOX[0] = 0x63;
})();
const xt = (a) => ((a << 1) ^ (a & 0x80 ? 0x1b : 0)) & 0xff;

function expandKey(key) {
  const nk = key.length / 4, nr = nk + 6;
  const w = new Uint8Array(16 * (nr + 1));
  w.set(key);
  let rcon = 1;
  for (let i = nk; i < 4 * (nr + 1); i++) {
    let t = w.slice(4 * (i - 1), 4 * i);
    if (i % nk === 0) {
      t = new Uint8Array([SBOX[t[1]] ^ rcon, SBOX[t[2]], SBOX[t[3]], SBOX[t[0]]]);
      rcon = xt(rcon);
    } else if (nk > 6 && i % nk === 4) {
      t = t.map((x) => SBOX[x]);
    }
    for (let j = 0; j < 4; j++) w[4 * i + j] = w[4 * (i - nk) + j] ^ t[j];
  }
  return { w, nr };
}

function encryptBlock(s, { w, nr }) {
  for (let i = 0; i < 16; i++) s[i] ^= w[i];
  for (let r = 1; r <= nr; r++) {
    for (let i = 0; i < 16; i++) s[i] = SBOX[s[i]];
    // ShiftRows (column-major state)
    let t = s[1]; s[1] = s[5]; s[5] = s[9]; s[9] = s[13]; s[13] = t;
    t = s[2]; s[2] = s[10]; s[10] = t; t = s[6]; s[6] = s[14]; s[14] = t;
    t = s[15]; s[15] = s[11]; s[11] = s[7]; s[7] = s[3]; s[3] = t;
    if (r !== nr) {
      for (let c = 0; c < 4; c++) {
        const a0 = s[4 * c], a1 = s[4 * c + 1], a2 = s[4 * c + 2], a3 = s[4 * c + 3];
        const all = a0 ^ a1 ^ a2 ^ a3;
        s[4 * c] ^= all ^ xt(a0 ^ a1);
        s[4 * c + 1] ^= all ^ xt(a1 ^ a2);
        s[4 * c + 2] ^= all ^ xt(a2 ^ a3);
        s[4 * c + 3] ^= all ^ xt(a3 ^ a0);
      }
    }
    for (let i = 0; i < 16; i++) s[i] ^= w[16 * r + i];
  }
}

export function aesEcbPkcs7(key, text) {
  if (![16, 24, 32].includes(key.length)) throw new Error(`crypto/aes: invalid key size ${key.length}`);
  const pad = 16 - (text.length % 16);
  const data = new Uint8Array(text.length + pad);
  data.set(text);
  data.fill(pad, text.length);
  const ks = expandKey(key);
  for (let i = 0; i < data.length; i += 16) {
    const block = data.subarray(i, i + 16);
    encryptBlock(block, ks);
  }
  return data;
}

export const aesEcbEncrypt = (key, text) => hex(aesEcbPkcs7(enc.encode(String(key)), enc.encode(String(text))));
