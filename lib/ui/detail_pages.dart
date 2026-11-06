import 'package:flutter/material.dart';

import '../models.dart';
import '../services.dart';
import 'common.dart';

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key, required this.pluginId, required this.album});
  final String pluginId;
  final Album album;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(album.name)),
      body: Loader<AlbumPage>(
        pluginId: pluginId,
        load: () async => AlbumPage.fromJson((await svc.plugin(pluginId)!.call('album', {'id': album.id})) as Map, pluginId),
        builder: (context, a, _) {
          final al = a.album.name.isEmpty ? album : a.album;
          return TrackListView(
            tracks: a.tracks,
            numbered: true,
            header: PageHeader(
              title: al.name,
              subtitle: [al.artistNames, al.released].where((x) => x.isNotEmpty).join(' · '),
              imageUrl: al.imageUrl.isNotEmpty ? al.imageUrl : album.imageUrl,
            ),
          );
        },
      ),
    );
  }
}

class ArtistScreen extends StatelessWidget {
  const ArtistScreen({super.key, required this.pluginId, required this.artist});
  final String pluginId;
  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return Scaffold(
      appBar: AppBar(title: Text(artist.name)),
      body: Loader<ArtistPage>(
        pluginId: pluginId,
        load: () async => ArtistPage.fromJson((await svc.plugin(pluginId)!.call('artist', {'id': artist.id})) as Map, pluginId),
        builder: (context, a, _) {
          final ar = a.artist.name.isEmpty ? artist : a.artist;
          return TrackListView(
            tracks: a.tracks,
            header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeader(title: ar.name, imageUrl: ar.imageUrl.isNotEmpty ? ar.imageUrl : artist.imageUrl, round: true),
              if (a.albums.isNotEmpty) ...[
                SectionTitle(s['albums']),
                CardRow(children: [
                  for (final al in a.albums)
                    MediaCard(
                      title: al.name,
                      subtitle: al.released,
                      imageUrl: al.imageUrl,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(pluginId: pluginId, album: al))),
                    )
                ]),
                SectionTitle(s['tracks']),
              ],
            ]),
          );
        },
      ),
    );
  }
}

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.pluginId, required this.playlist});
  final String pluginId;
  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: Loader<Playlist>(
        pluginId: pluginId,
        load: () async => Playlist.fromJson((await svc.plugin(pluginId)!.call('playlist', {'id': playlist.id})) as Map, pluginId),
        builder: (context, p, _) => TrackListView(
          tracks: p.tracks,
          header: PageHeader(
            title: p.name.isEmpty ? playlist.name : p.name,
            subtitle: [p.owner, if (p.tracks.isNotEmpty) '${p.tracks.length} ${svc.s['songs']}'].where((x) => x.isNotEmpty).join(' · '),
            imageUrl: p.imageUrl.isNotEmpty ? p.imageUrl : playlist.imageUrl,
            description: p.description,
          ),
        ),
      ),
    );
  }
}

class TrackListScreen extends StatelessWidget {
  const TrackListScreen({super.key, required this.title, this.subtitle = '', required this.tracks});
  final String title, subtitle;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: TrackListView(
        tracks: tracks,
        header: subtitle.isEmpty
            ? null
            : Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('${tracks.length} ${svc.s['songs']} · $subtitle')),
      ),
    );
  }
}

/// Liked songs, a page at a time, as liked({offset}) gives them.
class LikedView extends StatefulWidget {
  const LikedView({super.key, required this.pluginId});
  final String pluginId;

  @override
  State<LikedView> createState() => _LikedViewState();
}

class _LikedViewState extends State<LikedView> {
  final List<Track> _tracks = [];
  bool _more = false;
  bool _loadingMore = false;

  Future<List<Track>> _load() async {
    final r = TrackPage.fromJson((await svc.plugin(widget.pluginId)!.call('liked', {'offset': 0})) as Map, widget.pluginId);
    _tracks
      ..clear()
      ..addAll(r.tracks);
    _more = r.more;
    svc.liked.value = {...svc.liked.value, for (final t in r.tracks) t.key: true};
    return _tracks;
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    _loadingMore = true;
    try {
      final r = TrackPage.fromJson((await svc.plugin(widget.pluginId)!.call('liked', {'offset': _tracks.length})) as Map, widget.pluginId);
      setState(() {
        _tracks.addAll(r.tracks);
        _more = r.more && r.tracks.isNotEmpty;
      });
      svc.liked.value = {...svc.liked.value, for (final t in r.tracks) t.key: true};
    } catch (e) {
      if (mounted) toast(context, svc.describe(e));
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Loader<List<Track>>(
      pluginId: widget.pluginId,
      load: _load,
      builder: (context, tracks, _) => ValueListenableBuilder(
        valueListenable: svc.liked,
        builder: (context, liked, _) {
          // Songs unliked from here leave the list.
          final shown = tracks.where((t) => liked[t.key] != false).toList();
          return TrackListView(tracks: shown, more: _more, onLoadMore: _loadMore);
        },
      ),
    );
  }
}

class LikedScreen extends StatelessWidget {
  const LikedScreen({super.key, required this.pluginId, this.title = ''});
  final String pluginId, title;
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(title.isEmpty ? svc.s['liked'] : title)), body: LikedView(pluginId: pluginId));
}

Future<void> playStation(BuildContext context, String pluginId, Station st) async {
  final p = svc.plugin(pluginId)!;
  try {
    final r = await p.call('stationNext', {'id': st.id});
    final tracks = ((r as List?) ?? const []).whereType<Map>().map((m) => Track.fromJson(m, pluginId)).toList();
    if (tracks.isEmpty) {
      if (context.mounted) toast(context, svc.s['nothing']);
      return;
    }
    await svc.player.playStation(pluginId, st.id, tracks);
  } catch (e) {
    if (context.mounted) toast(context, svc.describe(e));
  }
}

class StationsView extends StatelessWidget {
  const StationsView({super.key, required this.pluginId});
  final String pluginId;

  @override
  Widget build(BuildContext context) {
    return Loader<List<Station>>(
      pluginId: pluginId,
      load: () async => (((await svc.plugin(pluginId)!.call('stations')) as List?) ?? const []).whereType<Map>().map(Station.fromJson).toList(),
      builder: (context, stations, _) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (stations.isEmpty) Center(child: Text(svc.s['nothing'])),
          for (final st in stations)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Cover(st.imageUrl, size: 64, icon: Icons.radio),
                title: Text(st.name, style: Theme.of(context).textTheme.titleMedium),
                subtitle: st.description.isEmpty ? null : Text(st.description),
                trailing: const Icon(Icons.play_circle_fill, size: 40),
                onTap: () => playStation(context, pluginId, st),
              ),
            ),
        ],
      ),
    );
  }
}

class StationsScreen extends StatelessWidget {
  const StationsScreen({super.key, required this.pluginId, this.title = ''});
  final String pluginId, title;
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(title.isEmpty ? svc.s['stations'] : title)), body: StationsView(pluginId: pluginId));
}

class SavedAlbumsScreen extends StatelessWidget {
  const SavedAlbumsScreen({super.key, required this.pluginId, this.title = ''});
  final String pluginId, title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title.isEmpty ? svc.s['savedAlbums'] : title)),
      body: Loader<List<Album>>(
        pluginId: pluginId,
        load: () async {
          final r = (await svc.plugin(pluginId)!.call('savedAlbums', {'offset': 0})) as Map? ?? const {};
          return ((r['albums'] as List?) ?? const []).whereType<Map>().map(Album.fromJson).toList();
        },
        builder: (context, albums, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (albums.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(svc.s['nothing']))),
            for (final a in albums)
              ListTile(
                leading: Cover(a.imageUrl, size: 48),
                title: Text(a.name),
                subtitle: Text(a.artistNames),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(pluginId: pluginId, album: a))),
              ),
          ],
        ),
      ),
    );
  }
}

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key, required this.pluginId});
  final String pluginId;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return Scaffold(
      appBar: AppBar(title: Text(s['playlists'])),
      body: Loader<List<Playlist>>(
        pluginId: pluginId,
        load: () async =>
            (((await svc.plugin(pluginId)!.call('playlists')) as List?) ?? const []).whereType<Map>().map((m) => Playlist.fromJson(m, pluginId)).toList(),
        builder: (context, lists, _) {
          final mine = lists.where((p) => p.mine).toList();
          final saved = lists.where((p) => !p.mine).toList();
          Widget tile(Playlist p) => ListTile(
                leading: Cover(p.imageUrl, size: 48, icon: Icons.queue_music),
                title: Text(p.name),
                subtitle: Text([if (p.trackCount > 0) '${p.trackCount} ${s['songs']}', p.owner].where((x) => x.isNotEmpty).join(' · ')),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(pluginId: pluginId, playlist: p))),
              );
          return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
            if (mine.isNotEmpty) SectionTitle(s['myPlaylists']),
            ...mine.map(tile),
            if (saved.isNotEmpty) SectionTitle(s['savedPlaylists']),
            ...saved.map(tile),
            if (lists.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(s['nothing']))),
          ]);
        },
      ),
    );
  }
}

/// Recently played: what this device played, and the source's own list when
/// the plugin has `recent`.
class RecentScreen extends StatelessWidget {
  const RecentScreen({super.key, this.pluginId});
  final String? pluginId;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final p = pluginId == null ? null : svc.plugin(pluginId!);
    final hasSource = p != null && p.can('recent');
    final local = ListenableBuilder(
      listenable: svc.app,
      builder: (context, _) => TrackListView(tracks: svc.app.history),
    );
    if (!hasSource) {
      return Scaffold(
        appBar: AppBar(title: Text(s['recent']), actions: [
          IconButton(icon: const Icon(Icons.delete_sweep_outlined), tooltip: s['clearHistory'], onPressed: svc.app.clearHistory),
        ]),
        body: local,
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s['recent']),
          bottom: TabBar(tabs: [Tab(text: s['fromSource']), Tab(text: s['fromLocal'])]),
          actions: [IconButton(icon: const Icon(Icons.delete_sweep_outlined), tooltip: s['clearHistory'], onPressed: svc.app.clearHistory)],
        ),
        body: TabBarView(children: [
          Loader<List<Track>>(
            pluginId: pluginId,
            load: () async => (((await p.call('recent')) as List?) ?? const []).whereType<Map>().map((m) => Track.fromJson(m, pluginId!)).toList(),
            builder: (context, tracks, _) => TrackListView(tracks: tracks),
          ),
          local,
        ]),
      ),
    );
  }
}
