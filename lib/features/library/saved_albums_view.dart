// Saved albums.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/album/album_screen.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/skeletons.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

class SavedAlbumsView extends StatelessWidget {
  const SavedAlbumsView({super.key, required this.pluginId, this.title = ''});
  final String pluginId, title;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return Loader<List<Album>>(
      pluginId: pluginId,
      skeleton: SkeletonKind.cards,
      load: () => svc.music.savedAlbums(pluginId),
      builder: (context, albums, _) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pageInsets(context),
        children: [
          MgHeading(title.isEmpty ? svc.s['savedAlbums'] : title, compact: isCompact(context)),
          if (albums.isEmpty) Center(child: Text(svc.s['nothing'], style: TextStyle(color: p.muted))),
          for (final a in albums)
            MgListRow(
              leading: CoverArt(a.imageUrl, size: 48, radius: MgRadius.rowCover, icon: MgIcons.album),
              label: a.name,
              sub: a.artistNames,
              onTap: () => pushPage(context, AlbumScreen(pluginId: pluginId, album: a)),
            ),
        ],
      ),
    );
  }
}

