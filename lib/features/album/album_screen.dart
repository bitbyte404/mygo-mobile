// An album: its header and numbered songs.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/skeletons.dart';
import 'package:mygo_mobile/features/common/tracks.dart';
import 'package:mygo_mobile/features/common/headers.dart';
import 'package:mygo_mobile/ui/ui.dart';

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key, required this.pluginId, required this.album, this.heroTag});
  final String pluginId;
  final Album album;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return MgPage(
      title: album.name,
      child: Loader<AlbumPage>(
        pluginId: pluginId,
        skeleton: SkeletonKind.collection,
        load: () => svc.music.album(pluginId, album.id),
        cacheKey: '$pluginId/album/${album.id}',
        builder: (context, a, _) {
          final al = a.album.name.isEmpty ? album : a.album;
          final meta = [al.artistNames, al.released, if (a.tracks.isNotEmpty) '${a.tracks.length} ${s['songs']}'].where((x) => x.isNotEmpty).join(' · ');
          return TrackListView(
            tracks: a.tracks,
            numbered: true,
            showAlbum: false,
            header: PageHeader(
              eyebrow: s['album'],
              title: al.name,
              subtitle: meta,
              imageUrl: al.imageUrl.isNotEmpty ? al.imageUrl : album.imageUrl,
              heroTag: heroTag,
              icon: MgIcons.album,
            ),
          );
        },
      ),
    );
  }
}

