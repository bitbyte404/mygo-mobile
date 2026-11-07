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

export function open(name = "mygo") {
  if (!dbs.has(name)) {
    dbs.set(name, new Promise((resolve, reject) => {
      const r = indexedDB.open(name, 1);
      r.onupgradeneeded = () => r.result.createObjectStore(STORE);
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
      r.onblocked = () => reject(new Error("IndexedDB is blocked by another tab"));
    }));
  }
  return dbs.get(name);
}

const norm = (p) => String(p).split("/").filter((s) => s && s !== ".").join("/");
const range = (dir) => IDBKeyRange.bound(dir + "/", dir + "/\uffff");

async function tx(db, mode, fn) {
  const d = await open(db);
  const t = d.transaction(STORE, mode);
  const s = t.objectStore(STORE);
  const out = await fn(s);
  await new Promise((resolve, reject) => {
    t.oncomplete = resolve;
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error || new Error("aborted"));
  });
  return out;
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
