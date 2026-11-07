// Liked songs under the gradient heart (ui_pages.go likedPage).
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/common/headers.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/tracks.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'liked_controller.dart';

class LikedView extends StatefulWidget {
  const LikedView({super.key, required this.pluginId, this.title = ''});
  final String pluginId, title;

  @override
  State<LikedView> createState() => _LikedViewState();
}

class _LikedViewState extends State<LikedView> {
  late final LikedController _c = LikedController(
    (offset) => svc.music.liked(widget.pluginId, offset: offset),
    onTracks: (t) => svc.likes.mark(t, true),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return Loader<List<Track>>(
      pluginId: widget.pluginId,
      load: _c.load,
      builder: (context, _, _) => ListenableBuilder(
        listenable: Listenable.merge([_c, svc.likes.liked]),
        builder: (context, _) {
          final liked = svc.likes.liked.value;
          // Songs unliked from here leave the list.
          final shown = _c.tracks.where((t) => liked[t.key] != false).toList();
          final size = isCompact(context) ? 160.0 : MgSize.headerCover;
          return TrackListView(
            tracks: shown,
            more: _c.more,
            onLoadMore: _c.loadMore,
            playAll: () => _c.all(keep: (t) => svc.likes.liked.value[t.key] != false),
            header: PageHeader(
              eyebrow: s['playlist'],
              title: widget.title.isEmpty ? s['liked'] : widget.title,
              subtitle: '${shown.length}${_c.more ? '+' : ''} ${s['songs']}',
              cover: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(gradient: likedGradient, borderRadius: BorderRadius.circular(MgRadius.header)),
                child: Center(child: MgIcon(MgIcons.heartFill, size: size * 0.4, color: Colors.white)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class LikedScreen extends StatelessWidget {
  const LikedScreen({super.key, required this.pluginId, this.title = ''});
  final String pluginId, title;
  @override
  Widget build(BuildContext context) => MgPage(title: title.isEmpty ? svc.s['liked'] : title, child: LikedView(pluginId: pluginId, title: title));
}
