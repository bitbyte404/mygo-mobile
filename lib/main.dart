import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/services.dart';
import 'features/plugins/install_flow.dart';
import 'ui/theme/mg_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge to edge: the app draws under the status and navigation bars, which
  // stay transparent with no contrast scrim (see also MainActivity and
  // res/values-v29/styles.xml).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(mgOverlay(_systemIsLight()));
  svc = await bootstrap();
  runApp(const MyGoApp());
  _listenForLinks();
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
