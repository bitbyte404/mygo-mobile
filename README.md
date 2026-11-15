# MyGo 音乐 (mygo_mobile)

English | [简体中文](README.zh-CN.md)

![phone](screenshots/phone.jpg)

A mobile (Flutter) music player that runs **MyGo Music plugins unchanged** — the same
`plugin.json` + `index.js` packages the desktop app [egoist/mygo-music](https://github.com/egoist/mygo-music)
loads. The app has no music service of its own: every catalogue, sign-in, stream and lyric
comes from an installed plugin (e.g. [kugou-lite](https://github.com/bitbyte404/mygo-music-kugou-lite)).

Android first (package `io.github.bitbyte404.mygo_mobile`); the code is plain Flutter + dart:ffi so
iOS can follow.

## Features

- **Looks and moves like MyGo Music**, adapted to touch: MyGo's palette (light and dark, following
  the system), type scale, icons, covers, track rows, pills, the player bar, Now Playing growing out
  of the player on a spring with the artwork's colors behind it, and synced lyrics that glide to the
  line sung. No stock Material chrome. See [docs/DESIGN.md](docs/DESIGN.md).
- **Adaptive layout** by width class: phones get a tab bar (首页 / 搜索 / 我的) and a mini player that
  expands into Now Playing (tap, or drag it up; drag Now Playing down to close); tablets, foldables
  and landscape (≥ 840 dp) get the desktop layout with the plugin's navigation in a sidebar, card
  grids, the player bar, and Now Playing with cover and lyrics side by side; 600–840 dp an icon rail.
- **Edge to edge**: content and artwork draw under transparent status and navigation bars (no
  contrast scrim, display cutouts on the short edges); bar icons follow the theme and Now Playing's
  artwork; the tab bar and mini player sit above the gesture bar or the 3-button bar.
- **Plugin runtime** — each plugin runs in its own QuickJS-ng engine (`libmygojs.so`) on its own
  background isolate, with the desktop host API re-implemented in Dart: storage, settings,
  locales (`host.t`), md5 / AES / RSA, `fetch` limited to the plugin's declared network
  permission, timers, and the sign-in prompt (QR code / link).
- **Install plugins** from a GitHub repository (default-branch zip via codeload; `plugin.json` at the
  root or one folder deep) or from a local zip, with a permission review before install.
  Update checks read the repo's `plugin.json` from raw.githubusercontent.com (no GitHub API rate limit).
  Deep link `mygo-music://install-plugin?repo=owner/repo` (as the desktop app answers) opens the installer.
- **Browse** — the plugin's home (under a greeting), pages, albums, artists, playlists, "see all" pages, stations.
  Pages are kept for the session: going back to a tab or a page shows it at once and refreshes it
  quietly when it is stale, keeping its scroll position (see docs/DESIGN.md, Loading).
- **Search** — songs / albums / artists / playlists with paging and suggestions.
- **我的** — account and QR sign-in, liked songs (Play all plays every liked song, loading the
  remaining pages first), recently played (the source's list and this device's, one entry),
  playlists, saved albums, the plugin's own pages, plugins, settings.
- **Now playing** — queue, quality choice (standard … lossless/Hi-Res where the plugin offers it,
  with a 无损 badge), synced lyrics (line and word timing, tap a line to seek), comments when the
  plugin exports them.
- **Playback** — just_audio + audio_service: background play, notification and lock-screen
  controls, media buttons. Stream URLs are requested from the plugin when each track starts
  (they expire), with the headers the plugin returns.
- UI in Simplified Chinese and English (with Flutter's own localizations for both).

## Architecture

Layered `core` → `data` → `features`, with the design system in `ui` and the composition root in
`app`; plugins run behind a `PluginRuntime` platform interface (QuickJS-ng over FFI today, a web
runtime can slot in). Details, the runtime/isolate model, a diagram, and how plugins map to
features: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
lib/
  main.dart · app/ (bootstrap, services, app)
  core/      models, errors, plugin manifest, runtime interface + quickjs/ (JsEngine, PluginHost, PluginWorker)
  data/      plugins (manager, installer), library (MusicRepository, LikedStore), player, settings, navigation
  ui/        design system: theme (tokens, icons), components, layout
  features/  shell, home, browse, search, album, artist, playlist, liked, recent, stations, library,
             now_playing, lyrics, account, plugins, settings, common
  l10n/      the app's strings (zh-CN, en)
assets/js/prelude.js    JS side of the host API given to every plugin
native/                 QuickJS-ng amalgamation + mygojs.c bridge; build.sh
android/app/src/main/jniLibs/<abi>/libmygojs.so   prebuilt by native/build.sh android
```

Plugin answers use the desktop app's JSON shapes (`internal/music/music.go`); times are milliseconds.

## Web

The same app runs in the browser, served with a small Go relay (plugin traffic, audio streams,
cover art, GitHub installs) behind an access token: one container.

```bash
echo "RELAY_TOKEN=$(openssl rand -hex 24)" > .env && mkdir -p data && sudo chown 65532:65532 data
docker compose up -d --build        # http://127.0.0.1:18090, put TLS in front
```

Plugins run in a Web Worker in the browser; their data stays in IndexedDB. Architecture, security
model, env vars and deployment: [docs/WEB.md](docs/WEB.md). Screenshots: `screenshots/web.jpg`.

## Building

Normal machine (x86_64 Linux/macOS with Flutter + Android SDK + NDK r28):

```bash
native/build.sh android          # only if native/*.c changed; prebuilt .so files are committed
flutter pub get
flutter build apk --release --split-per-abi
```

### Release signing

`android/app/build.gradle.kts` reads `android/key.properties`:

```
storePassword=...
keyPassword=...
keyAlias=mygo
storeFile=../keystore/release.jks
```

Generate a key with e.g.
`keytool -genkeypair -keystore android/keystore/release.jks -alias mygo -keyalg RSA -keysize 4096 -validity 10000`.
Both `android/key.properties` and `android/keystore/` are gitignored. Without `key.properties`
the release build falls back to the debug key. **Back up the keystore** — updates to an installed
APK must be signed with the same key.

## Releases

Pushing a tag `v<version>` (it must match `version:` in `pubspec.yaml`) runs
[`.github/workflows/release.yml`](.github/workflows/release.yml): signed split APKs
(arm64-v8a, armeabi-v7a, x86_64) and a `linux/amd64` + `linux/arm64` image
`ghcr.io/bitbyte404/mygo-mobile:<version>` (also `latest`), then a GitHub Release with the APKs
and `SHA256SUMS.txt`. The signing key comes from the repository secrets
`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

## Tests

```bash
flutter test test/unit                      # no network: controllers, navigation, lyrics, design tokens
native/build.sh host
MYGOJS_LIB=native/build/host/libmygojs.so flutter test test/kugou_live_test.dart
MYGOJS_LIB=native/build/host/libmygojs.so flutter test test/stack_stress_test.dart   # 4 plugin isolates, 480 calls
```

Behind a proxy, give the plugin traffic an unauthenticated proxy with `MYGO_HTTP_PROXY=host:port`
and keep the test runner's own localhost WebSocket
off the proxy with `NO_PROXY=127.0.0.1,localhost`.

The live test needs the network, a checkout of kugou-lite (`--dart-define=KUGOU_DIR=...`) and a signed-in fixture at
`test/fixtures/kugou-data/kugou-lite/storage.json` (gitignored — it holds a sign-in). It checks
exports, account, home, recent, search (all kinds), liked, a lossless stream whose first bytes are
`fLaC`, standard stream, lyrics, comments, and that an unexported method fails as `unsupported`.
Results go to `build/kugou_live_results.json`.

## Known gaps / not yet verified

Verified headlessly only (plugin runtime + kugou-lite live calls, UI at phone/tablet sizes,
release build and signing). Not yet verified on a real device:

- actual audio playback (including FLAC / Hi-Res decoding by ExoPlayer),
- background play, notification and lock-screen controls,
- QR-code sign-in flow in the UI,
- installing a plugin from a zip via the file picker,
- the `mygo-music://install-plugin` deep link,
- touch feel: the mini player drag, pull-to-close, lyrics scrolling and frame rate on real hardware,
- edge-to-edge on a device (status/navigation bar colors, 3-button navigation, cutouts) and the
  Android back gesture,
- iOS: not built at all (needs a Mac; `libmygojs` would be linked statically / as an xcframework).

Other gaps: no downloads / offline cache; no desktop-only plugin exports (e.g. `remoteState`
returns `unsupported`).
