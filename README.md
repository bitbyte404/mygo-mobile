# MyGo 音乐 (mygo_mobile)

A mobile (Flutter) music player that runs **MyGo Music plugins unchanged** — the same
`plugin.json` + `index.js` packages the desktop app [egoist/mygo-music](https://github.com/egoist/mygo-music)
loads. The app has no music service of its own: every catalogue, sign-in, stream and lyric
comes from an installed plugin (e.g. [kugou-lite](https://github.com/bitbyte404/mygo-music-kugou-lite)).

Android first (package `io.github.bitbyte404.mygo_mobile`); the code is plain Flutter + dart:ffi so
iOS can follow.

## Features

- **Plugin runtime** — each plugin runs in its own QuickJS-ng engine (`libmygojs.so`) on its own
  background isolate, with the desktop host API re-implemented in Dart: storage, settings,
  locales (`host.t`), md5 / AES / RSA, `fetch` limited to the plugin's declared network
  permission, timers, and the sign-in prompt (QR code / link).
- **Install plugins** from a GitHub repository (default-branch zip via codeload; `plugin.json` at the
  root or one folder deep) or from a local zip, with a permission review before install.
  Update checks read the repo's `plugin.json` from raw.githubusercontent.com (no GitHub API rate limit).
  Deep link `mygo-music://install-plugin?repo=owner/repo` (as the desktop app answers) opens the installer.
- **Browse** — the plugin's home, pages, albums, artists, playlists, "see more" pages.
- **Search** — tracks / albums / artists / playlists with paging.
- **Me** — account, liked tracks, recent plays, the plugin's own pages.
- **Now playing** — queue, quality choice (standard … lossless/Hi-Res where the plugin offers it),
  synced lyrics (line and word timing), comments when the plugin exports them.
- **Playback** — just_audio + audio_service: background play, notification and lock-screen
  controls, media buttons. Stream URLs are requested from the plugin when each track starts
  (they expire), with the headers the plugin returns.
- UI in Simplified Chinese and English.

## Architecture

```
lib/
  main.dart, services.dart, app_state.dart, i18n.dart, models.dart
  runtime/
    js_engine.dart      dart:ffi bindings to libmygojs (QuickJS-ng + native/mygojs.c)
    plugin_host.dart    one plugin: module + host API (storage, fetch, crypto, timers, sign-in)
    plugin_worker.dart  runs a PluginHost on a background isolate; UI talks to it by messages
    manifest.dart       plugin.json, as the desktop app reads it
  plugins/
    installer.dart      GitHub / zip install, permission review, update checks
    plugin_manager.dart installed plugins, one isolate each, which one is active
  player/player.dart    just_audio + audio_service, queue, per-track stream lookup
  ui/                   home shell, browse, search, me, detail pages, now playing, plugins, settings
assets/js/prelude.js    JS side of the host API given to every plugin
native/                 QuickJS-ng amalgamation + mygojs.c bridge; build.sh
android/app/src/main/jniLibs/<abi>/libmygojs.so   prebuilt by native/build.sh android
test/kugou_live_test.dart   headless live test of the kugou-lite plugin through this runtime
```

Plugin answers use the desktop app's JSON shapes (`internal/music/music.go`); times are milliseconds.

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

### The arm64 Linux build box (how the first APKs were built)

The APKs were built on an aarch64 Linux sandbox, which Flutter/Android do not officially support
as a host. Workarounds, all under `/workspace/work/tools` (`source tools/env.sh` first):

- **Downloads through a local proxy**: `tools/localproxy.py` (127.0.0.1:3128) adds upstream auth;
  `env.sh` points Java/Gradle at it via `JAVA_TOOL_OPTIONS`. `./build_apk.sh` starts it if needed.
- **Flutter mirror**: `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`.
- **gen_snapshot**: Flutter ships no linux-arm64 gen_snapshot for Android targets, so
  `artifacts/engine/android-*/linux-arm64/gen_snapshot` are shell wrappers running the x86_64 binary
  under qemu-user (`tools/x86`, extracted from Debian packages).
- **aapt2**: an arm64 build (2.19), reached through `tools/aapt2-wrap/aapt2`, set by
  `android.aapt2FromMavenOverride` in `android/gradle.properties`. The wrapper rewrites `--opt=value`
  into `--opt value`: AGP 9.1 calls `aapt2 optimize --resource-path-shortening-map=…`, which this
  aapt2 rejects (exit 1), and AGP then *silently* packages an APK with no `AndroidManifest.xml` or
  `resources.arsc`. `build_apk.sh` now fails the build if any APK lacks the manifest or `libmygojs.so`.
  (On another machine, delete that `gradle.properties` line.)
- **Memory**: 8 GB, no swap. Gradle heap is capped at 2 GB and the Kotlin daemon at 768 MB in
  `android/gradle.properties`; with the old 3 GB heap the daemon was OOM-killed while the qemu
  gen_snapshot runs. A clean release build takes ~25 min here (gen_snapshot under qemu dominates).
- **NDK stand-in 28.2.13676358**: r28c sysroot/headers with toolchain binaries symlinked to the system
  LLVM 19, so AGP accepts an installed NDK. No NDK compile happens in the Gradle build;
  `libmygojs.so` is built by `native/build.sh` with system clang against the NDK sysroot.
- **path_provider_android pinned to 2.2.23** (`dependency_overrides`): 2.3.x pulls in `package:jni`,
  which compiles C with the NDK toolchain at build time.

On a normal x86_64 host none of this is needed except the pin (harmless) and signing.

## Tests

```bash
native/build.sh host
MYGOJS_LIB=native/build/host/libmygojs.so flutter test test/kugou_live_test.dart
```

Behind a proxy, give the plugin traffic an unauthenticated proxy with `MYGO_HTTP_PROXY=host:port`
(here: the local forwarder, `127.0.0.1:3128`) and keep the test runner's own localhost WebSocket
off the proxy with `NO_PROXY=127.0.0.1,localhost`.

The live test needs the network, a checkout of kugou-lite (`--dart-define=KUGOU_DIR=...`, default
`/workspace/work/mygo-music-kugou-lite`) and a signed-in fixture at
`test/fixtures/kugou-data/kugou-lite/storage.json` (gitignored — it holds a sign-in). It checks
exports, account, home, recent, search (all kinds), liked, a lossless stream whose first bytes are
`fLaC`, standard stream, lyrics, comments, and that an unexported method fails as `unsupported`.
Results go to `build/kugou_live_results.json`.

## Known gaps / not yet verified

Verified headlessly only (plugin runtime + kugou-lite live calls, release build and signing).
Not yet verified on a real device:

- actual audio playback (including FLAC / Hi-Res decoding by ExoPlayer),
- background play, notification and lock-screen controls,
- QR-code sign-in flow in the UI,
- installing a plugin from a zip via the file picker,
- the `mygo-music://install-plugin` deep link,
- iOS: not built at all (needs a Mac; `libmygojs` would be linked statically / as an xcframework).

Other gaps: no downloads / offline cache; no desktop-only plugin exports (e.g. `remoteState`
returns `unsupported`).
