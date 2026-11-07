// Now Playing, over the whole window (ui_nowplaying.go nowPlayingLayer).
//
// It grows out of the player: a card that takes the screen, clipped from the
// mini player (phone) or the bar's cover (wider) to the full window on a
// 440 ms spring, while the cover flies from the player's to its place and
// the rest rises in one after another (npRise). Pulled down it follows the
// finger, smaller and rounder the farther it goes, and let go far or fast
// enough it falls back into the player; otherwise it springs back. The mini
// player can be dragged up to pull it out the same way.
//
// For 60 fps: the view is built once per change, not per frame; the frames
// only move a clip, a transform and opacities. The artwork's backdrop is a
// gradient of its tint plus the cover shrunk to 48 pixels, both inside a
// RepaintBoundary: nothing is blurred per frame.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/lyrics/lyrics_view.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'comments_view.dart';
import 'controls.dart';
import 'now_playing_controller.dart';
import 'queue_view.dart';

class NowPlayingLayer extends StatefulWidget {
  const NowPlayingLayer({super.key, required this.wide});
  final bool wide;

  @override
  State<NowPlayingLayer> createState() => _NowPlayingLayerState();
}

class _NowPlayingLayerState extends State<NowPlayingLayer> with TickerProviderStateMixin {
  late final AnimationController _t = AnimationController.unbounded(vsync: this);
  late final AnimationController _pull = AnimationController.unbounded(vsync: this);
  final _coverKey = GlobalKey(debugLabel: 'np-cover');
  final _layerKey = GlobalKey(debugLabel: 'np-layer');
  double _drag = 0; // how far it is pulled down, before rubber-banding

  @override
  void initState() {
    super.initState();
    nowPlaying.addListener(_onController);
    nowPlaying.onDragUpdate = _miniDrag;
    nowPlaying.onDragEnd = _miniDragEnd;
    _t.addListener(() => nowPlaying.progress.value = _t.value.clamp(0.0, 1.0));
    _t.addStatusListener((_) => setState(() {}));
  }

  @override
  void dispose() {
    nowPlaying.removeListener(_onController);
    nowPlaying.onDragUpdate = null;
    nowPlaying.onDragEnd = null;
    _t.dispose();
    _pull.dispose();
    super.dispose();
  }

  bool get _still => MediaQuery.of(context).disableAnimations;

  void _animate(double to, [double velocity = 0]) {
    if (_still) {
      _t.animateTo(to, duration: MgMotion.npFade).then((_) {
        if (mounted) _t.value = to;
      });
      return;
    }
    // The spring stops within its tolerance of the target: land on it, so the
    // view knows it is all the way open (or closed).
    _t.animateWith(SpringSimulation(MgMotion.npSpring, _t.value, to, velocity, tolerance: const Tolerance(distance: 0.001, velocity: 0.01))).then((_) {
      if (mounted) _t.value = to;
    });
  }

  void _onController() {
    final open = nowPlaying.isOpen && svc.player.current.value != null;
    setState(() {});
    if (open && _t.value < 1) {
      // Its first frame lays it out, for the cover to know where it flies to.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && nowPlaying.isOpen) _animate(1, _t.velocity);
      });
    } else if (!open && _t.value > 0) {
      _animate(0, _t.velocity);
    }
  }

  double get _h => MediaQuery.sizeOf(context).height;

  // ---- pulled from the mini player
  void _miniDrag(double dy) {
    if (svc.player.current.value == null) return;
    _t.stop();
    if (!nowPlaying.isOpen && _t.value == 0) setState(() {}); // build it, to lay it out
    _t.value = (_t.value - dy / (_h * 0.75)).clamp(0.0, 1.0);
  }

  void _miniDragEnd(double vy) {
    final v = -vy / (_h * 0.75);
    if (vy < -400 || (_t.value > 0.35 && vy < 400)) {
      nowPlaying.markOpen();
      _animate(1, v);
    } else {
      nowPlaying.close();
      _animate(0, v);
    }
  }

  // ---- pulled down on Now Playing
  void _dragStart(DragStartDetails _) {
    _drag = _pull.value;
    _pull.stop();
  }

  void _dragUpdate(DragUpdateDetails d) {
    _drag += d.delta.dy;
    // Pulled up, it gives less and less (MyGo: Rubberband(pull, 0, h, h)).
    _pull.value = _drag >= 0 ? math.min(_drag, _h) : rubberband(_drag, _h);
  }

  void _dragEnd(DragEndDetails d) {
    final vy = d.velocity.pixelsPerSecond.dy;
    final spring = MgMotion.npSpring;
    if (_drag > _h * 0.2 || (_drag > 24 && vy > 700)) {
      // Let go far enough, or thrown: it falls the rest of the way as fast
      // as it was thrown.
      nowPlaying.close();
      _animate(0, -math.max(vy, 0) / _h);
    }
    _pull.animateWith(SpringSimulation(spring, _pull.value, 0, 0));
    _drag = 0;
  }

  Rect? _rectOf(GlobalKey k) {
    final ro = k.currentContext?.findRenderObject() as RenderBox?;
    final layer = _layerKey.currentContext?.findRenderObject() as RenderBox?;
    if (ro == null || !ro.hasSize || !ro.attached || layer == null) return null;
    return ro.localToGlobal(Offset.zero, ancestor: layer) & ro.size;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Track?>(
      valueListenable: svc.player.current,
      builder: (context, track, _) {
        final visible = track != null && (nowPlaying.isOpen || _t.value > 0 || _t.isAnimating);
        if (!visible) {
          // Closed: nothing to paint or touch.
          return const SizedBox.shrink();
        }
        final view = RepaintBoundary(
          child: _NowPlayingView(track: track, wide: widget.wide, coverKey: _coverKey, t: _t),
        );
        return LayoutBuilder(
          key: _layerKey,
          builder: (context, c) {
            final full = Offset.zero & c.biggest;
            return AnimatedBuilder(
              animation: Listenable.merge([_t, _pull]),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _dragStart,
                onVerticalDragUpdate: _dragUpdate,
                onVerticalDragEnd: _dragEnd,
                child: view,
              ),
              builder: (context, child) {
                final t = _t.value.clamp(0.0, 1.0);
                final k = 1 - t;
                final shift = _pull.value;
                final pulled = (shift / c.maxHeight).clamp(0.0, 1.0);
                final from = _rectOf(nowPlaying.fromBarKey) ?? Rect.fromLTWH(8, c.maxHeight - 140, c.maxWidth - 16, 60);
                final fromRadius = widget.wide ? MgRadius.barCover : 14.0;
                final clip = Rect.lerp(full, from, k)!;
                final radius = fromRadius * k + 28 * (shift / 120).clamp(0.0, 1.0);
                Widget card = _still
                    ? Opacity(opacity: t, child: child)
                    : ClipRRect(
                        clipper: _RectClipper(clip, radius),
                        child: child,
                      );
                if (shift != 0) {
                  final s = 1 - 0.12 * pulled;
                  card = Transform(
                    alignment: Alignment.topCenter,
                    transform: Matrix4.identity()
                      ..translateByDouble(0, shift, 0, 1)
                      ..scaleByDouble(s, s, 1, 1),
                    child: card,
                  );
                }
                // The cover flying from the player's to its place.
                final coverTo = _rectOf(_coverKey);
                final coverFrom = _rectOf(nowPlaying.fromCoverKey);
                final flying = !_still && t < 1 && t > 0 && coverTo != null && coverFrom != null;
                final layers = <Widget>[
                  Positioned.fill(child: IgnorePointer(ignoring: !nowPlaying.isOpen, child: card)),
                  if (flying)
                    Positioned.fromRect(
                      rect: Rect.lerp(coverFrom, coverTo, t)!.shift(Offset(0, shift)),
                      child: IgnorePointer(child: CoverArt(track.album.imageUrl, radius: lerpD(MgRadius.barCover, 16, t))),
                    ),
                ];
                final stack = Stack(children: layers);
                // Status and navigation bar icons over the artwork's backdrop.
                if (t > 0.5) {
                  final tint = ArtTint.cached(track.album.imageUrl);
                  final top = tint == null ? npBase : backdropColors(tint).$1;
                  final light = top.computeLuminance() > 0.5;
                  return AnnotatedRegion<SystemUiOverlayStyle>(value: mgOverlay(light), child: stack);
                }
                return stack;
              },
            );
          },
        );
      },
    );
  }
}

class _RectClipper extends CustomClipper<RRect> {
  _RectClipper(this.rect, this.radius);
  final Rect rect;
  final double radius;
  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(rect, Radius.circular(radius));
  @override
  bool shouldReclip(_RectClipper old) => old.rect != rect || old.radius != radius;
}

/// npRise: the nth of the things that fade in and lift into place once the
/// cover is on its way, one after another; the other way as it closes.
class _Rise extends StatelessWidget {
  const _Rise({required this.t, required this.n, required this.child});
  final Animation<double> t;
  final int n;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) {
        final v = t.value.clamp(0.0, 1.0);
        if (v >= 1) return child!;
        final from = 0.3 + 0.07 * n;
        final k = smoothstep(from, from + 0.4, v);
        return Opacity(opacity: k, child: Transform.translate(offset: Offset(0, 24 * (1 - k)), child: child));
      },
    );
  }
}

/// The artwork's colors behind Now Playing (backdrop.go drawBackdrop): a deep
/// gradient of its tint, lighter at the top, the cover itself faintly through
/// it, and a shade toward the foot. Another song's fades in over 700 ms.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ArtTintBuilder(
      url: url,
      builder: (context, tint) {
        final (top, foot) = tint == null ? (const Color(0xFF2A2A30), const Color(0xFF17171B)) : backdropColors(tint);
        return AnimatedSwitcher(
          duration: MgMotion.backdropFade,
          switchInCurve: Curves.easeOutCubic,
          child: RepaintBoundary(
            key: ValueKey('$url/${tint?.toARGB32()}'),
            child: Stack(fit: StackFit.expand, children: [
              DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, foot]))),
              if (url.isNotEmpty)
                Opacity(
                  opacity: 0.1,
                  child: Image(image: ResizeImage(NetworkImage(url), width: 48, height: 48), fit: BoxFit.cover, filterQuality: FilterQuality.medium, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x2E000000)], stops: [0.55, 1]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _NowPlayingView extends StatelessWidget {
  const _NowPlayingView({required this.track, required this.wide, required this.coverKey, required this.t});
  final Track track;
  final bool wide;
  final GlobalKey coverKey;
  final Animation<double> t;

  @override
  Widget build(BuildContext context) {
    svc.likes.refresh(track.source, [track]);
    return ArtTintBuilder(
      url: track.album.imageUrl,
      builder: (context, tint) {
        // Controls lit in the artwork's color, lightened (accent = tint mixed
        // with 45% white).
        final accent = tint == null ? Colors.white : Color.lerp(tint, Colors.white, 0.45)!;
        final pal = MgPalette.darkPalette.copyWith(accent: accent);
        return Theme(
          data: mgTheme(pal),
          child: ListenableBuilder(
            listenable: nowPlaying,
            builder: (context, _) => Stack(fit: StackFit.expand, children: [
              AnimatedBuilder(
                animation: t,
                builder: (context, child) {
                  final v = t.value.clamp(0.0, 1.0);
                  return ColoredBox(
                    color: npBase.withValues(alpha: smoothstep(0, 0.35, v)),
                    child: Opacity(opacity: smoothstep(0.05, 0.55, v), child: child),
                  );
                },
                child: _Backdrop(url: track.album.imageUrl),
              ),
              DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: wide ? _wide(context) : _compact(context),
              ),
            ]),
          ),
        );
      },
    );
  }

  List<(NpPane, String, MgIconData)> _tabs() {
    final s = svc.s;
    return [
      (NpPane.lyrics, s['lyrics'], MgIcons.lyrics),
      (NpPane.queue, s['upNext'], MgIcons.queue),
      if (svc.music.can(track.source, 'comments')) (NpPane.comments, s['comments'], MgIcons.comment),
    ];
  }

  Widget _paneTabs({required bool allowCover}) {
    return Wrap(spacing: 6, children: [
      for (final (pane, label, _) in _tabs())
        MgChip(
          label: label,
          onDark: true,
          selected: nowPlaying.pane == pane || (!allowCover && nowPlaying.pane == NpPane.cover && pane == NpPane.lyrics),
          onTap: () => allowCover ? nowPlaying.choose(pane) : nowPlaying.show(pane),
        ),
    ]);
  }

  Widget _pane(NpPane pane, {required bool compact}) {
    return switch (pane) {
      NpPane.queue => const QueueView(key: ValueKey('queue')),
      NpPane.comments => CommentsView(key: ValueKey('comments/${track.key}'), track: track),
      _ => LyricsView(key: const ValueKey('lyrics'), track: track, compact: compact),
    };
  }

  Widget _cover(double size) {
    return ValueListenableBuilder<bool>(
      valueListenable: svc.player.playingN,
      builder: (context, playing, child) => AnimatedScale(
        // The cover breathes: smaller while paused (ui_cover.go: 0.88).
        scale: playing ? 1 : 0.88,
        duration: const Duration(milliseconds: 600),
        curve: SpringCurve(SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 600), bounce: 0.25)),
        child: child,
      ),
      child: AnimatedBuilder(
        animation: t,
        builder: (context, child) => Opacity(opacity: t.value >= 1 || MediaQuery.of(context).disableAnimations ? 1 : 0, child: child),
        child: Container(
          key: coverKey,
          width: size,
          height: size,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.55), blurRadius: 60, spreadRadius: -12, offset: Offset(0, 30))]),
          child: CoverArt(track.album.imageUrl, size: size, radius: 16, placeholderColor: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
    );
  }

  Widget _meta({required bool big}) {
    final white = Colors.white;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: (big ? MgType.npTitle : MgType.npTitle.copyWith(fontSize: 17)).copyWith(color: white)),
          const SizedBox(height: 4),
          Text(track.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: (big ? MgType.npArtist : MgType.npArtist.copyWith(fontSize: 14)).copyWith(color: white.withValues(alpha: 0.6))),
        ]),
      ),
      LikeButton(track: track, size: big ? 22 : 20, color: white.withValues(alpha: 0.7)),
      MoreButton(track: track, size: big ? 22 : 20, color: white.withValues(alpha: 0.7)),
    ]);
  }

  Widget _compact(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context);
    final white = Colors.white;
    final pane = nowPlaying.pane;
    return Padding(
      padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom + 12, left: pad.left, right: pad.right),
      child: Column(children: [
        _Rise(
          t: t,
          n: 0,
          child: SizedBox(
            height: 52,
            child: Row(children: [
              const SizedBox(width: 4),
              MgIconButton(MgIcons.down, size: 24, color: white.withValues(alpha: 0.7), tooltip: svc.s['close'], onTap: nowPlaying.close),
              const Spacer(),
              _paneTabs(allowCover: true),
              const SizedBox(width: 12),
            ]),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: MgMotion.ease,
            switchOutCurve: MgMotion.ease.flipped,
            transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child)),
            child: pane == NpPane.cover
                ? LayoutBuilder(
                    key: const ValueKey('cover'),
                    builder: (context, c) {
                      final size = math.max(120.0, math.min(c.maxWidth - 56, c.maxHeight - 24));
                      return Center(child: GestureDetector(onTap: () => nowPlaying.choose(NpPane.lyrics), child: _cover(size)));
                    },
                  )
                : _Rise(t: t, n: 2, child: _pane(pane, compact: true)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 20, 6),
          child: _Rise(
            t: t,
            n: 1,
            child: pane == NpPane.cover
                ? _meta(big: true)
                : Row(children: [
                    GestureDetector(onTap: () => nowPlaying.choose(NpPane.cover), child: CoverArt(track.album.imageUrl, size: 48, radius: MgRadius.barCover)),
                    const SizedBox(width: 12),
                    Expanded(child: _meta(big: false)),
                  ]),
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: _Rise(t: t, n: 2, child: ProgressBlock(track: track))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: _Rise(t: t, n: 3, child: Transport(size: 28, color: white, dim: white.withValues(alpha: 0.45), on: Theme.of(context).extension<MgPalette>()!.accent, spread: true)),
        ),
      ]),
    );
  }

  Widget _wide(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context);
    final white = Colors.white;
    final size = MediaQuery.sizeOf(context);
    final padX = math.max(56.0, (size.width - 1280) / 2) + math.max(pad.left, pad.right);
    final cover = math.min(math.min(size.width * 0.36, 440.0), size.height - pad.top - pad.bottom - 330).clamp(160.0, 440.0);
    final side = math.max(cover, 300.0);
    final pane = nowPlaying.pane == NpPane.cover ? NpPane.lyrics : nowPlaying.pane;
    return Padding(
      padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
      child: Column(children: [
        _Rise(
          t: t,
          n: 0,
          child: SizedBox(
            height: 52,
            child: Center(child: MgIconButton(MgIcons.down, size: 22, color: white.withValues(alpha: 0.7), tooltip: svc.s['close'], onTap: nowPlaying.close)),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(padX, 0, padX, 36),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: side,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _cover(cover),
                  const SizedBox(height: 32),
                  _Rise(t: t, n: 1, child: _meta(big: true)),
                  const SizedBox(height: 14),
                  _Rise(t: t, n: 2, child: ProgressBlock(track: track)),
                  const SizedBox(height: 10),
                  _Rise(t: t, n: 3, child: Center(child: Transport(size: 28, color: white, dim: white.withValues(alpha: 0.45), on: Theme.of(context).extension<MgPalette>()!.accent))),
                ]),
              ),
              const SizedBox(width: 64),
              Expanded(
                child: _Rise(
                  t: t,
                  n: 2,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _paneTabs(allowCover: false),
                    const SizedBox(height: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: MgMotion.ease,
                        child: _pane(pane, compact: false),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
