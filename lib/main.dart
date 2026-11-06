import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'models.dart';
import 'player/player.dart';
import 'plugins/plugin_manager.dart';
import 'runtime/plugin_host.dart';
import 'services.dart';
import 'ui/home_shell.dart';
import 'ui/plugins_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

String _arch() {
  final a = Abi.current().toString();
  if (a.contains('arm64')) return 'arm64';
  if (a.contains('x64')) return 'amd64';
  if (a.contains('arm')) return 'arm';
  return a;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  final app = AppState(dir.path)..load(deviceLanguage: PlatformDispatcher.instance.locale.toLanguageTag());
  final prelude = await rootBundle.loadString('assets/js/prelude.js');

  final player = await AudioService.init(
    builder: () => Player(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'io.github.bitbyte404.mygo_mobile.playback',
      androidNotificationChannelName: 'MyGo 音乐',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  final plugins = PluginManager(root: dir.path, prelude: prelude, language: app.language, platform: Platform.operatingSystem, arch: _arch());
  svc = Services(app: app, plugins: plugins, player: player);

  player.resolver = (Track t) async {
    final p = plugins.byId(t.source);
    if (p == null) throw PluginError('', 'no plugin "${t.source}"');
    final r = await p.call('stream', {'id': t.id, 'quality': app.quality});
    final s = StreamInfo.fromJson((r as Map?) ?? const {});
    if (s.url.isEmpty) throw PluginError(PluginError.unavailable, '');
    return s;
  };
  player.onStarted = (Track t) {
    app.addHistory(t);
    final p = plugins.byId(t.source);
    if (p != null && p.can('played')) {
      p.call('played', {'id': t.id}).catchError((Object e) {
        debugPrint('played: $e');
        return null;
      });
    }
  };
  player.stationNext = (String source, String id) async {
    final r = await plugins.byId(source)!.call('stationNext', {'id': id});
    return ((r as List?) ?? const []).whereType<Map>().map((m) => Track.fromJson(m, source)).toList();
  };

  await plugins.init(activeId: app.activePlugin);
  runApp(const MyGoApp());
  _listenForLinks();
}

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

class MyGoApp extends StatelessWidget {
  const MyGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: svc.app,
      builder: (context, _) {
        const seed = Color(0xFF6A5ACD);
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: svc.s['appName'],
          debugShowCheckedModeBanner: false,
          themeMode: svc.app.themeMode,
          locale: svc.app.language == 'zh-CN' ? const Locale('zh', 'CN') : const Locale('en'),
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true),
          darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark), useMaterial3: true),
          home: const HomeShell(),
        );
      },
    );
  }
}
