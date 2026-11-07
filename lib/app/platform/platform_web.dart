import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWasm;
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
