// What each navigation entry opens.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/data/navigation.dart';
import 'package:mygo_mobile/features/browse/browse_view.dart';
import 'package:mygo_mobile/features/home/home_view.dart';
import 'package:mygo_mobile/features/library/saved_albums_view.dart';
import 'package:mygo_mobile/features/liked/liked_view.dart';
import 'package:mygo_mobile/features/recent/recent_view.dart';
import 'package:mygo_mobile/features/stations/stations_view.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// The page of a navigation entry: at the root of the content (no back
/// button), or [pushed] over another page.
Widget entryPage(String pluginId, NavEntry e, {bool pushed = false, Widget? homeHeader}) {
  final back = pushed ? true : false;
  final n = e.item;
  if (e.isRecent) {
    return MgPage(back: back, title: e.title, child: RecentView(pluginId: pluginId, sourcePage: e.recentPage, title: e.title));
  }
  if (n == null) return const SizedBox.shrink();
  if (n.page.isNotEmpty) {
    return MgPage(back: back, title: e.title, child: BrowseView(pluginId: pluginId, page: n.page, title: e.title));
  }
  switch (n.builtin) {
    case 'home':
      return MgPage(back: back, title: e.title, child: HomeView(pluginId: pluginId, header: homeHeader));
    case 'liked':
      return MgPage(back: back, title: e.title, child: LikedView(pluginId: pluginId, title: e.title));
    case 'stations':
      return MgPage(back: back, title: e.title, child: StationsView(pluginId: pluginId, title: e.title));
    case 'savedAlbums':
      return MgPage(back: back, title: e.title, child: SavedAlbumsView(pluginId: pluginId, title: e.title));
  }
  return MgPage(back: back, title: e.title, child: Center(child: Text(svc.s['errUnsupported'])));
}
