import 'package:flutter/material.dart';

import '../models.dart';
import '../services.dart';
import 'common.dart';
import 'detail_pages.dart';

/// A plugin's Home (page == null) or one of its browse pages.
class BrowseView extends StatelessWidget {
  const BrowseView({super.key, required this.pluginId, this.page});
  final String pluginId;
  final String? page;

  Future<Browse> _load() async {
    final p = svc.plugin(pluginId)!;
    final r = page == null ? await p.call('home') : await p.call('browse', {'page': page});
    return Browse.fromJson((r as Map?) ?? const {}, pluginId);
  }

  @override
  Widget build(BuildContext context) {
    return Loader<Browse>(
      key: ValueKey('$pluginId/${page ?? 'home'}'),
      pluginId: pluginId,
      load: _load,
      builder: (context, b, _) => BrowseBody(pluginId: pluginId, browse: b, showHeader: page != null),
    );
  }
}

class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key, required this.pluginId, required this.page, this.title = ''});
  final String pluginId, page, title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: BrowseView(pluginId: pluginId, page: page),
    );
  }
}

class BrowseBody extends StatelessWidget {
  const BrowseBody({super.key, required this.pluginId, required this.browse, this.showHeader = true});
  final String pluginId;
  final Browse browse;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final b = browse;
    final children = <Widget>[];
    if (showHeader || b.imageUrl.isNotEmpty) {
      if (b.title.isNotEmpty || b.imageUrl.isNotEmpty) {
        children.add(PageHeader(
          title: b.title,
          subtitle: b.subtitle,
          imageUrl: b.imageUrl,
          description: b.description,
          round: b.imageUrl.isNotEmpty,
        ));
      }
    } else if (b.title.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(b.title, style: Theme.of(context).textTheme.headlineSmall),
      ));
    }
    // A page that is one section of tracks is shown as a list with play-all.
    final trackOnly = b.sections.length == 1 && b.sections.first.tracks.isNotEmpty;
    for (final sec in b.sections) {
      children.addAll(_section(context, sec, full: trackOnly));
    }
    if (b.sections.isEmpty) {
      children.add(Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(svc.s['nothing']))));
    }
    children.add(const SizedBox(height: 24));
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: children);
  }

  List<Widget> _section(BuildContext context, Section sec, {bool full = false}) {
    final out = <Widget>[];
    VoidCallback? more;
    if (sec.morePage.isNotEmpty) {
      more = () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => BrowseScreen(pluginId: pluginId, page: sec.morePage, title: sec.pageTitle.isNotEmpty ? sec.pageTitle : sec.title)));
    } else if (sec.tracks.length > 8 && !full) {
      more = () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TrackListScreen(
                  title: sec.pageTitle.isNotEmpty ? sec.pageTitle : sec.title, subtitle: sec.subtitle, tracks: sec.tracks)));
    }
    if (sec.title.isNotEmpty) out.add(SectionTitle(sec.title, onMore: more));
    if (sec.isEmpty) {
      if (sec.empty.isNotEmpty) {
        out.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(sec.empty)));
      }
      return out;
    }
    if (sec.tracks.isNotEmpty) {
      final shown = full ? sec.tracks : sec.tracks.take(8).toList();
      if (full) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            FilledButton.icon(
              onPressed: () => svc.player.playTracks(sec.tracks),
              icon: const Icon(Icons.play_arrow),
              label: Text('${svc.s['playAll']} (${sec.tracks.length})'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => svc.player.playTracks(sec.tracks, start: -1, shuffled: true),
              icon: const Icon(Icons.shuffle),
              label: Text(svc.s['shuffle']),
            ),
          ]),
        ));
      }
      for (var i = 0; i < shown.length; i++) {
        out.add(TrackTile(track: shown[i], onTap: () => svc.player.playTracks(sec.tracks, start: i)));
      }
    }
    if (sec.albums.isNotEmpty) {
      out.add(CardRow(children: [
        for (final a in sec.albums)
          MediaCard(
            title: a.name,
            subtitle: a.artistNames,
            imageUrl: a.imageUrl,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(pluginId: pluginId, album: a))),
          )
      ]));
    }
    if (sec.playlists.isNotEmpty) {
      out.add(CardRow(children: [
        for (final p in sec.playlists)
          MediaCard(
            title: p.name,
            subtitle: p.owner,
            imageUrl: p.imageUrl,
            icon: Icons.queue_music,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(pluginId: pluginId, playlist: p))),
          )
      ]));
    }
    if (sec.artists.isNotEmpty) {
      out.add(CardRow(height: 175, children: [
        for (final a in sec.artists)
          MediaCard(
            title: a.name,
            imageUrl: a.imageUrl,
            round: true,
            icon: Icons.person,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(pluginId: pluginId, artist: a))),
          )
      ]));
    }
    if (sec.stations.isNotEmpty) {
      out.add(CardRow(children: [
        for (final st in sec.stations)
          MediaCard(
            title: st.name,
            subtitle: st.description,
            imageUrl: st.imageUrl,
            icon: Icons.radio,
            onTap: () => playStation(context, pluginId, st),
          )
      ]));
    }
    if (sec.shows.isNotEmpty) {
      out.add(CardRow(children: [
        for (final sh in sec.shows) MediaCard(title: sh.name, subtitle: sh.publisher, imageUrl: sh.imageUrl, icon: Icons.podcasts, onTap: () {})
      ]));
    }
    for (final l in sec.links) {
      out.add(ListTile(
        leading: l.imageUrl.isNotEmpty ? Cover(l.imageUrl, size: 44) : const Icon(Icons.chevron_right),
        title: Text(l.title),
        subtitle: l.subtitle.isEmpty ? null : Text(l.subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowseScreen(pluginId: pluginId, page: l.page, title: l.title))),
      ));
    }
    return out;
  }
}
