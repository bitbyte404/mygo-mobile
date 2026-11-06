// The host side of a MyGo Music plugin, in JavaScript, on top of QuickJS-ng
// and one native function: __mg_send(op, json, bytes?) -> json, which Dart
// answers synchronously. What has to wait (fetch, timers) answers later
// through __mg_settle / __mg_timer, called from Dart.
//
// It gives a plugin what the desktop app's moejs runtime does: the standard
// library, timers, fetch and its relatives, URL, TextEncoder/TextDecoder,
// atob/btoa, console and the host global.
(() => {
  "use strict";
  const g = globalThis;
  const nativeSend = g.__mg_send;
  delete g.__mg_send;

  const send = (op, data, bytes) => {
    const r = nativeSend(op, data === undefined ? "" : JSON.stringify(data), bytes);
    return r === undefined || r === "" ? undefined : JSON.parse(r);
  };
  Object.defineProperty(g, "__mg_host_send", { value: send });

  const define = (name, value) => {
    if (typeof g[name] === "undefined") {
      Object.defineProperty(g, name, { value, writable: true, configurable: true, enumerable: false });
    }
  };

  // ---------- async ops ----------
  let nextOp = 1;
  const pending = new Map();
  function asyncOp(op, data, bytes) {
    const id = nextOp++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      try {
        send(op, Object.assign({}, data, { id }), bytes);
      } catch (e) {
        pending.delete(id);
        reject(e);
      }
    });
  }
  Object.defineProperty(g, "__mg_settle", {
    value: (json, buf) => {
      const m = JSON.parse(json);
      const p = pending.get(m.id);
      if (!p) return;
      pending.delete(m.id);
      if (m.ok) p.resolve({ value: m.value, bytes: buf });
      else {
        const e = new (m.name === "AbortError" ? DOMExceptionLike : TypeError)(m.error || "failed");
        if (m.name) e.name = m.name;
        p.reject(e);
      }
    },
  });

  class DOMExceptionLike extends Error {
    constructor(message, name) {
      super(message);
      this.name = name || "Error";
    }
  }
  define("DOMException", DOMExceptionLike);

  // ---------- timers ----------
  let nextTimer = 1;
  const timers = new Map();
  function addTimer(fn, ms, args, repeat) {
    const id = nextTimer++;
    if (typeof fn !== "function") {
      const code = String(fn);
      fn = () => (0, eval)(code);
    }
    timers.set(id, { fn, args, repeat });
    ms = Math.max(0, Number(ms) || 0);
    send("timer", { id, ms, repeat: !!repeat });
    return id;
  }
  function clearTimer(id) {
    if (timers.delete(id)) send("clearTimer", { id });
  }
  Object.defineProperty(g, "__mg_timer", {
    value: (json) => {
      const { id } = JSON.parse(json);
      const t = timers.get(id);
      if (!t) return;
      if (!t.repeat) timers.delete(id);
      t.fn.apply(undefined, t.args);
    },
  });
  define("setTimeout", (fn, ms, ...args) => addTimer(fn, ms, args, false));
  define("setInterval", (fn, ms, ...args) => addTimer(fn, ms, args, true));
  define("clearTimeout", (id) => clearTimer(id));
  define("clearInterval", (id) => clearTimer(id));
  define("queueMicrotask", (fn) => Promise.resolve().then(fn));
  const t0 = Date.now();
  define("performance", { now: () => Date.now() - t0, timeOrigin: t0, mark() {}, measure() {} });

  // ---------- console ----------
  const fmt = (a) => {
    if (typeof a === "string") return a;
    if (a instanceof Error) return `${a.name}: ${a.message}`;
    try {
      return JSON.stringify(a, (k, v) => (typeof v === "bigint" ? v.toString() + "n" : v));
    } catch {
      return String(a);
    }
  };
  const log = (level) => (...args) => send("log", { level, msg: args.map(fmt).join(" ") });
  define("console", { log: log("log"), info: log("info"), warn: log("warn"), error: log("error"), debug: log("debug") });

  // ---------- text ----------
  function utf8Encode(str) {
    str = String(str);
    const out = [];
    for (let i = 0; i < str.length; i++) {
      let c = str.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
        const d = str.charCodeAt(i + 1);
        if (d >= 0xdc00 && d <= 0xdfff) {
          c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
          i++;
        } else c = 0xfffd;
      } else if (c >= 0xd800 && c <= 0xdfff) c = 0xfffd;
      if (c < 0x80) out.push(c);
      else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
      else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return new Uint8Array(out);
  }
  function utf8Decode(b, fatal) {
    let s = "";
    const parts = [];
    for (let i = 0; i < b.length; ) {
      const c = b[i];
      let cp = 0xfffd, n = 1;
      if (c < 0x80) cp = c;
      else if (c >= 0xc2 && c < 0xe0 && i + 1 < b.length && (b[i + 1] & 0xc0) === 0x80) {
        cp = ((c & 31) << 6) | (b[i + 1] & 63);
        n = 2;
      } else if (c >= 0xe0 && c < 0xf0 && i + 2 < b.length && (b[i + 1] & 0xc0) === 0x80 && (b[i + 2] & 0xc0) === 0x80) {
        cp = ((c & 15) << 12) | ((b[i + 1] & 63) << 6) | (b[i + 2] & 63);
        n = 3;
        if (cp < 0x800 || (cp >= 0xd800 && cp <= 0xdfff)) { cp = 0xfffd; n = 1; }
      } else if (c >= 0xf0 && c < 0xf5 && i + 3 < b.length && (b[i + 1] & 0xc0) === 0x80 && (b[i + 2] & 0xc0) === 0x80 && (b[i + 3] & 0xc0) === 0x80) {
        cp = ((c & 7) << 18) | ((b[i + 1] & 63) << 12) | ((b[i + 2] & 63) << 6) | (b[i + 3] & 63);
        n = 4;
        if (cp < 0x10000 || cp > 0x10ffff) { cp = 0xfffd; n = 1; }
      }
      if (cp === 0xfffd && n === 1 && c >= 0x80 && fatal) throw new TypeError("The encoded data was not valid utf-8");
      if (cp >= 0x10000) {
        cp -= 0x10000;
        parts.push(0xd800 + (cp >> 10), 0xdc00 + (cp & 1023));
      } else parts.push(cp);
      i += n;
      if (parts.length > 8192) {
        s += String.fromCharCode.apply(null, parts);
        parts.length = 0;
      }
    }
    return s + String.fromCharCode.apply(null, parts);
  }
  const toBytes = (input) => {
    if (input === undefined || input === null) return new Uint8Array(0);
    if (input instanceof Uint8Array) return input;
    if (input instanceof ArrayBuffer) return new Uint8Array(input);
    if (ArrayBuffer.isView(input)) return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    throw new TypeError("expected an ArrayBuffer or a view of one");
  };
  class TextEncoder {
    get encoding() { return "utf-8"; }
    encode(s = "") { return utf8Encode(s); }
    encodeInto(s, dest) {
      const b = utf8Encode(s);
      const n = Math.min(b.length, dest.length);
      dest.set(b.subarray(0, n));
      return { read: s.length, written: n };
    }
  }
  class TextDecoder {
    constructor(label = "utf-8", opts = {}) {
      const l = String(label).toLowerCase();
      if (!["utf-8", "utf8", "unicode-1-1-utf-8"].includes(l)) throw new RangeError(`TextDecoder: ${label} isn't supported`);
      this.fatal = !!opts.fatal;
      this.ignoreBOM = !!opts.ignoreBOM;
    }
    get encoding() { return "utf-8"; }
    decode(input) {
      let b = toBytes(input);
      if (!this.ignoreBOM && b.length >= 3 && b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) b = b.subarray(3);
      return utf8Decode(b, this.fatal);
    }
  }
  define("TextEncoder", TextEncoder);
  define("TextDecoder", TextDecoder);

  const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  define("btoa", (s) => {
    s = String(s);
    let out = "";
    for (let i = 0; i < s.length; i += 3) {
      const a = s.charCodeAt(i), b = s.charCodeAt(i + 1), c = s.charCodeAt(i + 2);
      if (a > 255 || b > 255 || c > 255) throw new DOMExceptionLike("Invalid character", "InvalidCharacterError");
      const n = (a << 16) | ((b || 0) << 8) | (c || 0);
      out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + (i + 1 < s.length ? B64[(n >> 6) & 63] : "=") + (i + 2 < s.length ? B64[n & 63] : "=");
    }
    return out;
  });
  define("atob", (s) => {
    s = String(s).replace(/[\t\n\f\r ]+/g, "");
    if (s.length % 4 === 0) s = s.replace(/==?$/, "");
    if (s.length % 4 === 1 || /[^A-Za-z0-9+/]/.test(s)) throw new DOMExceptionLike("Invalid character", "InvalidCharacterError");
    let out = "", bits = 0, acc = 0;
    for (let i = 0; i < s.length; i++) {
      acc = (acc << 6) | B64.indexOf(s[i]);
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out += String.fromCharCode((acc >> bits) & 255);
      }
    }
    return out;
  });

  define("structuredClone", (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v))));

  // ---------- crypto (random only; host.crypto has the rest) ----------
  define("crypto", {
    getRandomValues(arr) {
      const b = toBytes(arr);
      const r = send("random", { n: b.length });
      for (let i = 0; i < b.length; i++) b[i] = r[i];
      return arr;
    },
    randomUUID() {
      const b = this.getRandomValues(new Uint8Array(16));
      b[6] = (b[6] & 15) | 64;
      b[8] = (b[8] & 63) | 128;
      const h = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
      return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
    },
  });

  // ---------- events ----------
  class Event {
    constructor(type, init = {}) {
      this.type = String(type);
      this.bubbles = !!init.bubbles;
      this.cancelable = !!init.cancelable;
      this.defaultPrevented = false;
      this.timeStamp = Date.now();
      this.target = null;
    }
    preventDefault() { if (this.cancelable) this.defaultPrevented = true; }
    stopPropagation() {}
    stopImmediatePropagation() { this._stop = true; }
  }
  class EventTarget {
    constructor() { Object.defineProperty(this, "_listeners", { value: new Map() }); }
    addEventListener(type, fn, opts) {
      if (!fn) return;
      const list = this._listeners.get(type) || [];
      if (list.some((l) => l.fn === fn)) return;
      list.push({ fn, once: !!(opts && opts.once) });
      this._listeners.set(type, list);
    }
    removeEventListener(type, fn) {
      const list = this._listeners.get(type);
      if (list) this._listeners.set(type, list.filter((l) => l.fn !== fn));
    }
    dispatchEvent(ev) {
      ev.target = this;
      const handler = this["on" + ev.type];
      if (typeof handler === "function") handler.call(this, ev);
      for (const l of [...(this._listeners.get(ev.type) || [])]) {
        if (l.once) this.removeEventListener(ev.type, l.fn);
        typeof l.fn === "function" ? l.fn.call(this, ev) : l.fn.handleEvent(ev);
        if (ev._stop) break;
      }
      return !ev.defaultPrevented;
    }
  }
  define("Event", Event);
  define("EventTarget", EventTarget);

  class AbortSignal extends EventTarget {
    constructor() {
      super();
      this.aborted = false;
      this.reason = undefined;
      this.onabort = null;
    }
    throwIfAborted() { if (this.aborted) throw this.reason; }
    static abort(reason) {
      const c = new AbortController();
      c.abort(reason);
      return c.signal;
    }
    static timeout(ms) {
      const c = new AbortController();
      setTimeout(() => c.abort(new DOMExceptionLike("The operation timed out.", "TimeoutError")), ms);
      return c.signal;
    }
  }
  class AbortController {
    constructor() { this.signal = new AbortSignal(); }
    abort(reason) {
      const s = this.signal;
      if (s.aborted) return;
      s.aborted = true;
      s.reason = reason === undefined ? new DOMExceptionLike("This operation was aborted", "AbortError") : reason;
      s.dispatchEvent(new Event("abort"));
    }
  }
  define("AbortSignal", AbortSignal);
  define("AbortController", AbortController);

  // ---------- URL ----------
  const encodeForm = (s) => encodeURIComponent(s).replace(/%20/g, "+").replace(/[!'()~]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
  const decodeForm = (s) => {
    try {
      return decodeURIComponent(s.replace(/\+/g, " "));
    } catch {
      return s;
    }
  };
  class URLSearchParams {
    constructor(init) {
      Object.defineProperty(this, "_list", { value: [], writable: true });
      Object.defineProperty(this, "_url", { value: null, writable: true });
      if (init === undefined || init === null) return;
      if (typeof init === "string") {
        this._parse(init);
      } else if (init instanceof URLSearchParams) {
        this._list = init._list.map((p) => [...p]);
      } else if (typeof init[Symbol.iterator] === "function") {
        for (const [k, v] of init) this._list.push([String(k), String(v)]);
      } else {
        for (const k of Object.keys(init)) this._list.push([k, String(init[k])]);
      }
    }
    _parse(s) {
      this._list = [];
      if (s.startsWith("?")) s = s.slice(1);
      for (const part of s.split("&")) {
        if (!part) continue;
        const i = part.indexOf("=");
        this._list.push(i < 0 ? [decodeForm(part), ""] : [decodeForm(part.slice(0, i)), decodeForm(part.slice(i + 1))]);
      }
    }
    _update() { if (this._url) this._url._search = this._list.length ? "?" + this.toString() : ""; }
    get size() { return this._list.length; }
    append(k, v) { this._list.push([String(k), String(v)]); this._update(); }
    delete(k, v) { this._list = this._list.filter((p) => !(p[0] === String(k) && (v === undefined || p[1] === String(v)))); this._update(); }
    get(k) { const p = this._list.find((p) => p[0] === String(k)); return p ? p[1] : null; }
    getAll(k) { return this._list.filter((p) => p[0] === String(k)).map((p) => p[1]); }
    has(k, v) { return this._list.some((p) => p[0] === String(k) && (v === undefined || p[1] === String(v))); }
    set(k, v) {
      k = String(k);
      const i = this._list.findIndex((p) => p[0] === k);
      if (i < 0) this._list.push([k, String(v)]);
      else {
        this._list[i][1] = String(v);
        this._list = this._list.filter((p, j) => j <= i || p[0] !== k);
      }
      this._update();
    }
    sort() { this._list.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)); this._update(); }
    forEach(fn, self) { for (const [k, v] of this._list) fn.call(self, v, k, this); }
    keys() { return this._list.map((p) => p[0])[Symbol.iterator](); }
    values() { return this._list.map((p) => p[1])[Symbol.iterator](); }
    entries() { return this._list.map((p) => [p[0], p[1]])[Symbol.iterator](); }
    [Symbol.iterator]() { return this.entries(); }
    toString() { return this._list.map(([k, v]) => encodeForm(k) + "=" + encodeForm(v)).join("&"); }
  }
  const DEFAULT_PORTS = { "http:": "80", "https:": "443", "ws:": "80", "wss:": "443", "ftp:": "21" };
  const SPECIAL = new Set(["http:", "https:", "ws:", "wss:", "ftp:", "file:"]);
  function normalizePath(path) {
    const out = [];
    const segs = path.split("/");
    for (let i = 0; i < segs.length; i++) {
      const s = segs[i];
      if (s === "..") {
        if (out.length > 1) out.pop();
        if (i === segs.length - 1) out.push("");
      } else if (s === ".") {
        if (i === segs.length - 1) out.push("");
      } else out.push(s);
    }
    let p = out.join("/");
    if (!p.startsWith("/")) p = "/" + p;
    return p.replace(/[^\x21-\x7e]|[ "<>`#?{}]/g, (c) => (c === "%" ? c : encodeURIComponent(c)));
  }
  class URL {
    constructor(url, base) {
      url = String(url).trim();
      const m = /^([a-zA-Z][a-zA-Z0-9+.-]*):(.*)$/.exec(url);
      if (m) {
        this._parseAbsolute(m[1].toLowerCase() + ":", m[2]);
      } else {
        if (base === undefined) throw new TypeError(`Invalid URL: ${url}`);
        const b = base instanceof URL ? base : new URL(base);
        this._protocol = b._protocol;
        if (url.startsWith("//")) {
          this._parseAbsolute(b._protocol, url);
          return;
        }
        this._username = b._username; this._password = b._password;
        this._hostname = b._hostname; this._port = b._port;
        let rest = url, hash = "", search = "";
        const hi = rest.indexOf("#");
        if (hi >= 0) { hash = rest.slice(hi); rest = rest.slice(0, hi); }
        const qi = rest.indexOf("?");
        if (qi >= 0) { search = rest.slice(qi); rest = rest.slice(0, qi); }
        if (rest === "") {
          this._pathname = b._pathname;
          this._search = qi >= 0 ? (search === "?" ? "" : search) : b._search;
        } else if (rest.startsWith("/")) {
          this._pathname = normalizePath(rest);
          this._search = search === "?" ? "" : search;
        } else {
          const dir = b._pathname.slice(0, b._pathname.lastIndexOf("/") + 1);
          this._pathname = normalizePath(dir + rest);
          this._search = search === "?" ? "" : search;
        }
        this._hash = hash === "#" ? "" : hash;
      }
    }
    _parseAbsolute(protocol, rest) {
      this._protocol = protocol;
      this._username = ""; this._password = ""; this._hostname = ""; this._port = "";
      let hash = "", search = "";
      const hi = rest.indexOf("#");
      if (hi >= 0) { hash = rest.slice(hi); rest = rest.slice(0, hi); }
      const qi = rest.indexOf("?");
      if (qi >= 0) { search = rest.slice(qi); rest = rest.slice(0, qi); }
      if (SPECIAL.has(protocol)) rest = rest.replace(/\\/g, "/");
      if (rest.startsWith("//") || (SPECIAL.has(protocol) && protocol !== "file:")) {
        rest = rest.replace(/^\/*/, "");
        const si = rest.indexOf("/");
        let auth = si < 0 ? rest : rest.slice(0, si);
        rest = si < 0 ? "" : rest.slice(si);
        const at = auth.lastIndexOf("@");
        if (at >= 0) {
          const cred = auth.slice(0, at);
          auth = auth.slice(at + 1);
          const ci = cred.indexOf(":");
          this._username = ci < 0 ? cred : cred.slice(0, ci);
          this._password = ci < 0 ? "" : cred.slice(ci + 1);
        }
        const pm = /^(\[[^\]]*\]|[^:]*)(?::(\d*))?$/.exec(auth);
        if (!pm) throw new TypeError(`Invalid URL: ${protocol}${rest}`);
        this._hostname = pm[1].toLowerCase();
        this._port = pm[2] && pm[2] !== DEFAULT_PORTS[protocol] ? String(Number(pm[2])) : "";
        if (!this._hostname && protocol !== "file:") throw new TypeError("Invalid URL: no host");
        this._pathname = SPECIAL.has(protocol) ? normalizePath(rest || "/") : rest;
      } else {
        this._pathname = rest;
      }
      this._search = search === "?" ? "" : search;
      this._hash = hash === "#" ? "" : hash;
    }
    get protocol() { return this._protocol; }
    set protocol(v) { this._protocol = String(v).replace(/:?$/, ":").toLowerCase(); }
    get username() { return this._username; }
    set username(v) { this._username = String(v); }
    get password() { return this._password; }
    set password(v) { this._password = String(v); }
    get hostname() { return this._hostname; }
    set hostname(v) { this._hostname = String(v).toLowerCase(); }
    get port() { return this._port; }
    set port(v) { v = String(v); this._port = v === DEFAULT_PORTS[this._protocol] ? "" : v; }
    get host() { return this._hostname + (this._port ? ":" + this._port : ""); }
    set host(v) { const [h, p] = String(v).split(":"); this.hostname = h; this.port = p || ""; }
    get origin() { return SPECIAL.has(this._protocol) && this._protocol !== "file:" ? `${this._protocol}//${this.host}` : "null"; }
    get pathname() { return this._pathname; }
    set pathname(v) { this._pathname = normalizePath(String(v)); }
    get search() { return this._search; }
    set search(v) {
      v = String(v);
      this._search = v === "" || v === "?" ? "" : v.startsWith("?") ? v : "?" + v;
      if (this._sp) this._sp._parse(this._search);
    }
    get searchParams() {
      if (!this._sp) {
        this._sp = new URLSearchParams(this._search);
        this._sp._url = this;
      }
      return this._sp;
    }
    get hash() { return this._hash; }
    set hash(v) { v = String(v); this._hash = v === "" || v === "#" ? "" : v.startsWith("#") ? v : "#" + v; }
    get href() {
      const cred = this._username ? this._username + (this._password ? ":" + this._password : "") + "@" : "";
      const authority = this._hostname || this._protocol === "file:" ? "//" + cred + this.host : "";
      return this._protocol + authority + this._pathname + this._search + this._hash;
    }
    set href(v) {
      const u = new URL(v);
      Object.assign(this, u);
      this._sp = undefined;
    }
    toString() { return this.href; }
    toJSON() { return this.href; }
    static canParse(u, b) {
      try { new URL(u, b); return true; } catch { return false; }
    }
  }
  define("URLSearchParams", URLSearchParams);
  define("URL", URL);

  // ---------- fetch ----------
  const normName = (n) => {
    n = String(n).toLowerCase();
    if (!/^[!#$%&'*+.^_`|~0-9a-z-]+$/.test(n)) throw new TypeError(`Invalid header name: ${n}`);
    return n;
  };
  class Headers {
    constructor(init) {
      Object.defineProperty(this, "_map", { value: new Map() });
      if (!init) return;
      if (init instanceof Headers) init.forEach((v, k) => this.append(k, v));
      else if (Array.isArray(init) || typeof init[Symbol.iterator] === "function") for (const [k, v] of init) this.append(k, v);
      else for (const k of Object.keys(init)) this.append(k, init[k]);
    }
    append(k, v) {
      k = normName(k);
      v = String(v).trim();
      const cur = this._map.get(k);
      this._map.set(k, cur === undefined ? v : k === "set-cookie" ? cur + "\n" + v : cur + ", " + v);
    }
    set(k, v) { this._map.set(normName(k), String(v).trim()); }
    get(k) { const v = this._map.get(normName(k)); return v === undefined ? null : k.toLowerCase() === "set-cookie" ? v.replace(/\n/g, ", ") : v; }
    getSetCookie() { const v = this._map.get("set-cookie"); return v === undefined ? [] : v.split("\n"); }
    has(k) { return this._map.has(normName(k)); }
    delete(k) { this._map.delete(normName(k)); }
    forEach(fn, self) { for (const [k, v] of this.entries()) fn.call(self, v, k, this); }
    keys() { return [...this._map.keys()].sort()[Symbol.iterator](); }
    values() { return [...this.entries()].map((e) => e[1])[Symbol.iterator](); }
    entries() { return [...this._map.keys()].sort().map((k) => [k, this.get(k)])[Symbol.iterator](); }
    [Symbol.iterator]() { return this.entries(); }
  }

  class Blob {
    constructor(parts = [], opts = {}) {
      const chunks = parts.map((p) => (p instanceof Blob ? p._bytes : typeof p === "string" ? utf8Encode(p) : toBytes(p)));
      const n = chunks.reduce((a, c) => a + c.length, 0);
      const b = new Uint8Array(n);
      let o = 0;
      for (const c of chunks) { b.set(c, o); o += c.length; }
      Object.defineProperty(this, "_bytes", { value: b });
      this.type = opts.type ? String(opts.type).toLowerCase() : "";
    }
    get size() { return this._bytes.length; }
    arrayBuffer() { return Promise.resolve(this._bytes.slice().buffer); }
    bytes() { return Promise.resolve(this._bytes.slice()); }
    text() { return Promise.resolve(utf8Decode(this._bytes)); }
    slice(start = 0, end = this.size, type = "") { return new Blob([this._bytes.slice(start, end)], { type }); }
  }
  class File extends Blob {
    constructor(parts, name, opts = {}) {
      super(parts, opts);
      this.name = String(name);
      this.lastModified = opts.lastModified || Date.now();
    }
  }
  class FormData {
    constructor() { Object.defineProperty(this, "_list", { value: [], writable: true }); }
    append(k, v, filename) { this._list.push([String(k), v instanceof Blob ? (filename !== undefined || !(v instanceof File) ? new File([v], filename ?? "blob", { type: v.type }) : v) : String(v)]); }
    set(k, v, f) { this.delete(k); this.append(k, v, f); }
    get(k) { const p = this._list.find((p) => p[0] === k); return p ? p[1] : null; }
    getAll(k) { return this._list.filter((p) => p[0] === k).map((p) => p[1]); }
    has(k) { return this._list.some((p) => p[0] === k); }
    delete(k) { this._list = this._list.filter((p) => p[0] !== k); }
    forEach(fn, self) { for (const [k, v] of this._list) fn.call(self, v, k, this); }
    entries() { return this._list.map((p) => [...p])[Symbol.iterator](); }
    keys() { return this._list.map((p) => p[0])[Symbol.iterator](); }
    values() { return this._list.map((p) => p[1])[Symbol.iterator](); }
    [Symbol.iterator]() { return this.entries(); }
  }
  define("Headers", Headers);
  define("Blob", Blob);
  define("File", File);
  define("FormData", FormData);

  // Turns a body into bytes and the content type it implies.
  function extractBody(body) {
    if (body === undefined || body === null) return { bytes: null, type: null };
    if (typeof body === "string") return { bytes: utf8Encode(body), type: "text/plain;charset=UTF-8" };
    if (body instanceof URLSearchParams) return { bytes: utf8Encode(body.toString()), type: "application/x-www-form-urlencoded;charset=UTF-8" };
    if (body instanceof Blob) return { bytes: body._bytes, type: body.type || null };
    if (body instanceof FormData) {
      const boundary = "----MyGoFormBoundary" + Math.random().toString(16).slice(2) + Date.now().toString(16);
      const parts = [];
      for (const [k, v] of body._list) {
        const name = k.replace(/"/g, "%22").replace(/\r?\n/g, "%0A");
        if (v instanceof File) {
          parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"; filename="${v.name.replace(/"/g, "%22")}"\r\nContent-Type: ${v.type || "application/octet-stream"}\r\n\r\n`, v, "\r\n");
        } else parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${v}\r\n`);
      }
      parts.push(`--${boundary}--\r\n`);
      return { bytes: new Blob(parts)._bytes, type: `multipart/form-data; boundary=${boundary}` };
    }
    if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) return { bytes: toBytes(body).slice(), type: null };
    return { bytes: utf8Encode(String(body)), type: "text/plain;charset=UTF-8" };
  }

  class Body {
    _initBody(bytes) {
      Object.defineProperty(this, "_body", { value: bytes, writable: true });
      Object.defineProperty(this, "_used", { value: false, writable: true });
    }
    get bodyUsed() { return this._used; }
    get body() { return this._body === null ? null : { locked: false }; }
    _consume() {
      if (this._used) return Promise.reject(new TypeError("Body is unusable: Body has already been read"));
      this._used = true;
      return Promise.resolve(this._body || new Uint8Array(0));
    }
    arrayBuffer() { return this._consume().then((b) => b.slice().buffer); }
    bytes() { return this._consume().then((b) => b.slice()); }
    text() { return this._consume().then((b) => utf8Decode(b)); }
    json() { return this.text().then((t) => JSON.parse(t)); }
    blob() { return this._consume().then((b) => new Blob([b], { type: (this.headers && this.headers.get("content-type")) || "" })); }
    formData() {
      return this.text().then((t) => {
        const f = new FormData();
        for (const [k, v] of new URLSearchParams(t)) f.append(k, v);
        return f;
      });
    }
  }

  class Request extends Body {
    constructor(input, init = {}) {
      super();
      let base = {};
      if (input instanceof Request) {
        base = { method: input.method, headers: input.headers, body: input._body, signal: input.signal, redirect: input.redirect };
        this.url = input.url;
      } else {
        this.url = new URL(String(input)).href;
      }
      this.method = String(init.method || base.method || "GET").toUpperCase();
      this.headers = new Headers(init.headers || base.headers);
      this.signal = init.signal || base.signal || new AbortController().signal;
      this.redirect = init.redirect || base.redirect || "follow";
      this.credentials = init.credentials || "same-origin";
      this.cache = init.cache || "default";
      this.mode = init.mode || "cors";
      let bytes = base.body || null;
      if (init.body !== undefined && init.body !== null) {
        if (this.method === "GET" || this.method === "HEAD") throw new TypeError("Request with GET/HEAD method cannot have body.");
        const ex = extractBody(init.body);
        bytes = ex.bytes;
        if (ex.type && !this.headers.has("content-type")) this.headers.set("content-type", ex.type);
      }
      this._initBody(bytes);
    }
    clone() { return new Request(this); }
  }

  const STATUS = { 200: "OK", 201: "Created", 204: "No Content", 301: "Moved Permanently", 302: "Found", 304: "Not Modified", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 500: "Internal Server Error" };
  class Response extends Body {
    constructor(body = null, init = {}) {
      super();
      this.status = init.status === undefined ? 200 : init.status;
      this.statusText = init.statusText === undefined ? STATUS[this.status] || "" : String(init.statusText);
      this.headers = new Headers(init.headers);
      this.url = init.url || "";
      this.redirected = !!init.redirected;
      this.type = init.type || "default";
      const ex = extractBody(body);
      if (ex.type && !this.headers.has("content-type")) this.headers.set("content-type", ex.type);
      this._initBody(ex.bytes);
    }
    get ok() { return this.status >= 200 && this.status < 300; }
    clone() {
      if (this._used) throw new TypeError("Response body is already used");
      const r = new Response(null, { status: this.status, statusText: this.statusText, headers: this.headers, url: this.url, redirected: this.redirected, type: this.type });
      r._body = this._body ? this._body.slice() : null;
      return r;
    }
    static json(data, init = {}) {
      const headers = new Headers(init.headers);
      if (!headers.has("content-type")) headers.set("content-type", "application/json");
      return new Response(JSON.stringify(data), Object.assign({}, init, { headers }));
    }
    static error() { return new Response(null, { status: 0, statusText: "", type: "error" }); }
    static redirect(url, status = 302) { return new Response(null, { status, headers: { location: new URL(url).href } }); }
  }
  define("Request", Request);
  define("Response", Response);

  define("fetch", (input, init) => {
    let req;
    try {
      req = new Request(input, init);
    } catch (e) {
      return Promise.reject(e);
    }
    if (req.signal.aborted) return Promise.reject(req.signal.reason);
    const headers = [];
    req.headers.forEach((v, k) => headers.push([k, v]));
    const p = asyncOp("fetch", { url: req.url, method: req.method, headers, redirect: req.redirect }, req._body || undefined);
    let onAbort;
    const aborted = new Promise((_, reject) => {
      onAbort = () => reject(req.signal.reason);
      req.signal.addEventListener("abort", onAbort);
    });
    return Promise.race([p, aborted])
      .then(({ value, bytes }) => {
        const res = new Response(null, { status: value.status, statusText: value.statusText, headers: value.headers, url: value.url, redirected: value.redirected, type: "basic" });
        res._body = new Uint8Array(bytes || new ArrayBuffer(0));
        return res;
      })
      .finally(() => req.signal.removeEventListener("abort", onAbort));
  });

  // ---------- host ----------
  const info = send("info");
  const host = {
    platform: info.platform,
    arch: info.arch,
    dir: info.dir,
    dataDir: info.dataDir,
    storage: {
      get: (key) => send("storage.get", { key: String(key) }),
      set: (key, value) => {
        if (value === undefined) return send("storage.remove", { key: String(key) });
        send("storage.set", { key: String(key), value });
      },
      remove: (key) => { send("storage.remove", { key: String(key) }); },
    },
    setting: (key) => send("setting", { key: String(key) }) ?? "",
    t: (text) => send("t", { text: String(text) }),
    language: () => send("language"),
    removeDataDir: (name) => { send("removeDataDir", { name: String(name) }); },
    crypto: {
      md5: (text) => send("md5", { text: String(text) }),
      aesEcbEncrypt: (key, text) => send("aesEcbEncrypt", { key: String(key), text: String(text) }),
    },
    openURL: (url) => { send("openURL", { url: String(url) }); },
    signInPrompt: (prompt) => { send("signInPrompt", prompt || {}); },
    waitForRedirect: (opts) => asyncOp("waitForRedirect", { opts: opts || {} }).then((r) => r.value),
    webSignIn: (opts) => asyncOp("webSignIn", { opts: opts || {} }).then((r) => r.value),
    spawn: () => { throw new Error("host.spawn isn't available on mobile: a phone can't start programs"); },
  };
  Object.freeze(host.storage);
  Object.freeze(host.crypto);
  define("host", Object.freeze(host));

  // ---------- calls into the plugin ----------
  // Like the desktop's helper: calls the export, sync or async, and reports
  // how it went, reading an error's code here.
  Object.defineProperty(g, "__mg_call", {
    value: (json) => {
      const { id, method, params } = JSON.parse(json);
      const done = (ok, value, code, message) => {
        let out;
        try {
          out = { id, ok, value: value === undefined ? null : value, code, message };
          send("result", out);
        } catch (e) {
          send("result", { id, ok: false, value: null, code: "", message: "the plugin answered something that isn't JSON: " + String(e && e.message) });
        }
      };
      const fail = (e) => {
        const isObject = e !== null && typeof e === "object";
        done(false, null, String((isObject && e.code) || ""), isObject ? String(e.message || "") : String(e));
      };
      const exports = g.__mg_exports || {};
      const fn = exports[method];
      if (typeof fn !== "function") return done(false, null, "unsupported", "");
      try {
        Promise.resolve(fn(params === null ? undefined : params)).then((r) => done(true, r), fail);
      } catch (e) {
        fail(e);
      }
    },
  });
})();
