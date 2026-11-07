// One MyGo Music plugin, running in the browser's own JavaScript engine in
// this module Worker: the web counterpart of the phone's PluginHost (Dart) +
// assets/js/prelude.js (QuickJS). It gives the plugin the desktop app's host
// API (internal/plugin/host.go) with the same semantics:
//
//   host.storage   get/set/remove, synchronous; kept in IndexedDB at
//                  plugin-data/<id>/storage.json (the phone's file layout)
//   host.setting   plugin-data/<id>/settings.json
//   host.t / language, host.crypto.md5 / aesEcbEncrypt (sync, hex),
//   host.openURL, host.signInPrompt (events to the app), errors with codes
//   fetch          through the relay (/relay): the plugin's headers (Cookie,
//                  User-Agent, Referer... which a page may not set) travel
//                  in an envelope; the answer comes back with its status,
//                  headers (Set-Cookie too) and bytes. Limited to the
//                  manifest's network permission here and again at the relay.
//
// The worker reads the plugin's files itself from IndexedDB (plugins/<id>/).
// Messages are JSON strings: in {op: init|call|setSetting|language|ping}, out
// {type: ready|failed|result|event|pong}.
import * as idb from "./idb.js";
import { md5, aesEcbEncrypt } from "./host_crypto.js";

const nativeFetch = self.fetch.bind(self);
// What a plugin can't have on the phone either, and would let it go around
// the relay: sockets, XHR, server-sent events, classic script loading.
for (const name of ["WebSocket", "WebSocketStream", "XMLHttpRequest", "EventSource", "WebTransport", "importScripts"]) {
  try {
    delete self[name];
    if (name in self) Object.defineProperty(self, name, { value: undefined, configurable: false, writable: false });
  } catch (_) {}
}

const post = (m) => self.postMessage(JSON.stringify(m));
const event = (type, data) => post({ type: "event", event: type, data });
const dec = new TextDecoder();
const enc = new TextEncoder();

let db = "mygo";
let manifest = null;
let dataDir = "";
let pluginDir = "";
let relayUrl = "relay";
let language = "zh-CN";
let locales = {};
let storage = {};
let settings = {};
let exportsNs = {};

async function readText(path) {
  const b = await idb.get(db, path);
  return b ? dec.decode(b) : null;
}
async function readJson(path) {
  const t = await readText(path);
  if (t === null) return null;
  try {
    return JSON.parse(t);
  } catch {
    return null;
  }
}

// Writes are queued so they land in order, as the phone's synchronous file writes do.
let writes = Promise.resolve();
function persist(name, value) {
  const bytes = enc.encode(JSON.stringify(value));
  writes = writes.then(() => idb.put(db, `${dataDir}/${name}`, bytes)).catch((e) => log("error", `saving ${name}: ${e}`));
  return writes;
}

const fmt = (a) => {
  if (typeof a === "string") return a;
  if (a instanceof Error) return `${a.name}: ${a.message}`;
  try {
    return JSON.stringify(a, (k, v) => (typeof v === "bigint" ? v.toString() + "n" : v));
  } catch {
    return String(a);
  }
};
function log(level, msg) {
  event("log", { level, msg, plugin: manifest ? manifest.id : pluginDir });
}
for (const level of ["log", "info", "warn", "error", "debug"]) {
  console[level] = (...args) => log(level, args.map(fmt).join(" "));
}

async function loadLocales() {
  locales = {};
  if (language === "en") return;
  const m = await readJson(`${pluginDir}/locales/${language}.json`);
  if (m && typeof m === "object") for (const k of Object.keys(m)) locales[k] = String(m[k]);
}

// ---------- host.allowHosts, as the desktop's webapi.AllowHosts ----------
function hostAllowed(host) {
  const h = String(host).toLowerCase();
  for (let a of manifest.permissions.network) {
    a = String(a).toLowerCase();
    if (a === "*") return true;
    if (a.startsWith("*.")) {
      if (h.endsWith(a.slice(1))) return true;
    } else if (a === h) return true;
  }
  return false;
}

// ---------- fetch through the relay ----------
function headerList(h) {
  const out = [];
  if (!h) return out;
  if (h instanceof Headers) h.forEach((v, k) => out.push([k, v]));
  else if (Array.isArray(h) || typeof h[Symbol.iterator] === "function") for (const [k, v] of h) out.push([String(k).toLowerCase(), String(v)]);
  else for (const k of Object.keys(h)) out.push([k.toLowerCase(), String(h[k])]);
  return out;
}

function b64(str) {
  const bytes = enc.encode(str);
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
function unb64(s) {
  const bin = atob(s);
  const b = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) b[i] = bin.charCodeAt(i);
  return dec.decode(b);
}

const NULL_BODY = new Set([101, 103, 204, 205, 304]);

async function relayFetch(input, init = {}) {
  let url, method = "GET", headers = [], body = null, signal, redirect = "follow";
  if (input instanceof Request) {
    url = input.url;
    method = input.method;
    headers = headerList(input.headers);
    signal = input.signal;
    redirect = input.redirect;
    if (method !== "GET" && method !== "HEAD") body = await input.arrayBuffer();
  } else {
    url = String(input instanceof URL ? input.href : input);
  }
  let u;
  try {
    u = new URL(url);
  } catch {
    throw new TypeError(`Invalid URL: ${url}`);
  }
  if (init.method) method = String(init.method).toUpperCase();
  if (init.headers) headers = headerList(init.headers);
  if (init.signal) signal = init.signal;
  if (init.redirect) redirect = init.redirect;
  if (init.body !== undefined && init.body !== null) {
    if (method === "GET" || method === "HEAD") throw new TypeError("Request with GET/HEAD method cannot have body.");
    const r = new Response(init.body); // serialises strings, forms, blobs, buffers, streams the standard way
    body = await r.arrayBuffer();
    const ct = r.headers.get("content-type");
    if (ct && !headers.some(([k]) => k.toLowerCase() === "content-type")) headers.push(["content-type", ct]);
  }
  if (!manifest.permissions.network.length) throw new TypeError("fetch: the plugin has no network permission");
  if (u.protocol !== "http:" && u.protocol !== "https:") throw new TypeError(`fetch: not a web address: ${url}`);
  if (!hostAllowed(u.hostname)) throw new TypeError(`webapi: host ${u.hostname.toLowerCase()} is not allowed`);
  if (signal && signal.aborted) throw signal.reason ?? new DOMException("This operation was aborted", "AbortError");

  const q = `plugin=${encodeURIComponent(manifest.id)}&url=${encodeURIComponent(u.href)}`;
  let res;
  try {
    res = await nativeFetch(`${relayUrl}?${q}`, {
      method: "POST",
      headers: { "X-Relay-Method": method, "X-Relay-Headers": b64(JSON.stringify(headers)), "X-Relay-Redirect": redirect },
      body,
      signal,
      credentials: "same-origin",
      cache: "no-store",
    });
  } catch (e) {
    if (e && e.name === "AbortError") throw e;
    throw new TypeError(`fetch failed: ${e && e.message ? e.message : e}`);
  }
  if (res.headers.get("X-Relay-Error")) {
    let msg = `relay answered ${res.status}`;
    try {
      const j = await res.json();
      if (j && j.error) msg = j.error;
    } catch {}
    if (res.status === 401) event("relayAuth", {});
    throw new TypeError(msg.startsWith("webapi:") || msg.startsWith("fetch") ? msg : `fetch failed: ${msg}`);
  }
  const status = Number(res.headers.get("X-Relay-Status")) || 200;
  const statusText = res.headers.get("X-Relay-Status-Text") || "";
  const finalUrl = res.headers.get("X-Relay-Url") || u.href;
  const redirected = res.headers.get("X-Relay-Redirected") === "1";
  const list = JSON.parse(unb64(res.headers.get("X-Relay-Headers") || "W10="));
  const buf = await res.arrayBuffer();
  const out = new Response(NULL_BODY.has(status) ? null : buf, { status: status < 200 || status > 599 ? 200 : status, statusText });
  const h = new Headers(); // guard "none": keeps Set-Cookie, which a Response's own headers drop
  for (const [k, v] of list) h.append(k, v);
  Object.defineProperties(out, {
    headers: { value: h },
    url: { value: finalUrl },
    redirected: { value: redirected },
    status: { value: status },
    ok: { value: status >= 200 && status < 300 },
  });
  return out;
}

// ---------- host ----------
function makeHost(info) {
  const host = {
    platform: info.platform,
    arch: info.arch,
    dir: pluginDir,
    dataDir,
    storage: {
      get: (key) => {
        const k = String(key);
        if (!Object.prototype.hasOwnProperty.call(storage, k)) return undefined;
        return JSON.parse(JSON.stringify(storage[k]));
      },
      set: (key, value) => {
        if (value === undefined) return host.storage.remove(key);
        const v = JSON.stringify(value);
        storage[String(key)] = v === undefined ? null : JSON.parse(v);
        persist("storage.json", storage);
      },
      remove: (key) => {
        delete storage[String(key)];
        persist("storage.json", storage);
      },
    },
    setting: (key) => settings[String(key)] ?? "",
    t: (text) => {
      const tr = locales[String(text)];
      return tr ? tr : String(text);
    },
    language: () => language,
    removeDataDir: (name) => {
      name = String(name);
      const parts = name.split("/").filter((p) => p && p !== ".");
      if (!name || name.startsWith("/") || parts.includes("..") || !parts.length) throw new Error(`not a folder of the plugin's data: ${name}`);
      writes = writes.then(() => idb.del(db, `${dataDir}/${parts.join("/")}`));
    },
    crypto: {
      md5: (text) => md5(String(text)),
      aesEcbEncrypt: (key, text) => aesEcbEncrypt(String(key), String(text)),
    },
    openURL: (url) => {
      let u;
      try {
        u = new URL(String(url));
      } catch {}
      if (!u || (u.protocol !== "http:" && u.protocol !== "https:")) throw new Error(`not a web address: ${url}`);
      event("openURL", { url: String(url), plugin: manifest.id });
    },
    signInPrompt: (prompt) => {
      const p = prompt || {};
      event("signInPrompt", { qr: String(p.qr ?? ""), text: String(p.text ?? ""), plugin: manifest.id });
    },
    waitForRedirect: () => Promise.reject(new Error("host.waitForRedirect isn't available in a browser")),
    webSignIn: () => Promise.reject(new Error("host.webSignIn isn't available in the web app yet")),
    spawn: () => {
      throw new Error("host.spawn isn't available in a browser: a web page can't start programs");
    },
  };
  Object.freeze(host.storage);
  Object.freeze(host.crypto);
  return Object.freeze(host);
}

// ---------- calls ----------
async function call(id, method, params) {
  const reply = (ok, value, code, message) => {
    try {
      post({ type: "result", id, ok, value: value === undefined ? null : value, code: code || "", message: message || "" });
    } catch (e) {
      post({ type: "result", id, ok: false, value: null, code: "", message: "the plugin answered something that isn't JSON: " + String(e && e.message) });
    }
  };
  const fn = exportsNs[method];
  if (typeof fn !== "function") return reply(false, null, "unsupported", "");
  try {
    const v = await fn(params === null ? undefined : params);
    reply(true, v);
  } catch (e) {
    const isObject = e !== null && typeof e === "object";
    reply(false, null, String((isObject && e.code) || ""), isObject ? String(e.message || "") : String(e));
  }
}

async function init(m) {
  db = m.db || "mygo";
  pluginDir = m.dir;
  relayUrl = m.relay || "relay";
  language = m.language || "zh-CN";
  const mj = await readText(`${pluginDir}/plugin.json`);
  if (mj === null) throw Object.assign(new Error(`${pluginDir}/plugin.json is missing`), { code: "" });
  manifest = JSON.parse(mj);
  manifest.permissions = manifest.permissions || {};
  manifest.permissions.network = Array.isArray(manifest.permissions.network) ? manifest.permissions.network.map(String) : [];
  manifest.main = manifest.main || "index.js";
  if (String(manifest.main).endsWith(".ts")) throw new Error(`TypeScript plugins (${manifest.main}) are not supported in the web app yet`);
  dataDir = `${m.dataRoot}/${manifest.id}`;
  storage = (await readJson(`${dataDir}/storage.json`)) || {};
  const st = (await readJson(`${dataDir}/settings.json`)) || {};
  settings = {};
  for (const k of Object.keys(st)) settings[k] = String(st[k]);
  await loadLocales();
  const src = await readText(`${pluginDir}/${manifest.main}`);
  if (src === null) throw new Error(`${manifest.main} is missing`);
  Object.defineProperty(self, "host", { value: makeHost(m), enumerable: false, configurable: false, writable: false });
  Object.defineProperty(self, "fetch", { value: relayFetch, enumerable: true, configurable: false, writable: false });
  const url = URL.createObjectURL(new Blob([src], { type: "text/javascript" }));
  try {
    exportsNs = await import(url);
  } finally {
    URL.revokeObjectURL(url);
  }
  const exportNames = Object.keys(exportsNs).filter((k) => typeof exportsNs[k] === "function");
  return { manifest: mj, exports: exportNames, settings };
}

self.onmessage = async (e) => {
  let m;
  try {
    m = JSON.parse(e.data);
  } catch {
    return;
  }
  switch (m.op) {
    case "init":
      try {
        const r = await init(m);
        post({ type: "ready", ...r });
      } catch (err) {
        post({ type: "failed", code: String((err && err.code) || ""), message: String((err && err.message) || err) });
      }
      break;
    case "call":
      call(m.id, m.method, m.params);
      break;
    case "setSetting":
      settings[m.key] = String(m.value);
      await persist("settings.json", settings);
      if (typeof exportsNs.setSetting === "function") await call(m.id, "setSetting", { key: m.key, value: m.value });
      else post({ type: "result", id: m.id, ok: true, value: null });
      break;
    case "language":
      language = m.language;
      await loadLocales();
      post({ type: "result", id: m.id, ok: true, value: null });
      break;
    case "ping":
      post({ type: "pong", id: m.id });
      break;
    case "flush":
      await writes;
      post({ type: "result", id: m.id, ok: true, value: null });
      break;
  }
};
