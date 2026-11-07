// Screenshots of the real app UI, rendered headlessly at phone size
// (360x780 dp @3x = 1080x2340 px, dark theme, zh-CN) with live data from the
// signed-in kugou-lite plugin running in the app's own runtime (PluginManager
// -> PluginWorker isolate -> QuickJS). No device needed.
//
// Run (needs network; behind a proxy give MYGO_HTTP_PROXY=host:port):
//   MYGOJS_LIB=native/build/host/libmygojs.so MYGO_HTTP_PROXY=127.0.0.1:3128 \
//   NO_PROXY=localhost,127.0.0.1 flutter test test/screenshots_test.dart
// Fonts: --dart-define=CJK_FONT_DIR=<dir with NotoSansSC-{Regular,Medium,Bold}.otf>
// Output: screenshots/NN-name.png
@Tags(['live', 'screenshots'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/app_state.dart';
import 'package:mygo_mobile/main.dart';
import 'package:mygo_mobile/models.dart';
import 'package:mygo_mobile/player/player.dart';
import 'package:mygo_mobile/plugins/plugin_manager.dart';
import 'package:mygo_mobile/services.dart';
import 'package:mygo_mobile/ui/common.dart';
import 'package:mygo_mobile/ui/now_playing.dart';

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
  final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await l.load();
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

void main() {
  final boundary = GlobalKey();
  final errors = <String>[];
  final retries = <String>[];

  testWidgets('screenshots', (tester) async {
    final origOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d.exceptionAsString().split('\n').first);
      debugPrint('FLUTTER ERROR: ${d.exceptionAsString()}');
      if (!d.exceptionAsString().contains('overflowed')) debugPrint('${d.stack}');
    };
    HttpOverrides.global = _ImageOverrides();
    // flutter_test draws elevation as a hard black outline unless told not to.
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    // A phone's status bar and gesture bar.
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 48);
    addTearDown(tester.view.reset);
    Directory(outDir).createSync(recursive: true);

    late Directory root;
    await tester.runAsync(() async {
      await _loadFonts();
      root = Directory.systemTemp.createTempSync('mygo-shots-');
      // Installed as the installer leaves it: plugins/<id>/ + .mygo-origin.json.
      final pdir = Directory('${root.path}/plugins/kugou-lite')..createSync(recursive: true);
      for (final f in Directory(pluginSrc).listSync(recursive: true).whereType<File>()) {
        final rel = f.path.substring(pluginSrc.length + 1);
        if (rel.startsWith('.git')) continue;
        File('${pdir.path}/$rel')
          ..createSync(recursive: true)
          ..writeAsBytesSync(f.readAsBytesSync());
      }
      File(
        '${pdir.path}/.mygo-origin.json',
      ).writeAsStringSync('{"kind":"github","repo":"bitbyte404/mygo-music-kugou-lite","branch":"main","installedAt":${DateTime.now().millisecondsSinceEpoch}}');
      // The signed-in storage (a copy; the fixture itself is never written).
      Directory('${root.path}/plugin-data/kugou-lite').createSync(recursive: true);
      File('test/fixtures/kugou-data/kugou-lite/storage.json').copySync('${root.path}/plugin-data/kugou-lite/storage.json');

      final app = AppState(root.path)..load(deviceLanguage: 'zh-CN');
      app.themeMode = ThemeMode.dark;
      final plugins = PluginManager(
        root: root.path,
        prelude: File('assets/js/prelude.js').readAsStringSync(),
        language: 'zh-CN',
        platform: 'android',
        arch: 'arm64',
      );
      final player = Player();
      svc = Services(app: app, plugins: plugins, player: player);
      await plugins.init();
    });
    expect(svc.plugins.active?.worker, isNotNull, reason: svc.plugins.active?.error);

    Future<void> settle() async {
      try {
        await tester.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
      } catch (_) {} // something still animates (a spinner): fine
    }

    Future<void> waitOnce(int maxSecs) async {
      for (var i = 0; i < maxSecs * 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await settle();
    }

    // A plugin call that fails shows ErrorView with 重试; press it like a user
    // would (see the report: intermittent 'Maximum call stack size exceeded').
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

    // Image futures are created in the test's fake zone, so they only move
    // when real time passes (runAsync) *and* the fake zone is pumped.
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
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle();
    }

    Future<void> shot(String name) async {
      await loadImages();
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await ro.toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        img.dispose();
      });
      debugPrint('SHOT $name');
    }

    Future<Object?> callPlugin(String method, [Object? params]) async {
      Object? r;
      await tester.runAsync(() async => r = await svc.plugin('kugou-lite')!.call(method, params));
      return r;
    }

    ScaffoldState topScaffold() => tester.state<ScaffoldState>(find.byType(Scaffold).last);

    try {
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: const MyGoApp()));
      await wait();

      // 01 Home
      await shot('01-home');
      // 02 Home scrolled to the playlists
      final home = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
      final pos = tester.state<ScrollableState>(home).position;
      for (var i = 0; i < 40 && find.byType(MediaCard).evaluate().isEmpty; i++) {
        pos.jumpTo((pos.pixels + 300).clamp(0.0, pos.maxScrollExtent));
        await tester.pump();
      }
      final cardTop = tester.getTopLeft(find.byType(MediaCard).first).dy;
      debugPrint('home: pixels=${pos.pixels} cardTop=$cardTop max=${pos.maxScrollExtent}');
      pos.jumpTo((pos.pixels + cardTop - 330).clamp(0.0, pos.maxScrollExtent));
      await settle();
      await shot('02-home-scrolled');

      // 03 Drawer
      topScaffold().openDrawer();
      await settle();
      await shot('03-drawer');
      Navigator.of(tester.element(find.byType(NavigationDrawer))).pop();
      await settle();

      // 04 A playlist from the home page (推荐歌单)
      final card = find.byType(MediaCard).first;
      await tester.ensureVisible(card);
      await settle();
      await tester.tap(card);
      await tester.pump();
      await settle();
      await wait();
      await shot('04-playlist');
      navigatorKey.currentState!.pop();
      await settle();

      // 05 Search: 周杰伦 晴天
      await tester.tap(find.text('搜索').last);
      await settle();
      await tester.enterText(find.byType(TextField), '周杰伦 晴天');
      // let the suggestion debounce (350 ms) and its call finish before submitting
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      }
      await tester.pump();
      if (find.byType(TrackTile).evaluate().isEmpty && find.byType(ListTile).evaluate().isNotEmpty) {
        await shot('05-search-suggestions');
      }
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await wait();
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      await shot('06-search');

      // 06 Track menu on the first result, then its album (查看专辑)
      await tester.tap(find.descendant(of: find.byType(TrackTile).first, matching: find.byIcon(Icons.more_vert)));
      await tester.pump();
      for (var i = 0; i < 20 && find.byType(BottomSheet).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle();
      await shot('07-track-menu');
      final viewAlbum = find.textContaining('查看专辑');
      if (viewAlbum.evaluate().isNotEmpty) {
        await tester.tap(viewAlbum);
      } else {
        debugPrint('no 查看专辑 in the menu; opening the album from the 专辑 search tab');
        navigatorKey.currentState!.pop();
        await settle();
        await tester.tap(find.widgetWithText(ChoiceChip, '专辑'));
        await tester.pump();
        await wait();
        await tester.tap(find.byType(ListTile).first);
      }
      await tester.pump();
      await settle();
      await wait();
      await shot('08-album');
      navigatorKey.currentState!.pop();
      await settle();

      // "Playing" 晴天: the queue is the search results, as tapping a result
      // would set it (no audio is decoded in a test; position stays 0:00).
      final r = await callPlugin('search', {'query': '周杰伦 晴天', 'kind': 'tracks', 'offset': 0}) as Map;
      final tracks = (r['tracks'] as List).whereType<Map>().map((m) => Track.fromJson(m, 'kugou-lite')).toList();
      final qingtian = tracks.firstWhere((t) => t.name == '晴天');
      svc.player.tracks.value = List.unmodifiable(tracks);
      svc.player.current.value = qingtian;
      try {
        final s = await callPlugin('stream', {'id': qingtian.id, 'quality': 'lossless'});
        svc.player.streamInfo.value = StreamInfo.fromJson((s as Map?) ?? const {});
      } catch (e) {
        debugPrint('stream: $e');
      }
      await settle();

      // 08 我喜欢 (drawer -> 我喜欢)
      await tester.tap(find.byType(NavigationDestination).first);
      await settle();
      topScaffold().openDrawer();
      await settle();
      await tester.tap(find.descendant(of: find.byType(NavigationDrawer), matching: find.text('我喜欢')));
      await settle();
      await wait();
      await shot('09-liked');

      // 09 Now playing (tap the mini player)
      await tester.tap(find.byType(MiniPlayer));
      await tester.pump();
      await settle();
      await wait(8);
      await shot('10-now-playing');

      // 10 Lyrics (tap the cover)
      await tester.tap(find.byType(Cover).last);
      await tester.pump();
      await wait();
      // past the credits, into the sung lines (nothing is highlighted: no playback, position 0:00)
      await tester.drag(find.byType(LyricsView), const Offset(0, -900));
      await settle();
      await shot('11-lyrics');
      navigatorKey.currentState!.pop();
      await settle();

      // 11 Plugins (drawer -> 插件), after a real update check
      topScaffold().openDrawer();
      await settle();
      await tester.tap(find.descendant(of: find.byType(NavigationDrawer), matching: find.text('插件')));
      await settle();
      await tester.tap(find.byIcon(Icons.update));
      await tester.pump();
      for (var i = 0; i < 40 && find.byIcon(Icons.update).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle();
      await shot('12-plugins');
      navigatorKey.currentState!.pop();
      await settle();

      // 12 我的 tab
      await tester.tap(find.text('我的').last);
      await tester.pump();
      await wait();
      await shot('13-me');

      // tear down: unmount, stop the plugin isolates
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        svc.plugins.dispose();
        try {
          await svc.player.audio.dispose();
        } catch (_) {}
        root.deleteSync(recursive: true);
      });
      // the installer's HttpClient keeps an idle connection timer (15 s)
      await tester.pump(const Duration(seconds: 20));
    } finally {
      debugDisableShadows = true;
      FlutterError.onError = origOnError;
      HttpOverrides.global = null;
    }
    File('build/screenshot_errors.txt').writeAsStringSync([...errors, ...retries.map((r) => 'retried: $r')].join('\n'));
    debugPrint('ERRORS (${errors.length}):\n${errors.join('\n')}');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
