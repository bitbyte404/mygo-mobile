// The queue in play order, the song playing marked (ui_nowplaying.go
// queuePane): rows 58 tall, 12-point corners, a tap plays one there.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/ui/ui.dart';

class QueueView extends StatefulWidget {
  const QueueView({super.key});

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  static const rowH = 60.0;
  late final ScrollController _scroll = ScrollController(initialScrollOffset: _offsetOfCurrent());

  double _offsetOfCurrent() {
    final at = svc.player.order.indexOf(svc.player.index);
    return at <= 0 ? 0 : (at - 1) * rowH;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    return ValueListenableBuilder<List<Track>>(
      valueListenable: svc.player.tracks,
      builder: (context, tracks, _) => ValueListenableBuilder<Track?>(
        valueListenable: svc.player.current,
        builder: (context, cur, _) {
          final order = svc.player.order;
          return ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 40),
            itemExtent: rowH,
            itemCount: order.length,
            itemBuilder: (context, r) {
              final i = order[r];
              if (i >= tracks.length) return const SizedBox.shrink();
              final t = tracks[i];
              final playing = i == svc.player.index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Opacity(
                  opacity: t.unavailable ? 0.4 : 1,
                  child: Pressable(
                    onTap: playing || t.unavailable ? null : () => svc.player.skipToQueueItem(i),
                    pressedScale: 0.985,
                    color: playing ? white.withValues(alpha: 0.12) : Colors.transparent,
                    pressedColor: white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(MgRadius.queueRow),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(children: [
                      CoverArt(t.album.imageUrl, size: 42, radius: 7),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: white)),
                          const SizedBox(height: 3),
                          Text(t.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: white.withValues(alpha: 0.55))),
                        ]),
                      ),
                      if (t.duration > 0)
                        Text(fmtDuration(Duration(milliseconds: t.duration)), style: TextStyle(fontSize: 12, color: white.withValues(alpha: 0.4), fontFeatures: MgType.tnum)),
                      if (!playing) MgIconButton(MgIcons.x, size: 15, color: white.withValues(alpha: 0.45), tooltip: svc.s['remove'], onTap: () => svc.player.removeAt(i)),
                      if (playing) const SizedBox(width: 44),
                    ]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
