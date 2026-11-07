// How a plugin's navigation (plugin.json "navigation", or the app's pages it
// can do) becomes the entries of the sidebar / library. Pure: no widgets, so
// it is unit-tested (test/navigation_test.dart).
import 'package:mygo_mobile/core/plugin/manifest.dart';

/// An entry of the sidebar / library: a plugin's navigation entry, or the
/// app's own "recently played".
class NavEntry {
  NavEntry({required this.key, required this.icon, required this.title, this.item, this.recentPage, this.recent = false});

  /// `nav:<index>` (into the navigation) or `recent` (the app's own entry).
  final String key;

  /// An icon name as plugins give them (icons.go navIcon): home, album,
  /// artist, playlist, radio, podcast, chart, calendar, heart, search, star;
  /// and 'history' for recently played.
  final String icon;
  final String title;
  final NavItem? item; // null: the app's recently played

  /// For recently played: the plugin's own page of it ('' to use its
  /// `recent` export; null when only this device's history is shown).
  final String? recentPage;
  final bool recent;

  bool get isHome => item?.builtin == 'home';
  bool get isRecent => recent;
}

/// The plugin's navigation, as the desktop sidebar lists it, with one
/// "recently played": the plugin's own entry for it, if it has one, takes in
/// what this device played too, rather than the app adding a second entry.
List<NavEntry> buildNavEntries({
  required List<NavItem> nav,
  required String Function(String) translate,
  required String Function(NavItem) builtinTitle,
  required String recentTitle,
  required bool canRecent,
  bool canShows = false,
}) {
  final out = <NavEntry>[];
  var hasRecent = false;
  for (var i = 0; i < nav.length; i++) {
    final n = nav[i];
    if (n.builtin == 'shows' && !canShows) continue;
    final recent = isRecentItem(n, translate, recentTitle);
    if (recent) hasRecent = true;
    final title = n.title.isNotEmpty ? translate(n.title) : builtinTitle(n);
    out.add(NavEntry(
      key: 'nav:$i',
      icon: recent ? 'history' : (n.builtin.isNotEmpty ? _builtinIcon(n.builtin, n.icon) : n.icon),
      title: recent ? recentTitle : title,
      item: n,
      recentPage: recent ? n.page : null,
      recent: recent,
    ));
  }
  if (!hasRecent) {
    out.add(NavEntry(key: 'recent', icon: 'history', title: recentTitle, recentPage: canRecent ? '' : null, recent: true));
  }
  return out;
}

String _builtinIcon(String builtin, String icon) {
  if (icon.isNotEmpty) return icon;
  return switch (builtin) {
    'home' => 'home',
    'liked' => 'heart',
    'savedAlbums' => 'album',
    'stations' => 'radio',
    'shows' => 'podcast',
    _ => '',
  };
}

/// Whether a plugin's entry is its "recently played" page.
bool isRecentItem(NavItem n, String Function(String) translate, String recentTitle) {
  if (n.builtin.isNotEmpty || n.page.isEmpty) return false;
  if (n.page == 'recent' || n.page == 'history') return true;
  final t = translate(n.title).trim().toLowerCase();
  return t == recentTitle.toLowerCase() || t == 'recently played' || t == '最近播放';
}
