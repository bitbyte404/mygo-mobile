import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mygo_mobile/core/runtime/runtime_factory.dart';
import 'package:mygo_mobile/core/storage/store.dart';
import 'package:mygo_mobile/data/plugins/installer.dart';
import 'package:mygo_mobile/data/relay/relay_client.dart';
import 'package:web/web.dart' as web;

import 'platform_bits.dart';

Future<PlatformBits> platformBits() async {
  // The page's base (honours <base href>, e.g. behind a reverse proxy at /music/).
  final base = Uri.parse(web.document.baseURI);
  return PlatformBits(
    store: await openStore('mygo'),
    platform: 'web',
    arch: kIsWasm ? 'wasm' : 'js',
    runtime: defaultPluginRuntime(),
    github: GitHubEndpoints.relay(base),
    relay: RelayClient(base),
  );
}

/// The family name [mgTheme] asks for on the web.
const webFontFamily = 'MgSans';

Future<void> _loadFont(String file) async {
  final url = Uri.parse(web.document.baseURI).resolve('fonts/$file').toString();
  final res = await web.window.fetch(url.toJS).toDart;
  if (!res.ok) throw StateError('font $file: HTTP ${res.status}');
  final buf = await res.arrayBuffer().toDart;
  await ui.loadFontFromList(buf.toDart.asUint8List(), fontFamily: webFontFamily);
}

/// Regular is awaited (briefly) so the first frame already has CJK glyphs;
/// Bold follows in the background and the text relayouts when it lands.
Future<void> loadAppFonts() async {
  unawaited(_loadFont('NotoSansSC-Bold.woff2').catchError((Object _) {}));
  try {
    await _loadFont('NotoSansSC-Regular.woff2').timeout(const Duration(seconds: 15));
  } catch (_) {}
}

/// env(safe-area-inset-*), measured by index.html (Flutter's web engine
/// reports no view padding, so without this the app drew under the notch,
/// the home indicator and Safari's toolbar).
final ValueListenable<EdgeInsets> systemInsets = _watchInsets();

ValueNotifier<EdgeInsets> _watchInsets() {
  final n = ValueNotifier<EdgeInsets>(EdgeInsets.zero);
  void read() {
    final o = web.window.getProperty<JSObject?>('mygoInsets'.toJS);
    if (o == null) return;
    double v(String k) => (o.getProperty<JSNumber?>(k.toJS)?.toDartDouble ?? 0).clamp(0, 400).toDouble();
    n.value = EdgeInsets.fromLTRB(v('left'), v('top'), v('right'), v('bottom'));
  }

  read();
  web.window.addEventListener('mygo-insets', ((web.Event _) => read()).toJS);
  return n;
}

/// Sends a failure to the relay's log (POST /api/log): on a phone there is no
/// console to read. Best effort; never throws.
void reportClientError(String kind, String message) {
  try {
    final standalone = web.window.matchMedia('(display-mode: standalone)').matches;
    final body = jsonEncode({'kind': kind, 'message': message, 'context': standalone ? 'standalone' : 'browser'});
    final url = Uri.parse(web.document.baseURI).resolve('api/log').toString();
    web.window
        .fetch(url.toJS, web.RequestInit(method: 'POST', body: body.toJS, headers: {'content-type': 'application/json'}.jsify()! as web.HeadersInit, keepalive: true))
        .toDart
        .then((_) {}, onError: (Object _) {});
  } catch (_) {}
}

/// The <audio> element's currentTime (index.html remembers the element the
/// player plays through), or null when there is none or it has nothing
/// decoded at that point. Safari and Chrome answer currentTime from the
/// media clock itself, so this is exact where just_audio's position reports
/// arrive a few times a second.
Duration? mediaClock() {
  final a = web.window.getProperty<JSObject?>('__mygoAudio'.toJS);
  if (a == null) return null;
  final el = a as web.HTMLMediaElement;
  if (el.readyState < 2 || el.seeking || el.ended) return null;
  final t = el.currentTime;
  if (t.isNaN || t < 0) return null;
  return Duration(microseconds: (t * 1e6).round());
}

/// Diagnostics the tests read (window.__mygo.*): the lyrics clock and line.
void debugExpose(String key, Object? value) {
  try {
    var o = web.window.getProperty<JSObject?>('__mygo'.toJS);
    if (o == null) {
      o = JSObject();
      web.window.setProperty('__mygo'.toJS, o);
    }
    o.setProperty(key.toJS, value.jsify());
  } catch (_) {}
}

/// A query parameter of the page (?clock=legacy).
String? pageParam(String name) => Uri.base.queryParameters[name];

/// window.__mygoPosition(): the position the lyrics follow, in ms (tests).
void exposeClock(Duration Function() now) {
  web.window.setProperty('__mygoPosition'.toJS, (() => now().inMilliseconds).toJS);
}
