# MyGo 音乐 on the web

The same Flutter app, compiled to JavaScript (`flutter build web`), served together with a small Go
server, **the relay** (`relay/`). One container, one origin.

## Architecture

```
browser ──────────────── https://music.example ───────────────── mygo-relay (Go, :8080)
  Flutter app (main.dart.js, CanvasKit)          GET /…              static build/web (SPA, gzip, COOP/COEP)
  plugin: module Worker web/mygo/plugin_worker.js  POST /relay         plugin fetch → allowed hosts only
    host API in JS (storage, settings, crypto)     GET  /stream        audio, Range passed through (206)
    storage: IndexedDB "mygo" (same layout as      GET  /img           cover art (image/* only)
    the phone: plugins/<id>/, plugin-data/<id>/)   /api/github/*       GitHub zip/manifest downloads
  audio: <audio> via just_audio → /stream          /api/plugins        registry = the allowlist
  fonts: web/fonts/NotoSansSC-*.woff2 (bundled)    /api/session        token → HttpOnly cookie
                                                   /gfonts/*           cached Flutter fallback fonts
```

- **Plugins run in the browser**, not on the server: each plugin is a module Worker with the
  desktop host API re-implemented in JS. Their `fetch` goes to `/relay` in an envelope (so the
  plugin's own Cookie/User-Agent/Referer headers survive), and the answer comes back with status,
  headers (Set-Cookie too) and bytes. Sockets, XHR, EventSource and importScripts are removed
  from the worker.
- **Plugin data stays in the browser** (IndexedDB). The relay keeps no sign-ins, cookies or
  plugin storage; its data dir only holds `plugins.json` (which plugins are registered and the
  hosts each declared).
- **Audio** plays from `/stream?plugin=<id>&url=…&h=…`: the relay passes Range through, so the
  browser gets `206` and seeks; FLAC (lossless) plays natively in Chromium/Firefox/Safari.
- **Fonts**: the CJK font (Noto Sans SC Regular + Bold, woff2) and Roboto are bundled; CanvasKit
  is bundled (`--no-web-resources-cdn`). Nothing is loaded from Google or a CDN. Rare glyphs
  (emoji, other scripts) use Flutter's fallback fonts through `/gfonts/` (the relay fetches them
  from fonts.gstatic.com once and caches them; if that is unreachable those glyphs are just missing).

## Security model

- **RELAY_TOKEN** (set it on anything reachable by others). Every API, relay, stream and image
  request needs it; the app asks once and trades it for an HttpOnly, SameSite=Strict cookie that
  holds an HMAC of the token, not the token (changing the token signs everyone out). Wrong tokens
  are slowed down. `Authorization: Bearer <token>` works too (scripts).
- **Allowlist**: `/relay` only reaches the hosts the registered plugins declare in
  `permissions.network`. A GitHub plugin is registered by the relay downloading the repository
  itself, so a client cannot claim hosts the manifest does not list. `RELAY_REPOS` limits which
  repositories may register at all. `/stream` also accepts the declared hosts' registrable domains
  (audio CDNs) plus `RELAY_MEDIA_HOSTS`, and only answers audio. `/img` answers images only; behind
  a token it may reach any public host (cover CDNs are never in manifests), without a token only
  the plugin domains.
- **No private network**: targets (and every redirect hop) must resolve to public addresses
  (loopback, RFC 1918, link-local, CGNAT, ULA… are refused) unless `RELAY_ALLOW_PRIVATE=1` (tests).
- The browser's own cookies never go upstream. The page is cross-origin isolated (COOP/COEP/CORP).
- The container runs distroless as `nonroot`, read-only except `/data`.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `RELAY_TOKEN` | (none) | Access token. Unset = open (a warning is logged). |
| `LISTEN` | `:8080` | Listen address. |
| `RELAY_STATIC` | `web` (`/app/web` in the image) | The Flutter web build. |
| `RELAY_DATA` | `data` (`/data` in the image) | Where `plugins.json` is kept. |
| `RELAY_REPOS` | (any) | Comma list of `owner/repo` allowed to register. |
| `RELAY_MEDIA_HOSTS` | | Extra hosts for `/stream` and `/img` (`*.example.com` patterns). |
| `RELAY_ALLOW_MANIFEST_UPLOAD` | off | Let zip-installed plugins register without a token. |
| `RELAY_SECURE_COOKIE` | off | Mark the session cookie Secure (set it behind https). |
| `RELAY_ALLOW_PRIVATE` | off | Allow private addresses (tests only). |
| `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` | | Outbound proxy for the relay's requests. |

## Build and run

```bash
# full build in Docker (Flutter + Go), multi-arch capable
docker build -t mygo-web .

# or build here, ship files (fast on a small server)
flutter build web --release --no-web-resources-cdn
(cd relay && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o ../dist/mygo-relay .)
docker build -f Dockerfile.prebuilt -t mygo-web .

# without Docker
RELAY_TOKEN=… RELAY_STATIC=build/web RELAY_DATA=./data ./dist/mygo-relay
```

## Deploy (docker compose)

```bash
echo "RELAY_TOKEN=$(openssl rand -hex 24)" > .env
mkdir -p data && sudo chown 65532:65532 data
docker compose up -d --build          # MYGO_DOCKERFILE=Dockerfile.prebuilt for prebuilt files
```

It listens on `127.0.0.1:18090` only; put a TLS reverse proxy in front, e.g. Caddy:

```
music.example.com {
    reverse_proxy 127.0.0.1:18090
}
```

Serving under a sub-path works (`flutter build web --base-href /music/` and proxy `/music/*` with
the prefix stripped). Health: `GET /healthz`; the image's HEALTHCHECK runs `mygo-relay -healthcheck`.

Install a plugin by opening `https://music.example.com/?install=owner/repo`, or from the plugins page.

## Testing

`relay/`: `go test ./...`. End to end (what was verified): relay with a temp `RELAY_DATA`, headless
Chromium — token gate, install kugou-lite from GitHub, signed-in storage seeded into IndexedDB,
home sections, search 周杰伦 晴天, 我喜欢, play 晴天 lossless (`/stream` 206 `audio/flac`, first bytes
`fLaC`, `currentTime` advancing), lyrics. Screenshots: `screenshots/web.jpg`.
