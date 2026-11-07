// Synced lyrics as MyGo shows them (ui_nowplaying.go lyricsPane/timedLines):
// big bold lines, the one sung lit and full size, the others at 28% and 94%;
// it glides to 30% of the way down on a critically damped spring (ω = 10);
// a line sung word by word lights up word by word; a tap seeks there.

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:mygo_mobile/app/platform/platform.dart' show debugExpose;
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'lyrics_controller.dart';

final lyricsCache = LyricsCache((t) => svc.music.lyrics(t));

class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.track, this.compact = true});
  final Track track;
  final bool compact;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> with TickerProviderStateMixin {
  late Future<List<LyricLine>> _future;
  final _scroll = ScrollController();
  late final AnimationController _glide = AnimationController.unbounded(vsync: this)..addListener(_onGlide);
  List<LyricLine> _lines = const [];
  List<GlobalKey> _keys = const [];
  final _contentKey = GlobalKey();
  int _current = -2;

  // The line changes on the frame its time comes: checked every frame while
  // playing, against the media clock (Player.positionNow), not only when a
  // position report arrives (a few times a second, later on the web).
  late final Ticker _frames = createTicker((_) => _onPosition());

  void _syncFrames() {
    final on = svc.player.playingN.value && !svc.player.legacyClock;
    if (on && !_frames.isActive) _frames.start();
    if (!on && _frames.isActive) _frames.stop();
  }

  @override
  void initState() {
    super.initState();
    _load();
    svc.player.positionN.addListener(_onPosition);
    svc.player.playingN.addListener(_syncFrames);
    _syncFrames();
  }

  void _load() {
    _future = lyricsCache.of(widget.track).then((l) {
      _lines = l;
      _keys = [for (var i = 0; i < l.length; i++) GlobalKey()];
      _current = -2;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onPosition());
      return l;
    });
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.track.key != widget.track.key) {
      _lines = const [];
      _load();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    svc.player.positionN.removeListener(_onPosition);
    svc.player.playingN.removeListener(_syncFrames);
    _frames.dispose();
    _glide.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPosition() {
    if (_lines.isEmpty || !mounted) return;
    final ms = svc.player.positionNow.inMilliseconds;
    final i = lyricIndex(_lines, ms);
    if (i == _current) return;
    debugExpose('lyric', {'index': i, 'start': i >= 0 ? _lines[i].start : -1, 'pos': ms, 'at': DateTime.now().millisecondsSinceEpoch});
    setState(() => _current = i);
    WidgetsBinding.instance.addPostFrameCallback((_) => _glideTo(i));
  }

  /// Brings line [i] to 30% of the way down.
  void _glideTo(int i) {
    if (!mounted || !_scroll.hasClients || i < 0 || i >= _keys.length) return;
    final line = _keys[i].currentContext?.findRenderObject() as RenderBox?;
    final content = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (line == null || content == null) return;
    final y = line.localToGlobal(Offset.zero, ancestor: content).dy;
    final pos = _scroll.position;
    final target = (y - pos.viewportDimension * MgMotion.lyricAnchor).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (MediaQuery.of(context).disableAnimations) {
      _scroll.jumpTo(target);
      return;
    }
    final v = _glide.isAnimating ? _glide.velocity : 0.0;
    _glide.value = pos.pixels;
    _glide.animateWith(SpringSimulation(MgMotion.lyricGlide, pos.pixels, target, v, tolerance: const Tolerance(distance: 0.5, velocity: 20)));
  }

  void _onGlide() {
    if (_scroll.hasClients) _scroll.jumpTo(_glide.value.clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.compact ? MgType.lyricCompact : MgType.lyric;
    return FutureBuilder<List<LyricLine>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return SkeletonLyrics(compact: widget.compact);
        if (snap.hasError) {
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(svc.describe(snap.error!), textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6)))));
        }
        final lines = snap.data ?? const [];
        if (lines.isEmpty) {
          return Center(child: Text(svc.s['noLyrics'], style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.4))));
        }
        return LayoutBuilder(builder: (context, c) {
          return NotificationListener<ScrollStartNotification>(
            onNotification: (n) {
              // The listener took over: the glide stops where it shows.
              if (n.dragDetails != null) _glide.stop();
              return false;
            },
            child: ShaderMask(
              // Lines fade out at the top and the foot of the pane.
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.08, 0.86, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(widget.compact ? 12 : 0, c.maxHeight * 0.3, 8, c.maxHeight * 0.6),
                child: Column(
                  key: _contentKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _Line(
                          key: _keys[i],
                          line: lines[i],
                          on: i == _current,
                          style: style,
                          onTap: () => svc.player.seek(Duration(milliseconds: lines[i].start)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.line, required this.on, required this.style, required this.onTap});
  final LyricLine line;
  final bool on;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = on && line.words.isNotEmpty ? _Words(line: line, style: style) : Text(line.text, style: style.copyWith(color: Colors.white));
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      color: Colors.transparent,
      pressedColor: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(MgRadius.queueRow),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: AnimatedScale(
        scale: on ? 1 : 0.94,
        alignment: Alignment.centerLeft,
        duration: const Duration(milliseconds: 600),
        curve: SpringCurve(MgMotion.lineSpring),
        child: AnimatedOpacity(
          opacity: on ? 1 : 0.28,
          duration: MgMotion.lineFade,
          curve: Curves.easeOut,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            text,
            if (line.translation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(line.translation, style: MgType.lyricTranslation.copyWith(color: Colors.white.withValues(alpha: 0.7), fontSize: style.fontSize! < 28 ? 15 : 17)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// The line sung, word by word: each word from 38% to full as it is sung,
/// redrawn 25 times a second while playing (MyGo: every 40 ms).
class _Words extends StatefulWidget {
  const _Words({required this.line, required this.style});
  final LyricLine line;
  final TextStyle style;

  @override
  State<_Words> createState() => _WordsState();
}

class _WordsState extends State<_Words> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  void _tick(Duration e) {
    if (e - _last >= const Duration(milliseconds: 40)) {
      _last = e;
      setState(() {});
    }
  }

  void _sync() {
    final on = svc.player.playingN.value;
    if (on && !_ticker.isActive) _ticker.start();
    if (!on && _ticker.isActive) _ticker.stop();
  }

  @override
  void initState() {
    super.initState();
    svc.player.playingN.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    svc.player.playingN.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = svc.player.positionNow.inMilliseconds;
    return Text.rich(TextSpan(style: widget.style, children: [
      for (final w in widget.line.words) TextSpan(text: w.text, style: TextStyle(color: Colors.white.withValues(alpha: 0.38 + 0.62 * wordLit(w, ms)))),
    ]));
  }
}
