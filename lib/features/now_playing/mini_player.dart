// The player along the foot: a floating card over the tab bar on a phone
// (MiniPlayer), the desktop's 84-point bar beside the sidebar on wider
// screens (PlayerBar, ui_player.go playerBar). Now Playing grows out of
// either; their cover hides while it is out.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'controls.dart';
import 'now_playing_controller.dart';

/// The cover Now Playing grows out of: hidden while it is out.
class _FromCover extends StatelessWidget {
  const _FromCover({required this.track, required this.size});
  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: nowPlaying.progress,
      builder: (context, t, child) => Opacity(opacity: t > 0.001 ? 0 : 1, child: child),
      child: KeyedSubtree(
        key: nowPlaying.fromCoverKey,
        child: CoverArt(track.album.imageUrl, size: size, radius: MgRadius.barCover, shadow: true),
      ),
    );
  }
}

class _Sub extends StatelessWidget {
  const _Sub({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    // What it waits on shows in place of the artists.
    return ValueListenableBuilder<bool>(
      valueListenable: svc.player.loading,
      builder: (_, loading, _) => ValueListenableBuilder<String?>(
        valueListenable: svc.player.error,
        builder: (_, err, _) {
          final text = loading ? svc.s['buffering'] : (err != null ? svc.s['errUnavailable'] : track.artistNames);
          return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.barSub.copyWith(color: err != null && !loading ? p.accent : p.muted));
        },
      ),
    );
  }
}

/// The phone's mini player: a card 60 tall over the tab bar. A tap opens Now
/// Playing; dragging it up pulls Now Playing out with the finger.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return ValueListenableBuilder<Track?>(
      valueListenable: svc.player.current,
      builder: (context, t, _) {
        if (t == null) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => nowPlaying.open(),
          onVerticalDragUpdate: (d) => nowPlaying.onDragUpdate?.call(d.delta.dy),
          onVerticalDragEnd: (d) => nowPlaying.onDragEnd?.call(d.velocity.pixelsPerSecond.dy),
          child: Container(
            key: nowPlaying.fromBarKey,
            height: MgSize.miniPlayerHeight,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: p.popover,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.popoverEdge, width: 0.5),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.4 : 0.12), blurRadius: 24, spreadRadius: -6, offset: const Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                  child: Row(children: [
                    _FromCover(track: t, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.barTitle.copyWith(fontSize: 14, color: p.text)),
                        const SizedBox(height: 2),
                        _Sub(track: t),
                      ]),
                    ),
                    const PlayButton(size: 22),
                    MgIconButton(MgIcons.next, size: 20, color: p.text, tooltip: svc.s['next'], onTap: svc.player.skipToNext),
                  ]),
                ),
                Positioned(left: 14, right: 14, bottom: 0, height: 2, child: _ThinProgress(track: t)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _ThinProgress extends StatelessWidget {
  const _ThinProgress({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return ValueListenableBuilder<Duration>(
      valueListenable: svc.player.positionN,
      builder: (context, pos, _) {
        final len = trackLength(track).inMilliseconds;
        final f = len <= 0 ? 0.0 : (pos.inMilliseconds / len).clamp(0.0, 1.0);
        return Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: f,
            child: DecoratedBox(decoration: BoxDecoration(color: p.text.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(1))),
          ),
        );
      },
    );
  }
}

/// The desktop's player bar: what plays (cover, title, artists, heart), the
/// transport over the progress in the middle, lyrics / queue / volume at the
/// end.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return ValueListenableBuilder<Track?>(
      valueListenable: svc.player.current,
      builder: (context, t, _) {
        return SizedBox(
          height: MgSize.playerBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LayoutBuilder(builder: (context, c) {
              final middle = c.maxWidth >= 760 ? 440.0 : (c.maxWidth * 0.46).clamp(260.0, 440.0);
              return Row(children: [
                Expanded(
                  child: t == null
                      ? Row(children: [
                          Container(width: 48, height: 48, decoration: BoxDecoration(color: p.hover, borderRadius: BorderRadius.circular(8)), child: Center(child: MgIcon(MgIcons.note, size: 18, color: p.faint))),
                          const SizedBox(width: 12),
                          Flexible(child: Text(svc.s['notPlaying'], style: TextStyle(fontSize: 13, color: p.muted))),
                        ])
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => nowPlaying.open(),
                          child: Row(children: [
                            KeyedSubtree(key: nowPlaying.fromBarKey, child: _FromCover(track: t, size: 48)),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.barTitle.copyWith(color: p.text)),
                                const SizedBox(height: 3),
                                _Sub(track: t),
                              ]),
                            ),
                            LikeButton(track: t, size: 16),
                          ]),
                        ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: middle,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Transport(size: 18, color: p.text, dim: p.muted, on: p.accent),
                    if (t != null) SizedBox(height: 18, child: ProgressBlock(track: t, onDark: false, sideTimes: true)),
                  ]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    MgIconButton(MgIcons.lyrics, size: 16, color: p.muted, tooltip: svc.s['lyrics'], onTap: t == null ? null : () => nowPlaying.open(pane: NpPane.lyrics)),
                    MgIconButton(MgIcons.queue, size: 16, color: p.muted, tooltip: svc.s['queue'], onTap: t == null ? null : () => nowPlaying.open(pane: NpPane.queue)),
                    if (c.maxWidth >= 900) const _Volume(),
                  ]),
                ),
              ]);
            }),
          ),
        );
      },
    );
  }
}

/// A slim volume slider with the speaker before it, which mutes
/// (ui_player.go volumeSlider).
class _Volume extends StatefulWidget {
  const _Volume();

  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  double _v = 1, _mutedFrom = 1;

  @override
  void initState() {
    super.initState();
    _v = svc.player.audio.volume;
  }

  void _set(double v) {
    setState(() => _v = v.clamp(0.0, 1.0));
    svc.player.audio.setVolume(_v);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final icon = _v == 0 ? MgIcons.mute : (_v < 0.4 ? MgIcons.volumeLow : MgIcons.volume);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      MgIconButton(icon, size: 16, color: p.text.withValues(alpha: 0.75), tooltip: svc.s['volume'], onTap: () {
        if (_v > 0) {
          _mutedFrom = _v;
          _set(0);
        } else {
          _set(_mutedFrom > 0 ? _mutedFrom : 0.5);
        }
      }),
      SizedBox(width: 96, child: Scrubber(value: _v * 1000, max: 1000, height: 16, guardEnd: false, onDrag: (v) {
        if (v != null) _set(v / 1000);
      }, onSeek: (v) => _set(v / 1000))),
    ]);
  }
}
