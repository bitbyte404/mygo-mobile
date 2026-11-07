// A playlist, the listener's playlists, and a plain list of songs.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/skeletons.dart';
import 'package:mygo_mobile/features/common/tracks.dart';
import 'package:mygo_mobile/features/common/headers.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.pluginId, required this.playlist, this.heroTag});
  final String pluginId;
  final Playlist playlist;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return MgPage(
      title: playlist.name,
      child: Loader<Playlist>(
        pluginId: pluginId,
        skeleton: SkeletonKind.collection,
        load: () => svc.music.playlist(pluginId, playlist.id),
        builder: (context, p, _) => TrackListView(
          tracks: p.tracks,
          header: PageHeader(
            eyebrow: s['playlist'],
            title: p.name.isEmpty ? playlist.name : p.name,
            subtitle: [p.owner, if (p.tracks.isNotEmpty) '${p.tracks.length} ${s['songs']}'].where((x) => x.isNotEmpty).join(' · '),
            imageUrl: p.imageUrl.isNotEmpty ? p.imageUrl : playlist.imageUrl,
            description: p.description,
            heroTag: heroTag,
            icon: MgIcons.playlist,
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
    return MgPage(
      title: title,
      child: TrackListView(
        tracks: tracks,
        header: MgHeading(title, eyebrow: [if (subtitle.isNotEmpty) subtitle, '${tracks.length} ${svc.s['songs']}'].join(' · '), compact: isCompact(context)),
      ),
    );
  }
}

/// The listener's playlists, theirs and saved.
class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key, required this.pluginId});
  final String pluginId;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return MgPage(
      title: s['playlists'],
      child: Loader<List<Playlist>>(
        pluginId: pluginId,
        skeleton: SkeletonKind.cards,
        load: () => svc.music.playlists(pluginId),
        builder: (context, lists, _) {
          final mine = lists.where((p) => p.mine).toList();
          final saved = lists.where((p) => !p.mine).toList();
          Widget tile(Playlist p) => MgListRow(
                leading: CoverArt(p.imageUrl, size: 48, radius: MgRadius.rowCover, icon: MgIcons.playlist),
                label: p.name,
                sub: [if (p.trackCount > 0) '${p.trackCount} ${s['songs']}', p.owner].where((x) => x.isNotEmpty).join(' · '),
                onTap: () => pushPage(context, PlaylistScreen(pluginId: pluginId, playlist: p)),
              );
          return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: pageInsets(context, h: pageHPad(context) - 12), children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: MgHeading(s['playlists'], compact: isCompact(context))),
            if (mine.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: MgSectionTitle(s['myPlaylists'], top: 0)),
            ...mine.map(tile),
            if (saved.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: MgSectionTitle(s['savedPlaylists'])),
            ...saved.map(tile),
            if (lists.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(s['nothing']))),
          ]);
        },
      ),
    );
  }
}

