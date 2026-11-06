// The app's long-lived objects, reachable from every page.
import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'i18n.dart';
import 'models.dart';
import 'player/player.dart';
import 'plugins/plugin_manager.dart';
import 'runtime/plugin_host.dart';

class Services {
  Services({required this.app, required this.plugins, required this.player});
  final AppState app;
  final PluginManager plugins;
  final Player player;

  /// What we know of liked songs, by track key (source:id).
  final liked = ValueNotifier<Map<String, bool>>({});

  S get s => app.s;

  InstalledPlugin? plugin(String id) => plugins.byId(id);

  bool? isLiked(Track t) => liked.value[t.key];

  void _setLiked(Map<String, bool> m) => liked.value = {...liked.value, ...m};

  /// Asks the source which of these it has liked.
  Future<void> refreshLiked(String source, List<Track> tracks) async {
    final p = plugin(source);
    if (p == null || !p.can('isLiked') || tracks.isEmpty) return;
    try {
      final r = await p.call('isLiked', {'ids': tracks.map((t) => t.id).toList()}) as Map?;
      if (r == null) return;
      _setLiked({for (final e in r.entries) '$source:${e.key}': e.value == true});
    } catch (e) {
      debugPrint('isLiked: $e');
    }
  }

  Future<void> setLiked(Track t, bool on) async {
    final p = plugin(t.source);
    if (p == null) return;
    final before = liked.value[t.key];
    _setLiked({t.key: on});
    try {
      await p.call(t.showId.isNotEmpty && p.can('likeEpisode') ? 'likeEpisode' : 'like', {'id': t.id, 'on': on});
    } catch (e) {
      _setLiked({t.key: before ?? !on});
      rethrow;
    }
  }

  /// A plugin's error in the listener's language.
  String describe(Object e) {
    if (e is PluginError) {
      switch (e.code) {
        case PluginError.signIn:
          return e.message.isNotEmpty ? e.message : s['errSignIn'];
        case PluginError.setup:
          return e.message.isNotEmpty ? e.message : s['errSetup'];
        case PluginError.unavailable:
          return e.message.isNotEmpty ? e.message : s['errUnavailable'];
        case PluginError.unsupported:
          return s['errUnsupported'];
      }
      return e.toString();
    }
    return '$e';
  }
}

late Services svc;
