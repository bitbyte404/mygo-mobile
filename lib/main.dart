import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/platform/platform.dart' show loadAppFonts;
import 'app/services.dart';
import 'features/plugins/install_flow.dart';
import 'features/relay/relay_gate.dart';
import 'ui/theme/mg_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge to edge: the app draws under the status and navigation bars, which
  // stay transparent with no contrast scrim (see also MainActivity and
  // res/values-v29/styles.xml).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(mgOverlay(_systemIsLight()));
  if (kIsWeb) await loadAppFonts();
  svc = await bootstrap(relayGate: kIsWeb ? ensureRelaySession : null);
  runApp(const MyGoApp());
  if (kIsWeb) {
    _webStart();
  } else {
    _listenForLinks();
  }
}

bool _systemIsLight() => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.light;

/// mygo-music://install-plugin?repo=owner/repo, as the desktop app answers.
void _listenForLinks() {
  final links = AppLinks();
  void handle(Uri uri) {
    if (uri.scheme != 'mygo-music' || uri.host != 'install-plugin') return;
    final repo = uri.queryParameters['repo'];
    final ctx = navigatorKey.currentContext;
    if (repo == null || ctx == null) return;
    installFromRepo(ctx, repo);
  }

  links.uriLinkStream.listen(handle, onError: (_) {});
}

/// The browser's deep link is the page address: ?install=owner/repo (or
/// ?repo=..., as the desktop's mygo-music://install-plugin link has it). And
/// if the relay later refuses this browser (its token changed), ask again.
void _webStart() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final q = Uri.base.queryParameters;
    final repo = q['install'] ?? q['repo'];
    final ctx = navigatorKey.currentContext;
    if (repo != null && repo.isNotEmpty && ctx != null) installFromRepo(ctx, repo);
  });
  final relay = svc.relay;
  if (relay == null) return;
  var asking = false;
  svc.plugins.relayAuthNeeded.addListener(() async {
    final ctx = navigatorKey.currentContext;
    if (!svc.plugins.relayAuthNeeded.value || asking || ctx == null) return;
    asking = true;
    await showRelayTokenDialog(ctx, relay, svc.s);
    svc.plugins.relayAuthNeeded.value = false;
    asking = false;
  });
}
