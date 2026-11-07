// Where the app is: the destination its content shows at the root (a
// plugin's navigation entry, search, the library...), the content navigator
// pages are pushed on, and Now Playing over it all.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// The navigator of the content area (between the sidebar or the top of the
/// screen and the player): pages are pushed here, so the sidebar, the tab
/// bar and the player stay.
final contentNavKey = GlobalKey<NavigatorState>();

class ShellState extends ChangeNotifier {
  /// 'nav:<i>' (the plugin's i-th navigation entry), 'recent', 'search',
  /// 'library', 'plugins' or 'settings'.
  String dest = 'nav:0';
  int gen = 0; // bumps to reload the root page
  String searchQuery = '';

  void go(String d, {bool reload = true}) {
    if (d == dest && !reload) return;
    dest = d;
    if (reload) gen++;
    contentNavKey.currentState?.popUntil((r) => r.isFirst);
    notifyListeners();
  }

  void search(String q) {
    searchQuery = q;
    go('search');
  }
}

final shellState = ShellState();

/// Set by the shell: closes Now Playing, if open.
VoidCallback closeNowPlaying = () {};

/// Opens [page] in the content area, closing Now Playing over it, as MyGo's
/// open() does.
Future<T?> pushPage<T>(BuildContext context, Widget page) {
  closeNowPlaying();
  final nav = contentNavKey.currentState ?? Navigator.of(context);
  return nav.push<T>(MaterialPageRoute<T>(builder: (_) => page));
}

/// The icon for an icon name a plugin gives (icons.go navIcon).
MgIconData navIcon(String name) => switch (name) {
      'home' => MgIcons.home,
      'album' => MgIcons.album,
      'artist' => MgIcons.user,
      'playlist' => MgIcons.playlist,
      'radio' => MgIcons.radio,
      'podcast' => MgIcons.podcast,
      'chart' => MgIcons.charts,
      'calendar' => MgIcons.calendar,
      'heart' => MgIcons.heart,
      'search' => MgIcons.search,
      'star' => MgIcons.star,
      'history' => MgIcons.history,
      _ => MgIcons.note,
    };
