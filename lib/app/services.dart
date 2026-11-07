// The composition root's product: the app's long-lived objects, built once by
// bootstrap() (lib/app/bootstrap.dart) or by a test, and reached from the
// features through [svc]. Data-layer classes get their dependencies through
// their constructors; [svc] is only the hand-off point to widgets.
import 'package:mygo_mobile/core/errors.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/data/library/liked_store.dart';
import 'package:mygo_mobile/data/library/music_repository.dart';
import 'package:mygo_mobile/data/navigation.dart';
import 'package:mygo_mobile/data/player/player.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/data/settings/app_state.dart';
import 'package:mygo_mobile/l10n/strings.dart';

class Services {
  Services({required this.app, required this.plugins, required this.player, MusicRepository? music}) : music = music ?? MusicRepository(plugins) {
    likes = LikedStore(this.music);
  }

  final AppState app;
  final PluginManager plugins;
  final Player player;
  final MusicRepository music;
  late final LikedStore likes;

  S get s => app.s;

  InstalledPlugin? plugin(String id) => plugins.byId(id);

  /// The navigation entries of a plugin (sidebar / library), in this
  /// language.
  List<NavEntry> navEntries(InstalledPlugin? p) {
    if (p == null) return buildNavEntries(nav: const [], translate: (t) => t, builtinTitle: (_) => '', recentTitle: s['recent'], canRecent: false);
    return buildNavEntries(
      nav: p.navigation,
      translate: p.t,
      builtinTitle: (n) => switch (n.builtin) {
        'home' => s['home'],
        'liked' => s['liked'],
        'savedAlbums' => s['savedAlbums'],
        'stations' => s['stations'],
        'shows' => s['shows'],
        _ => n.page,
      },
      recentTitle: s['recent'],
      canRecent: p.can('recent'),
      canShows: p.can('shows'),
    );
  }

  /// Wires the player to the plugins: streams, "played", radio refills.
  void connectPlayer() {
    player.resolver = (Track t) => music.stream(t, app.quality);
    player.onStarted = (Track t) {
      app.addHistory(t);
      if (music.can(t.source, 'played')) {
        music.played(t.source, t.id).catchError((Object e) {
          // ignore: avoid_print
          print('played: $e');
        });
      }
    };
    player.stationNext = music.stationNext;
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

/// Set once by bootstrap() (or a test) before the first frame.
late Services svc;
