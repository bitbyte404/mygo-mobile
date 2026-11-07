// A plugin's browse pages (and Home's body): sections of songs and cards.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/album/album_screen.dart';
import 'package:mygo_mobile/features/artist/artist_screen.dart';
import 'package:mygo_mobile/features/common/cards.dart';
import 'package:mygo_mobile/features/common/headers.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/tracks.dart';
import 'package:mygo_mobile/features/playlist/playlist_screens.dart';
import 'package:mygo_mobile/features/shell/destinations.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/features/stations/stations_view.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// One of a plugin's browse pages, at the root (no back button) or pushed.
class BrowseView extends StatelessWidget {
  const BrowseView({super.key, required this.pluginId, required this.page, this.title = ''});
  final String pluginId, page, title;

  Future<Browse> _load() => svc.music.browse(pluginId, page);

  @override
  Widget build(BuildContext context) {
    return Loader<Browse>(
      key: ValueKey('$pluginId/$page'),
      pluginId: pluginId,
      load: _load,
      builder: (context, b, _) => BrowseBody(pluginId: pluginId, browse: b, fallbackTitle: title),
    );
  }
}

class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key, required this.pluginId, required this.page, this.title = ''});
  final String pluginId, page, title;

  @override
  Widget build(BuildContext context) => MgPage(title: title, child: BrowseView(pluginId: pluginId, page: page, title: title));
}

/// A browse page's sections (ui_browse.go browseRows): titles 19/700 with
/// "See all", songs as rows, everything else as cards.
class BrowseBody extends StatelessWidget {
  const BrowseBody({super.key, required this.pluginId, required this.browse, this.header, this.fallbackTitle = '', this.chips = false});
  final String pluginId;
  final Browse browse;
  final Widget? header;
  final String fallbackTitle;
  final bool chips;

  @override
  Widget build(BuildContext context) {
    final b = browse;
    final pad = MediaQuery.paddingOf(context);
    final h = pageHPad(context);
    Widget padded(Widget w, {double inset = 0}) => Padding(padding: EdgeInsets.fromLTRB(h - inset + pad.left, 0, h - inset + pad.right, 0), child: w);
    final children = <Widget>[];
    if (header != null) {
      children.add(padded(header!));
    } else {
      final title = b.title.isNotEmpty ? b.title : fallbackTitle;
      if (b.imageUrl.isNotEmpty) {
        children.add(padded(PageHeader(title: title, subtitle: b.subtitle, imageUrl: b.imageUrl, description: b.description, round: true, icon: MgIcons.user)));
      } else if (title.isNotEmpty) {
        children.add(padded(MgHeading(title, eyebrow: b.subtitle, compact: isCompact(context))));
      }
    }
    if (chips) children.add(_NavChips(pluginId: pluginId));
    final trackOnly = b.sections.length == 1 && b.sections.first.tracks.isNotEmpty;
    for (var i = 0; i < b.sections.length; i++) {
      children.addAll(_section(context, b.sections[i], i, full: trackOnly, padded: padded));
    }
    if (b.sections.isEmpty) {
      children.add(Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(svc.s['nothing'], style: TextStyle(color: context.mg.muted)))));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(0, pad.top + MgSize.pageGap, 0, pad.bottom + 32),
      children: children,
    );
  }

  List<Widget> _section(BuildContext context, Section sec, int index, {required bool full, required Widget Function(Widget, {double inset}) padded}) {
    final out = <Widget>[];
    final p = context.mg;
    VoidCallback? more;
    final pageTitle = sec.pageTitle.isNotEmpty ? sec.pageTitle : sec.title;
    if (sec.morePage.isNotEmpty) {
      more = () => pushPage(context, BrowseScreen(pluginId: pluginId, page: sec.morePage, title: pageTitle));
    } else if (sec.tracks.length > 8 && !full) {
      more = () => pushPage(context, TrackListScreen(title: pageTitle, subtitle: sec.subtitle, tracks: sec.tracks));
    }
    if (sec.title.isNotEmpty) out.add(SectionTitle(sec.title, onMore: more, first: index == 0 && header == null));
    if (sec.isEmpty) {
      if (sec.empty.isNotEmpty) out.add(padded(Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(sec.empty, style: TextStyle(color: p.muted)))));
      return out;
    }
    if (sec.tracks.isNotEmpty) {
      final shown = full ? sec.tracks : sec.tracks.take(8).toList();
      if (full) {
        out.add(padded(Padding(padding: const EdgeInsets.only(bottom: 12), child: PlayButtons(tracks: sec.tracks))));
      }
      for (var i = 0; i < shown.length; i++) {
        out.add(padded(TrackTile(track: shown[i], onTap: () => svc.player.playTracks(sec.tracks, start: i)), inset: isCompact(context) ? 8 : 12));
      }
    }
    final tag = '$pluginId/$index';
    if (sec.albums.isNotEmpty) {
      out.add(CardRow(
        count: sec.albums.length,
        itemBuilder: (context, i, w) {
          final a = sec.albums[i];
          final hero = 'album:$tag/$i/${a.id}';
          return MediaCard(width: w, title: a.name, subtitle: a.artistNames, imageUrl: a.imageUrl, heroTag: hero, icon: MgIcons.album, onTap: () => pushPage(context, AlbumScreen(pluginId: pluginId, album: a, heroTag: hero)));
        },
      ));
    }
    if (sec.playlists.isNotEmpty) {
      out.add(CardRow(
        count: sec.playlists.length,
        itemBuilder: (context, i, w) {
          final pl = sec.playlists[i];
          final hero = 'playlist:$tag/$i/${pl.id}';
          final sub = [if (pl.trackCount > 0) '${pl.trackCount} ${svc.s['songs']}', pl.owner].where((x) => x.isNotEmpty).join(' · ');
          return MediaCard(width: w, title: pl.name, subtitle: sub, imageUrl: pl.imageUrl, heroTag: hero, icon: MgIcons.playlist, onTap: () => pushPage(context, PlaylistScreen(pluginId: pluginId, playlist: pl, heroTag: hero)));
        },
      ));
    }
    if (sec.artists.isNotEmpty) {
      out.add(CardRow(
        count: sec.artists.length,
        cardWidth: 120,
        itemBuilder: (context, i, w) {
          final a = sec.artists[i];
          final hero = 'artist:$tag/$i/${a.id}';
          return MediaCard(width: w, title: a.name, imageUrl: a.imageUrl, round: true, heroTag: hero, icon: MgIcons.user, onTap: () => pushPage(context, ArtistScreen(pluginId: pluginId, artist: a, heroTag: hero)));
        },
      ));
    }
    if (sec.stations.isNotEmpty) {
      out.add(CardRow(
        count: sec.stations.length,
        itemBuilder: (context, i, w) {
          final st = sec.stations[i];
          return MediaCard(width: w, title: st.name, subtitle: st.description, imageUrl: st.imageUrl, icon: MgIcons.radio, onTap: () => playStation(context, pluginId, st));
        },
      ));
    }
    if (sec.shows.isNotEmpty) {
      out.add(CardRow(
        count: sec.shows.length,
        itemBuilder: (context, i, w) {
          final sh = sec.shows[i];
          return MediaCard(width: w, title: sh.name, subtitle: sh.publisher, imageUrl: sh.imageUrl, icon: MgIcons.podcast, onTap: () => toast(context, svc.s['errUnsupported']));
        },
      ));
    }
    for (final l in sec.links) {
      out.add(padded(
        MgListRow(
          leading: l.imageUrl.isNotEmpty ? CoverArt(l.imageUrl, size: 44, radius: MgRadius.rowCover) : null,
          icon: MgIcons.forward,
          label: l.title,
          sub: l.subtitle,
          trailing: MgIcon(MgIcons.forward, size: 16, color: p.faint),
          onTap: () => pushPage(context, BrowseScreen(pluginId: pluginId, page: l.page, title: l.title)),
        ),
        inset: 12,
      ));
    }
    return out;
  }
}

/// The plugin's other pages as a row of chips under Home's greeting, on a
/// phone, where there is no sidebar to list them.
class _NavChips extends StatelessWidget {
  const _NavChips({required this.pluginId});
  final String pluginId;

  @override
  Widget build(BuildContext context) {
    final entries = svc.navEntries(svc.plugin(pluginId)).where((e) => !e.isHome).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final pad = MediaQuery.paddingOf(context);
    final h = pageHPad(context);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: h + pad.left),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = entries[i];
          return MgChip(label: e.title, icon: navIcon(e.icon), selected: false, onTap: () => pushPage(context, entryPage(pluginId, e, pushed: true)));
        },
      ),
    );
  }
}

