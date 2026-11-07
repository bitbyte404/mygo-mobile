// The composition root: builds the app's long-lived objects in dependency
// order and wires them. Nothing else constructs them (tests build their own).
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:mygo_mobile/core/runtime/runtime_factory.dart';
import 'package:mygo_mobile/data/player/player.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/data/settings/app_state.dart';
import 'package:path_provider/path_provider.dart';

import 'services.dart';

String _arch() {
  final a = Abi.current().toString();
  if (a.contains('arm64')) return 'arm64';
  if (a.contains('x64')) return 'amd64';
  if (a.contains('arm')) return 'arm';
  return a;
}

Future<Services> bootstrap() async {
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

  final plugins = PluginManager(
    root: dir.path,
    prelude: prelude,
    language: app.language,
    platform: Platform.operatingSystem,
    arch: _arch(),
    runtime: defaultPluginRuntime(),
  );
  final services = Services(app: app, plugins: plugins, player: player)..connectPlayer();
  await plugins.init(activeId: app.activePlugin);
  return services;
}
