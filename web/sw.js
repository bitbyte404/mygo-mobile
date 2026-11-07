// MyGo 音乐's service worker: keeps the app shell (index, main.dart.js,
// CanvasKit, fonts, icons, the plugin host in mygo/) so the home-screen app
// opens at once and works offline up to its first request to the relay.
//
// - The page (navigations, index.html, flutter_bootstrap.js, version.json,
//   manifest.json) is network first, cached as a fallback.
// - Everything else of the shell is cache first, in a cache named for this
//   build; BUILD is stamped by tool/stamp_sw.sh after `flutter build web`
//   (a hash of the build), so every new build is a new worker and a new cache,
//   and the old cache is deleted when it takes over.
// - The relay is never cached: /api, /relay, /stream, /img (and /gfonts,
//   which the relay caches itself).
// - A new worker waits until the page says so (index.html shows "Reload"),
//   so code never changes under a running app.
const BUILD = '__MYGO_BUILD__';
const CACHE = `mygo-shell-${BUILD}`;
const SCOPE = new URL(self.registration.scope);
const u = (p) => new URL(p, SCOPE).href;

const PRECACHE = [
  '', 'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json', 'favicon.png', 'favicon.ico',
  'apple-touch-icon.png', 'icons/Icon-192.png', 'icons/Icon-512.png',
  'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
  'mygo/idb.js', 'mygo/plugin_worker.js', 'mygo/host_crypto.js',
  'assets/FontManifest.json', 'assets/AssetManifest.bin.json', 'assets/assets/js/prelude.js',
  'fonts/NotoSansSC-Regular.woff2', 'fonts/NotoSansSC-Bold.woff2',
].map(u);

const NEVER = ['api/', 'relay', 'stream', 'img', 'gfonts/', 'healthz', 'sw.js'];
const NETWORK_FIRST = ['', 'index.html', 'flutter_bootstrap.js', 'version.json', 'manifest.json'].map(u);

function relPath(url) {
  return url.href.startsWith(SCOPE.href) ? url.href.slice(SCOPE.href.length).split(/[?#]/)[0] : null;
}

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // One by one, so a file a build doesn't have (an optional font) doesn't
    // fail the whole install.
    await Promise.all(PRECACHE.map(async (url) => {
      try {
        const res = await fetch(url, { cache: 'no-cache' });
        if (res.ok) await cache.put(url, res);
      } catch (_) {}
    }));
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('mygo-shell-') && key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== SCOPE.origin) return;
  const rel = relPath(url);
  if (rel === null) return;
  if (NEVER.some((p) => (p.endsWith('/') ? rel.startsWith(p) : rel === p || rel.startsWith(p + '/')))) return;
  if (req.headers.has('range')) return; // media, never from here

  if (req.mode === 'navigate' || NETWORK_FIRST.includes(u(rel))) {
    event.respondWith(networkFirst(req, req.mode === 'navigate' ? u('index.html') : null));
    return;
  }
  event.respondWith(cacheFirst(req));
});

async function networkFirst(req, fallbackUrl) {
  const cache = await caches.open(CACHE);
  try {
    const res = await fetch(req, { cache: 'no-cache' });
    if (res.ok && res.type === 'basic') {
      // A navigation with a query (?install=…) is stored as the index.
      await cache.put(fallbackUrl || req, res.clone());
    }
    return res;
  } catch (e) {
    const hit = (await cache.match(req, { ignoreSearch: true })) || (fallbackUrl && (await cache.match(fallbackUrl)));
    if (hit) return hit;
    throw e;
  }
}

async function cacheFirst(req) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(req, { ignoreSearch: false });
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok && res.type === 'basic' && res.status === 200) {
    try {
      await cache.put(req, res.clone());
    } catch (_) {}
  }
  return res;
}
