// Screenshots of the real app UI, rendered headlessly with live data from
// the signed-in kugou-lite plugin running in the app's own runtime
// (PluginManager -> QuickJsRuntime -> PluginWorker isolate -> QuickJS).
//
//   phone   1080x2340 px (360x780 dp @3), dark and light, zh-CN
//   tablet  2560x1600 px (1280x800 dp @2, landscape), dark
//
// The phone's status bar (24 dp) and gesture bar (16 dp), the tablet's (24 /
// 20 dp), are simulated: the view gets them as padding/viewPadding, as an
// edge-to-edge Android window does, and the test paints a fake status bar
// (clock, icons) and gesture pill over the frame, in the icon brightness the
// app last asked for (SystemChrome.latestStyle). Content under them is the
// app's own: that is the edge-to-edge check. Results: screenshots/*.png and
// build/screenshot_report.json (per shot: the overlay style asked for, errors).
//
// Run (needs network; behind a proxy give MYGO_HTTP_PROXY=host:port):
//   MYGOJS_LIB=native/build/host/libmygojs.so MYGO_HTTP_PROXY=127.0.0.1:3128 \
//   NO_PROXY=localhost,127.0.0.1 flutter test test/screenshots_test.dart
@Tags(['live', 'screenshots'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/app/app.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/core/runtime/quickjs/quickjs_runtime.dart';
import 'package:mygo_mobile/core/storage/file_store.dart';
import 'package:mygo_mobile/data/player/player.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/data/settings/app_state.dart';
import 'package:mygo_mobile/features/album/album_screen.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/tracks.dart';
import 'package:mygo_mobile/features/now_playing/mini_player.dart';
import 'package:mygo_mobile/features/now_playing/now_playing_controller.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

const pluginSrc = String.fromEnvironment('KUGOU_DIR', defaultValue: '/workspace/work/mygo-music-kugou-lite');
const fontDir = String.fromEnvironment('CJK_FONT_DIR', defaultValue: '/workspace/work/tools/fonts');
const outDir = 'screenshots';

/// Network images in a widget test: served from build/img-cache, fetched
/// once with curl (through MYGO_HTTP_PROXY) when missing. Everything else
/// gets a real client.
class _ImageOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final c = super.createHttpClient(context);
    final proxy = Platform.environment['MYGO_HTTP_PROXY'];
    if (proxy != null && proxy.isNotEmpty) c.findProxy = (_) => 'PROXY $proxy';
    return _CachingClient(c);
  }
}

class _CachingClient implements HttpClient {
  _CachingClient(this._real);
  final HttpClient _real;
  @override
  bool autoUncompress = true;

  bool _isImage(Uri u) => RegExp(r'\.(jpe?g|png|webp|gif)$', caseSensitive: false).hasMatch(u.path) || u.host.startsWith('imge.') || u.host.contains('img');

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _isImage(url) ? _CachedRequest(url) : _real.getUrl(url);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => method == 'GET' && _isImage(url) ? _CachedRequest(url) : _real.openUrl(method, url);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('test HttpClient: ${i.memberName}');
}

final _inflight = <String, Future<List<int>?>>{};
Future<List<int>?> _fetch(Uri url) {
  final key = url.toString();
  return _inflight[key] ??= () async {
    final name = key.hashCode.toUnsigned(32).toRadixString(16) + key.length.toString();
    final f = File('build/img-cache/$name');
    if (!f.existsSync() || f.lengthSync() == 0) {
      f.parent.createSync(recursive: true);
      final proxy = Platform.environment['MYGO_HTTP_PROXY'];
      for (var attempt = 0; attempt < 3 && (!f.existsSync() || f.lengthSync() == 0); attempt++) {
        await Process.run('curl', [
          '-sSL',
          '-m',
          '25',
          '-f',
          if (proxy != null && proxy.isNotEmpty) ...['-x', proxy],
          '-o',
          f.path,
          key,
        ]);
      }
    }
    return f.existsSync() && f.lengthSync() > 0 ? f.readAsBytesSync() : null;
  }();
}

class _CachedRequest implements HttpClientRequest {
  _CachedRequest(this.uri);
  @override
  final Uri uri;
  @override
  HttpHeaders get headers => _NoHeaders();
  @override
  Future<HttpClientResponse> close() async {
    final bytes = await _fetch(uri);
    return _CachedResponse(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _NoHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _CachedResponse extends Stream<List<int>> implements HttpClientResponse {
  _CachedResponse(this._bytes);
  final List<int>? _bytes;
  @override
  int get statusCode => _bytes == null ? 404 : 200;
  @override
  int get contentLength => _bytes?.length ?? 0;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable([if (_bytes != null) _bytes]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/workspace/work/tools/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
  // The Android theme asks for Roboto; Noto Sans SC covers Latin + CJK (+kana).
  for (final family in ['Roboto']) {
    final f = FontLoader(family);
    for (final w in ['Regular', 'Medium', 'Bold']) {
      // emoji-merged/: the same font with monochrome Noto Emoji glyphs added
      // (tools/fonts/add_emoji.py), since the test engine has no per-glyph fallback.
      final merged = File('$fontDir/emoji-merged/NotoSansSC-$w.otf');
      final file = merged.existsSync() ? merged : File('$fontDir/NotoSansSC-$w.otf');
      f.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await f.load();
  }
}


/// The fake system bars painted over a frame: a status bar with a clock and
/// icons, and a gesture pill, both transparent, in the brightness the app
/// asked for.
class _SystemBars extends StatelessWidget {
  const _SystemBars({required this.top, required this.bottom});
  final double top, bottom;

  @override
  Widget build(BuildContext context) {
    final style = SystemChrome.latestStyle;
    final darkIcons = style?.statusBarIconBrightness == Brightness.dark;
    final c = darkIcons ? const Color(0xFF111111) : const Color(0xFFFFFFFF);
    final nav = style?.systemNavigationBarIconBrightness == Brightness.dark ? const Color(0xCC111111) : const Color(0xCCFFFFFF);
    return IgnorePointer(
      child: Stack(children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(children: [
              Text('12:00', style: TextStyle(fontFamily: 'Roboto', fontSize: 13, fontWeight: FontWeight.w600, color: c, decoration: TextDecoration.none)),
              const Spacer(),
              for (final w in [14.0, 14.0, 22.0]) Container(margin: const EdgeInsets.only(left: 5), width: w, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: bottom,
          child: Center(child: Container(width: 108, height: 4, decoration: BoxDecoration(color: nav, borderRadius: BorderRadius.circular(2)))),
        ),
      ]),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.boundary, required this.top, required this.bottom});
  final GlobalKey boundary;
  final double top, bottom;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: boundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [
          const Positioned.fill(child: MyGoApp()),
          Positioned.fill(child: _SystemBars(top: top, bottom: bottom)),
        ]),
      ),
    );
  }
}

void main() {
  final errors = <String>[];
  final retries = <String>[];
  final report = <String, Object?>{};

  testWidgets('screenshots', (tester) async {
    final origOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d.exceptionAsString().split('\n').first);
      debugPrint('FLUTTER ERROR: ${d.exceptionAsString()}');
      debugPrint('${d.stack}');
    };
    HttpOverrides.global = _ImageOverrides();
    debugDisableShadows = false;
    addTearDown(tester.view.reset);
    Directory(outDir).createSync(recursive: true);

    late Directory root;
    await tester.runAsync(() async {
      await _loadFonts();
      root = Directory.systemTemp.createTempSync('mygo-shots-');
      final pdir = Directory('${root.path}/plugins/kugou-lite')..createSync(recursive: true);
      for (final f in Directory(pluginSrc).listSync(recursive: true).whereType<File>()) {
        final rel = f.path.substring(pluginSrc.length + 1);
        if (rel.startsWith('.git')) continue;
        File('${pdir.path}/$rel')
          ..createSync(recursive: true)
          ..writeAsBytesSync(f.readAsBytesSync());
      }
      File('${pdir.path}/.mygo-origin.json')
          .writeAsStringSync('{"kind":"github","repo":"bitbyte404/mygo-music-kugou-lite","branch":"main","installedAt":${DateTime.now().millisecondsSinceEpoch}}');
      Directory('${root.path}/plugin-data/kugou-lite').createSync(recursive: true);
      File('test/fixtures/kugou-data/kugou-lite/storage.json').copySync('${root.path}/plugin-data/kugou-lite/storage.json');

      final store = FileStore(root.path);
      final app = AppState(store);
      await app.load(deviceLanguage: 'zh-CN');
      final plugins = PluginManager(
        store: store,
        prelude: File('assets/js/prelude.js').readAsStringSync(),
        language: 'zh-CN',
        platform: 'android',
        arch: 'arm64',
        runtime: const QuickJsRuntime(),
      );
      svc = Services(app: app, plugins: plugins, player: Player())..connectPlayer();
      await plugins.init();
    });
    expect(svc.plugins.active?.running, isTrue, reason: svc.plugins.active?.error);

    Future<void> settle([int secs = 3]) async {
      try {
        await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, Duration(seconds: secs));
      } catch (_) {} // something keeps animating (a playing indicator): fine
    }

    Future<void> waitOnce(int maxSecs) async {
      for (var i = 0; i < maxSecs * 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(MgSpinner).evaluate().isEmpty) break;
      }
      await settle();
    }

    // A plugin call that fails shows ErrorView with 重试; press it as a user would.
    Future<void> wait([int maxSecs = 25]) async {
      await waitOnce(maxSecs);
      for (var i = 0; i < 4 && find.byType(ErrorView).evaluate().isNotEmpty; i++) {
        final msg = find.descendant(of: find.byType(ErrorView).last, matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data).join(' | ');
        debugPrint('ErrorView shown ($msg); pressing 重试');
        retries.add(msg);
        await tester.tap(find.descendant(of: find.byType(ErrorView).last, matching: find.text('重试')));
        await tester.pump();
        await waitOnce(maxSecs);
      }
    }

    Future<void> loadImages() async {
      for (var round = 0; round < 3; round++) {
        final els = find.byType(Image).evaluate().toList();
        var done = 0;
        for (final e in els) {
          precacheImage((e.widget as Image).image, e, onError: (_, _) {}).whenComplete(() => done++);
        }
        for (var i = 0; i < 120 && done < els.length; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 16));
        }
        if (done < els.length) debugPrint('images: $done/${els.length} loaded');
        // artwork tints (ArtTint) resolve on their own futures
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle();
    }

    late GlobalKey boundary;
    late double dpr;
    Future<void> shot(String name) async {
      await loadImages();
      // Repaint so the fake bars read the style this frame asked for.
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      final style = SystemChrome.latestStyle;
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await ro.toImage(pixelRatio: dpr);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        img.dispose();
      });
      report[name] = {
        'statusBarIcons': style?.statusBarIconBrightness?.name,
        'navBarIcons': style?.systemNavigationBarIconBrightness?.name,
        'statusBarColor': style?.statusBarColor?.toARGB32().toRadixString(16),
        'navBarColor': style?.systemNavigationBarColor?.toARGB32().toRadixString(16),
        'navContrastEnforced': style?.systemNavigationBarContrastEnforced,
        'errorsSoFar': errors.length,
      };
      debugPrint('SHOT $name');
    }

    Future<T?> run<T>(Future<T> Function() f) async {
      T? r;
      await tester.runAsync(() async => r = await f());
      return r;
    }

    // Live data used to set up states a test can't reach by playing audio.
    final found = await run(() => svc.music.search('kugou-lite', query: '周杰伦 晴天', kind: 'tracks'));
    final tracks = found!.tracks;
    final qingtian = tracks.firstWhere((t) => t.name == '晴天', orElse: () => tracks.first);
    StreamInfo? stream;
    try {
      stream = await run(() => svc.music.stream(qingtian, 'lossless'));
    } catch (e) {
      debugPrint('stream: $e');
    }
    final lines = await run(() => svc.music.lyrics(qingtian)) ?? const <LyricLine>[];
    // A position inside the sung lines (past the credits): the 12th line or so.
    final sung = lines.where((l) => l.text.trim().isNotEmpty && !l.text.contains('：') && !l.text.contains(':')).toList();
    final at = sung.length > 12 ? sung[12].start + 400 : 60000;
    report['lyricsPosition'] = at;

    void setPlaying() {
      svc.player.tracks.value = List.unmodifiable(tracks);
      svc.player.current.value = qingtian;
      svc.player.streamInfo.value = stream;
      svc.player.debugSetClock(position: Duration(milliseconds: at), playing: true, frozen: true);
    }

    void clearPlaying() {
      svc.player.current.value = null;
      svc.player.debugSetClock(position: Duration.zero);
    }

    Future<void> resetApp() async {
      nowPlaying.close();
      nowPlaying.pane = NpPane.cover;
      shellState.dest = 'nav:0';
      shellState.gen++;
      await tester.pumpWidget(const SizedBox());
      await settle();
    }

    Future<void> configure({required Size px, required double ratio, required double top, required double bottom}) async {
      dpr = ratio;
      tester.view.physicalSize = px;
      tester.view.devicePixelRatio = ratio;
      tester.view.padding = FakeViewPadding(top: top * ratio, bottom: bottom * ratio);
      tester.view.viewPadding = FakeViewPadding(top: top * ratio, bottom: bottom * ratio);
      boundary = GlobalKey();
      await tester.pumpWidget(_Frame(boundary: boundary, top: top, bottom: bottom));
      await wait();
    }

    Future<void> openFromMenuAlbum() async {
      await tester.tap(find.descendant(of: find.byType(TrackTile).first, matching: find.byType(MgIconButton)).last);
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle();
      final viewAlbum = find.textContaining('查看专辑');
      expect(viewAlbum, findsWidgets);
      await tester.tap(viewAlbum.first);
      await tester.pump();
      await settle();
      await wait();
    }

    Future<void> phone(String theme) async {
      svc.app.themeMode = theme == 'dark' ? ThemeMode.dark : ThemeMode.light;
      clearPlaying();
      await resetApp();
      await configure(px: const Size(1080, 2340), ratio: 3, top: 24, bottom: 16);
      final p = 'phone-$theme';
      await shot('$p-01-home');

      // Search 周杰伦 晴天 (submitting cancels the pending suggestion)
      await tester.tap(find.text('搜索').last);
      await settle();
      await wait();
      await tester.enterText(find.byType(TextField), '周杰伦 晴天');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await wait();
      // past the debounce: the suggestion must not come back over the results
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      report['$p-searchShowsResults'] = find.byType(TrackTile).evaluate().isNotEmpty;
      await shot('$p-02-search');

      // The first result's album, from its song menu
      await openFromMenuAlbum();
      await shot('$p-03-album');
      contentNavKey.currentState!.pop();
      await settle();

      // 我喜欢, from the library tab
      await tester.tap(find.text('我的').last);
      await settle();
      await wait();
      await tester.tap(find.text('我喜欢').first);
      await tester.pump();
      await settle();
      await wait();
      await shot('$p-04-liked');

      // Something plays: the mini player over the tab bar, on Home
      setPlaying();
      await tester.tap(find.text('首页').last);
      await settle();
      await wait();
      await shot('$p-05-mini-player');

      // Now Playing, grown out of the mini player
      await tester.tap(find.byType(MiniPlayer));
      await tester.pump();
      await settle();
      await shot('$p-06-now-playing');

      // Lyrics, the line at the position lit
      nowPlaying.show(NpPane.lyrics);
      await tester.pump();
      await wait();
      svc.player.debugSetClock(position: Duration(milliseconds: at), playing: true, frozen: true);
      await tester.pump();
      await settle();
      await shot('$p-07-lyrics');
      nowPlaying.close();
      await settle();

      // Plugins, after a real update check
      clearPlaying();
      await tester.pump();
      await tester.tap(find.text('我的').last);
      await settle();
      await wait();
      await tester.tap(find.text('插件').first);
      await tester.pump();
      await settle();
      await tester.tap(find.byKey(const ValueKey('check-updates')));
      await tester.pump();
      for (var i = 0; i < 40 && find.byKey(const ValueKey('check-updates')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle();
      await shot('$p-08-plugins');
    }

    try {
      await phone('dark');
      await phone('light');

      // Tablet, landscape: the desktop layout.
      svc.app.themeMode = ThemeMode.dark;
      clearPlaying();
      await resetApp();
      setPlaying();
      await configure(px: const Size(2560, 1600), ratio: 2, top: 24, bottom: 20);
      await shot('tablet-01-home');
      final album = qingtian.album;
      pushPage(tester.element(find.byType(MyGoApp)), AlbumScreen(pluginId: 'kugou-lite', album: album));
      await tester.pump();
      await settle();
      await wait();
      await shot('tablet-02-album');
      nowPlaying.open(pane: NpPane.lyrics);
      await tester.pump();
      await settle();
      await wait();
      svc.player.debugSetClock(position: Duration(milliseconds: at), playing: true, frozen: true);
      await tester.pump();
      await settle();
      await shot('tablet-03-now-playing-lyrics');

      // tear down: unmount, stop the plugin isolates
      nowPlaying.close();
      clearPlaying();
      await tester.pumpWidget(const SizedBox());
      await settle();
      await tester.runAsync(() async {
        svc.plugins.dispose();
        try {
          await svc.player.audio.dispose();
        } catch (_) {}
        root.deleteSync(recursive: true);
      });
      await tester.pump(const Duration(seconds: 20));
    } finally {
      debugDisableShadows = true;
      FlutterError.onError = origOnError;
      HttpOverrides.global = null;
      report['errors'] = errors;
      report['retried'] = retries;
      File('build/screenshot_report.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
    debugPrint('ERRORS (${errors.length}):\n${errors.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
