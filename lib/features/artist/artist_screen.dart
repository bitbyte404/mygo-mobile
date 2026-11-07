// An artist: header, albums, songs.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/skeletons.dart';
import 'package:mygo_mobile/features/common/tracks.dart';
import 'package:mygo_mobile/features/common/headers.dart';
import 'package:mygo_mobile/features/album/album_screen.dart';
import 'package:mygo_mobile/features/common/cards.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

class ArtistScreen extends StatelessWidget {
  const ArtistScreen({super.key, required this.pluginId, required this.artist, this.heroTag});
  final String pluginId;
  final Artist artist;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return MgPage(
      title: artist.name,
      child: Loader<ArtistPage>(
        pluginId: pluginId,
        skeleton: SkeletonKind.artist,
        load: () => svc.music.artist(pluginId, artist.id),
        cacheKey: '$pluginId/artist/${artist.id}',
        builder: (context, a, _) {
          final ar = a.artist.name.isEmpty ? artist : a.artist;
          return TrackListView(
            tracks: a.tracks,
            header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeader(eyebrow: s['artist'], title: ar.name, imageUrl: ar.imageUrl.isNotEmpty ? ar.imageUrl : artist.imageUrl, round: true, heroTag: heroTag, icon: MgIcons.user),
              if (a.albums.isNotEmpty) ...[
                MgSectionTitle(s['albums'], top: 0),
                MediaQuery.removePadding(
                  context: context,
                  removeLeft: true,
                  removeRight: true,
                  child: Transform.translate(
                    offset: Offset(-pageHPad(context), 0),
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width,
                      child: CardRow(
                        count: a.albums.length,
                        grid: false,
                        itemBuilder: (context, i, w) {
                          final al = a.albums[i];
                          final hero = 'album:artist/${ar.id}/$i/${al.id}';
                          return MediaCard(width: w, title: al.name, subtitle: al.released, imageUrl: al.imageUrl, heroTag: hero, icon: MgIcons.album, onTap: () => pushPage(context, AlbumScreen(pluginId: pluginId, album: al, heroTag: hero)));
                        },
                      ),
                    ),
                  ),
                ),
                MgSectionTitle(s['tracks']),
              ],
            ]),
          );
        },
      ),
    );
  }
}

