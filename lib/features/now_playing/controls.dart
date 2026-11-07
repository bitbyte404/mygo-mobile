// The player's controls, shared by the mini player, the player bar and Now
// Playing: transport (ui_player.go transport), like, the lossless badge, the
// progress with its times.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/data/player/player.dart';
import 'package:mygo_mobile/features/common/tracks.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// Play/pause, the glyph swapping on its spring; a spinner while the
/// stream loads.
class PlayButton extends StatelessWidget {
  const PlayButton({super.key, this.size = 24, this.color, this.filled = false});
  final double size;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = svc.player;
    final c = color ?? context.mg.text;
    return ValueListenableBuilder<bool>(
      valueListenable: p.loading,
      builder: (context, loading, _) => ValueListenableBuilder<bool>(
        valueListenable: p.playingN,
        builder: (context, playing, _) {
          final glyph = loading ? SizedBox.square(dimension: size, child: Center(child: MgSpinner(size: size * 0.8, color: c))) : PlayPauseGlyph(playing: playing, size: size, color: filled ? context.mg.bg : c);
          return Pressable(
            onTap: playing ? p.pause : p.play,
            pressedScale: 0.88,
            shape: BoxShape.circle,
            color: filled ? c : Colors.transparent,
            pressedColor: filled ? c.withValues(alpha: 0.85) : const Color.fromRGBO(128, 128, 128, 0.14),
            semanticLabel: svc.s['playPause'],
            child: SizedBox.square(dimension: size + (filled ? 28 : 16), child: Center(child: glyph)),
          );
        },
      ),
    );
  }
}

/// Shuffle, previous, play, next, repeat, at [size] (MyGo: shuffle 0.62,
/// skip 0.85, play 1.25 of it), [on] marking shuffle and repeat when set.
class Transport extends StatelessWidget {
  const Transport({super.key, this.size = 28, this.color, this.dim, this.on, this.spread = false});
  final double size;
  final Color? color, dim, on;
  final bool spread;

  @override
  Widget build(BuildContext context) {
    final p = svc.player;
    final c = color ?? context.mg.text;
    final d = dim ?? context.mg.muted;
    final o = on ?? context.mg.accent;
    final children = [
      ValueListenableBuilder<bool>(
        valueListenable: p.shuffle,
        builder: (_, s, _) => MgIconButton(MgIcons.shuffle, size: size * 0.62, color: s ? o : d, tooltip: svc.s['shuffle'], onTap: p.toggleShuffle),
      ),
      MgIconButton(MgIcons.prev, size: size * 0.85, color: c, tooltip: svc.s['previous'], onTap: p.skipToPrevious),
      PlayButton(size: size * 1.25, color: c),
      MgIconButton(MgIcons.next, size: size * 0.85, color: c, tooltip: svc.s['next'], onTap: p.skipToNext),
      ValueListenableBuilder<Repeat>(
        valueListenable: p.repeat,
        builder: (_, r, _) => MgIconButton(r == Repeat.one ? MgIcons.repeat1 : MgIcons.repeat, size: size * 0.62, color: r == Repeat.off ? d : o, tooltip: svc.s['repeat'], onTap: p.cycleRepeat),
      ),
    ];
    return Row(
      mainAxisSize: spread ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: spread ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
      children: spread ? children : [for (final w in children) Padding(padding: EdgeInsets.symmetric(horizontal: size * 0.12), child: w)],
    );
  }
}

/// The heart of a song, filled in the accent when liked.
class LikeButton extends StatelessWidget {
  const LikeButton({super.key, required this.track, this.size = 22, this.color});
  final Track track;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!svc.music.can(track.source, 'like')) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: svc.likes.liked,
      builder: (context, liked, _) {
        final on = liked[track.key] ?? false;
        return MgIconButton(
          on ? MgIcons.heartFill : MgIcons.heart,
          size: size,
          color: on ? context.mg.accent : (color ?? context.mg.muted),
          tooltip: on ? svc.s['unlike'] : svc.s['like'],
          onTap: () async {
            try {
              await svc.likes.setLiked(track, !on);
            } catch (e) {
              if (context.mounted) toast(context, svc.describe(e));
            }
          },
        );
      },
    );
  }
}

class MoreButton extends StatelessWidget {
  const MoreButton({super.key, required this.track, this.size = 22, this.color});
  final Track track;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => MgIconButton(MgIcons.more, size: size, color: color ?? context.mg.muted, tooltip: svc.s['more'], onTap: () => showTrackMenu(context, track));
}

/// "Lossless" in gold while a lossless stream plays (qualityBadge).
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, this.stream});
  final StreamInfo? stream;

  @override
  Widget build(BuildContext context) {
    final st = stream;
    if (st == null || (st.quality != 'lossless' && st.type != 'flac' && st.type != 'wav')) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: losslessGold.withValues(alpha: 0.55))),
      child: Text(svc.s['losslessBadge'], style: MgType.badge.copyWith(color: losslessGold)),
    );
  }
}

/// The track's length: the player's once known, else the plugin's.
Duration trackLength(Track? t) {
  final d = svc.player.duration;
  if (d != null && d > Duration.zero) return d;
  return Duration(milliseconds: t?.duration ?? 0);
}

/// The scrubber over the time played, the badge, and the time left
/// (Now Playing), or played / length either side (the bar).
class ProgressBlock extends StatefulWidget {
  const ProgressBlock({super.key, required this.track, this.onDark = true, this.sideTimes = false});
  final Track track;
  final bool onDark, sideTimes;

  @override
  State<ProgressBlock> createState() => _ProgressBlockState();
}

class _ProgressBlockState extends State<ProgressBlock> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final on = widget.onDark;
    final track = on ? Colors.white.withValues(alpha: 0.18) : p.press;
    final fill = on ? Colors.white.withValues(alpha: 0.9) : p.text.withValues(alpha: 0.75);
    final timeColor = on ? Colors.white.withValues(alpha: 0.5) : p.faint;
    return ValueListenableBuilder<Duration>(
      valueListenable: svc.player.positionN,
      builder: (context, pos, _) {
        final len = trackLength(widget.track);
        final at = _drag != null ? Duration(milliseconds: _drag!.round()) : pos;
        final scrub = Scrubber(
          value: pos.inMilliseconds.toDouble(),
          max: len.inMilliseconds.toDouble(),
          track: track,
          fill: fill,
          onDrag: (v) => setState(() => _drag = v),
          onSeek: (v) => svc.player.seek(Duration(milliseconds: v.round())),
        );
        final ts = (on ? MgType.npTime : MgType.barTime).copyWith(color: timeColor);
        if (widget.sideTimes) {
          return Row(children: [
            SizedBox(width: 40, child: Text(fmtClock(at), textAlign: TextAlign.end, style: ts)),
            const SizedBox(width: 10),
            Expanded(child: scrub),
            const SizedBox(width: 10),
            SizedBox(width: 40, child: Text(fmtClock(len), style: ts)),
          ]);
        }
        return Column(children: [
          scrub,
          SizedBox(
            height: 18,
            child: Row(children: [
              Text(fmtClock(at), style: ts),
              const Spacer(),
              ValueListenableBuilder<StreamInfo?>(valueListenable: svc.player.streamInfo, builder: (_, st, _) => QualityBadge(stream: st)),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: svc.player.loading,
                builder: (_, loading, _) => Text(loading ? svc.s['buffering'] : '-${fmtClock(len - at)}', style: ts),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}

String fmtClock(Duration d) => fmtDuration(d.isNegative ? Duration.zero : d);
