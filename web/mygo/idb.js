// The browser side of the app's Store (lib/core/storage/store.dart): files
// by path in one IndexedDB object store. Used by the app (IdbStore, through
// dart:js_interop) and by plugin workers (plugin_worker.js), so both see the
// same plugins/ and plugin-data/ layout the phone keeps on disk.
const STORE = "files";
const dbs = new Map();

function req(r) {
  return new Promise((resolve, reject) => {
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
}

// iOS can drop a page's IndexedDB connection (the app was in the background,
// the home-screen app was suspended): the cached connection is then closed and
// every transaction on it throws. So a closed connection is forgotten and
// opened again, and nothing waits on IndexedDB forever.
const OPEN_TIMEOUT = 10000;
const TX_TIMEOUT = 20000;

function withTimeout(p, ms, what) {
  let t;
  return Promise.race([
    p,
    new Promise((_, reject) => { t = setTimeout(() => reject(new Error(`IndexedDB didn't answer (${what})`)), ms); }),
  ]).finally(() => clearTimeout(t));
}

export function open(name = "mygo") {
  if (!dbs.has(name)) {
    const p = withTimeout(new Promise((resolve, reject) => {
      let r;
      try {
        r = indexedDB.open(name, 1);
      } catch (e) {
        reject(e);
        return;
      }
      r.onupgradeneeded = () => r.result.createObjectStore(STORE);
      r.onsuccess = () => {
        const db = r.result;
        const forget = () => { if (dbs.get(name) === p) dbs.delete(name); };
        db.onclose = forget;
        db.onversionchange = () => { forget(); db.close(); };
        resolve(db);
      };
      r.onerror = () => reject(r.error || new Error("IndexedDB could not be opened"));
      r.onblocked = () => reject(new Error("IndexedDB is blocked by another tab"));
    }), OPEN_TIMEOUT, "open");
    p.catch(() => { if (dbs.get(name) === p) dbs.delete(name); });
    dbs.set(name, p);
  }
  return dbs.get(name);
}

const norm = (p) => String(p).split("/").filter((s) => s && s !== ".").join("/");
const range = (dir) => IDBKeyRange.bound(dir + "/", dir + "/\uffff");

async function tx(db, mode, fn, retry = true) {
  const d = await open(db);
  let t;
  try {
    t = d.transaction(STORE, mode);
  } catch (e) {
    // InvalidStateError: the connection was closed under us. Open it again once.
    dbs.delete(db);
    if (retry) return tx(db, mode, fn, false);
    throw e;
  }
  const done = new Promise((resolve, reject) => {
    t.oncomplete = resolve;
    t.onerror = () => reject(t.error || new Error("IndexedDB transaction failed"));
    t.onabort = () => reject(t.error || new Error("IndexedDB transaction aborted"));
  });
  done.catch(() => {});
  const s = t.objectStore(STORE);
  return withTimeout((async () => {
    const out = await fn(s);
    await done;
    return out;
  })(), TX_TIMEOUT, mode);
}

export async function get(db, path) {
  const v = await tx(db, "readonly", (s) => req(s.get(norm(path))));
  if (v === undefined || v === null) return null;
  return v instanceof Uint8Array ? v : new Uint8Array(v);
}

export function put(db, path, bytes) {
  const b = bytes instanceof Uint8Array ? bytes.slice() : new Uint8Array(bytes);
  return tx(db, "readwrite", (s) => req(s.put(b, norm(path)))).then(() => null);
}

export function del(db, path) {
  const p = norm(path);
  return tx(db, "readwrite", (s) => Promise.all([req(s.delete(p)), req(s.delete(range(p)))])).then(() => null);
}

export async function list(db, dir) {
  const p = norm(dir);
  const keys = await tx(db, "readonly", (s) => req(p ? s.getAllKeys(range(p)) : s.getAllKeys()));
  const names = new Set();
  for (const k of keys) {
    const rest = p ? String(k).slice(p.length + 1) : String(k);
    names.add(rest.split("/")[0]);
  }
  return [...names];
}

export async function move(db, from, to) {
  const f = norm(from), t = norm(to);
  await tx(db, "readwrite", async (s) => {
    await Promise.all([req(s.delete(t)), req(s.delete(range(t)))]);
    const one = await req(s.get(f));
    if (one !== undefined) {
      await req(s.put(one, t));
      await req(s.delete(f));
    }
    const keys = await req(s.getAllKeys(range(f)));
    for (const k of keys) {
      const v = await req(s.get(k));
      await req(s.put(v, t + String(k).slice(f.length)));
      await req(s.delete(k));
    }
  });
  return null;
}
