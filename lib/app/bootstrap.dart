// The composition root: builds the app's long-lived objects in dependency
// order and wires them. Nothing else constructs them (tests build their own).
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:mygo_mobile/data/player/player.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/data/relay/relay_client.dart';
import 'package:mygo_mobile/data/settings/app_state.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'platform/platform.dart';
import 'services.dart';

/// [relayGate] runs before anything talks to the relay (web only): it gets a
/// session when the relay wants its token.
Future<Services> bootstrap({Future<void> Function(RelayClient relay)? relayGate}) async {
  final bits = await platformBits();
  final relay = bits.relay;
  if (relay != null) {
    if (relayGate != null) await relayGate(relay);
    MgImages.rewrite = relay.imageUrl;
  }
  final app = AppState(bits.store);
  await app.load(deviceLanguage: PlatformDispatcher.instance.locale.toLanguageTag());
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
    store: bits.store,
    prelude: prelude,
    language: app.language,
    platform: bits.platform,
    arch: bits.arch,
    runtime: bits.runtime,
    github: bits.github,
    registrar: relay,
  );
  final services = Services(app: app, plugins: plugins, player: player, relay: relay)..connectPlayer();
  await plugins.init(activeId: app.activePlugin);
  return services;
}
