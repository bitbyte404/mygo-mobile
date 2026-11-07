// Skeleton screens: the shapes of what is loading, in the palette's placeholder
// fill, with a slow light sweep across them (still when the system asks for
// reduced motion). Pages and sections show these while they load; a spinner is
// kept only for an action in place (a button, the mini player buffering, a
// dialog). See docs/DESIGN.md "Loading".
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout/page.dart';
import '../theme/mg_theme.dart';

/// The fill and sweep colors of a skeleton on [p] (or on Now Playing's dark
/// backdrop when [onDark]).
({Color base, Color highlight}) mgSkeletonColors(MgPalette p, {bool onDark = false}) {
  if (onDark) return (base: Colors.white.withValues(alpha: 0.08), highlight: Colors.white.withValues(alpha: 0.17));
  return p.dark
      ? (base: Colors.white.withValues(alpha: 0.07), highlight: Colors.white.withValues(alpha: 0.13))
      : (base: Colors.black.withValues(alpha: 0.055), highlight: Colors.black.withValues(alpha: 0.02));
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required super.child});
  @override
  bool updateShouldNotify(_ShimmerScope old) => false;
}

/// Sweeps a soft band of light across every [MgBone] below it, all in one
/// pass so the band crosses the page as one. Put one at the root of a
/// skeleton screen.
class MgShimmer extends StatefulWidget {
  const MgShimmer({super.key, required this.child, this.onDark = false});
  final Widget child;
  final bool onDark;

  /// How long one sweep takes.
  static const period = Duration(milliseconds: 1600);

  @override
  State<MgShimmer> createState() => _MgShimmerState();
}

class _MgShimmerState extends State<MgShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: MgShimmer.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = mgSkeletonColors(context.mg, onDark: widget.onDark);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final child = _ShimmerScope(child: widget.child);
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          child: child,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              if (still) return LinearGradient(colors: [colors.base, colors.base]).createShader(bounds);
              // A band about 40% of the width wide, entering from the left
              // edge and leaving past the right, tilted a little.
              final t = Curves.easeInOut.transform(_c.value);
              final band = math.max(bounds.width * 0.4, 160.0);
              final x = -band + (bounds.width + 2 * band) * t;
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [colors.base, colors.highlight, colors.base],
                stops: const [0.0, 0.5, 1.0],
                transform: const GradientRotation(0.18),
              ).createShader(Rect.fromLTWH(x, bounds.top, band, bounds.height));
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One placeholder shape. Under an [MgShimmer] it is a mask the sweep paints
/// through; on its own it paints the plain placeholder fill.
class MgBone extends StatelessWidget {
  const MgBone({super.key, this.width, this.height = 12, this.radius = 6, this.circle = false, this.onDark = false});
  const MgBone.square(double size, {super.key, this.radius = 6, this.onDark = false})
      : width = size,
        height = size,
        circle = false;
  const MgBone.circle(double size, {super.key, this.onDark = false})
      : width = size,
        height = size,
        radius = 0,
        circle = true;

  final double? width;
  final double height, radius;
  final bool circle, onDark;

  @override
  Widget build(BuildContext context) {
    final masked = context.getInheritedWidgetOfExactType<_ShimmerScope>() != null;
    final color = masked ? Colors.white : mgSkeletonColors(context.mg, onDark: onDark).base;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// A text line's bone: [fraction] of the width available.
class MgBoneLine extends StatelessWidget {
  const MgBoneLine({super.key, this.fraction = 0.6, this.height = 12, this.maxWidth = double.infinity});
  final double fraction, height, maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final avail = c.maxWidth.isFinite ? c.maxWidth : 240.0;
          return Align(alignment: Alignment.centerLeft, child: MgBone(width: math.min(avail * fraction, maxWidth), height: height, radius: height / 2));
        },
      );
}

// Widths that vary row to row, so a list of bones doesn't read as a table.
const _titleW = [0.56, 0.42, 0.68, 0.48, 0.62, 0.38, 0.52, 0.6];
const _subW = [0.34, 0.26, 0.4, 0.3, 0.22, 0.36, 0.28, 0.32];

/// A song row's shape (TrackTile): cover, title, artists, the "…" at the end.
class SkeletonSongRow extends StatelessWidget {
  const SkeletonSongRow({super.key, this.index = 0, this.showCover = true, this.compact = true});
  final int index;
  final bool showCover, compact;

  @override
  Widget build(BuildContext context) {
    final i = index % _titleW.length;
    return SizedBox(
      height: compact ? MgSize.rowHeightCompact : MgSize.rowHeight + 4,
      child: Padding(
        padding: EdgeInsets.only(left: compact ? 8 : 12, right: compact ? 14 : 16),
        child: Row(children: [
          showCover ? const MgBone.square(44, radius: MgRadius.rowCover) : const SizedBox(width: 28, child: Center(child: MgBone(width: 12, height: 10))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgBoneLine(fraction: _titleW[i], height: compact ? 13 : 12),
              const SizedBox(height: 8),
              MgBoneLine(fraction: _subW[i], height: 10),
            ]),
          ),
          if (!compact) const Padding(padding: EdgeInsets.only(left: 12, right: 18), child: MgBone(width: 30, height: 10)),
          const SizedBox(width: 12),
          const MgBone(width: 18, height: 4, radius: 2),
        ]),
      ),
    );
  }
}

/// A card's shape (MediaCard): the square cover and two lines under it.
class SkeletonCardTile extends StatelessWidget {
  const SkeletonCardTile({super.key, required this.width, this.round = false, this.index = 0});
  final double width;
  final bool round;
  final int index;

  @override
  Widget build(BuildContext context) {
    final i = index % _titleW.length;
    return SizedBox(
      width: width,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: round ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
        round ? MgBone.circle(width) : MgBone.square(width, radius: MgRadius.card),
        const SizedBox(height: 12),
        MgBone(width: width * (0.55 + _titleW[i] * 0.4), height: 11),
        if (!round) ...[const SizedBox(height: 7), MgBone(width: width * (0.3 + _subW[i]), height: 9)],
      ]),
    );
  }
}

/// A section title's shape (MgSectionTitle): the title, and "See all" when
/// [more].
class SkeletonSectionHeader extends StatelessWidget {
  const SkeletonSectionHeader({super.key, this.first = false, this.more = true, this.width = 132});
  final bool first, more;
  final double width;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: first ? 8 : 30, bottom: 14),
        child: Row(children: [
          MgBone(width: width, height: 17, radius: 6),
          const Spacer(),
          if (more) const MgBone(width: 44, height: 11),
        ]),
      );
}

/// A page heading's shape (MgHeading): the date line and the big title.
class SkeletonHeading extends StatelessWidget {
  const SkeletonHeading({super.key, this.compact = true});
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MgBone(width: 128, height: 10),
          const SizedBox(height: 10),
          MgBone(width: compact ? 210 : 280, height: compact ? 26 : 30, radius: 8),
        ]),
      );
}

/// A playlist, album or artist header's shape (PageHeader): the big cover and
/// the title lines, stacked on a phone, side by side on a wider screen.
class SkeletonCollectionHeader extends StatelessWidget {
  const SkeletonCollectionHeader({super.key, this.round = false, this.buttons = true});
  final bool round, buttons;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final w = MediaQuery.sizeOf(context).width;
    final size = compact ? math.min(w * 0.5, 200.0) : MgSize.headerCover;
    final art = round ? MgBone.circle(size) : MgBone.square(size, radius: MgRadius.header);
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const MgBone(width: 64, height: 10),
      const SizedBox(height: 12),
      MgBone(width: compact ? 220 : 300, height: compact ? 24 : 30, radius: 8),
      const SizedBox(height: 12),
      const MgBone(width: 150, height: 11),
      const SizedBox(height: 8),
      const MgBone(width: 110, height: 11),
      if (buttons) ...[
        const SizedBox(height: 18),
        const Row(children: [MgBone(width: 96, height: 36, radius: 999), SizedBox(width: 10), MgBone(width: 96, height: 36, radius: 999)]),
      ],
    ]);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [art, const SizedBox(height: 20), text])
          : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [art, const SizedBox(width: 28), Expanded(child: text)]),
    );
  }
}

/// Lyrics' shape: big lines of varied width, on Now Playing's backdrop.
class SkeletonLyrics extends StatelessWidget {
  const SkeletonLyrics({super.key, this.compact = true, this.lines = 7});
  final bool compact;
  final int lines;

  @override
  Widget build(BuildContext context) {
    const widths = [0.72, 0.5, 0.84, 0.6, 0.76, 0.46, 0.66, 0.8];
    final h = compact ? 22.0 : 28.0;
    return MgShimmer(
      onDark: true,
      child: LayoutBuilder(builder: (context, c) {
        final body = Padding(
          padding: EdgeInsets.fromLTRB(compact ? 24 : 12, 40, 24, 0),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < lines; i++) Padding(padding: const EdgeInsets.only(bottom: 22), child: MgBoneLine(fraction: widths[i % widths.length], height: h)),
          ]),
        );
        if (!c.hasBoundedHeight) return body;
        // As many lines as the room has; the rest are cut, not overflowing.
        return ClipRect(child: OverflowBox(alignment: Alignment.topLeft, minHeight: 0, maxHeight: double.infinity, child: body));
      }),
    );
  }
}

/// A comment's shape: avatar, name, two lines of text.
class SkeletonCommentRow extends StatelessWidget {
  const SkeletonCommentRow({super.key, this.index = 0});
  final int index;

  @override
  Widget build(BuildContext context) {
    final i = index % _titleW.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const MgBone.circle(34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgBoneLine(fraction: 0.22 + _subW[i] * 0.3, height: 10),
            const SizedBox(height: 10),
            const MgBoneLine(fraction: 0.94, height: 11),
            const SizedBox(height: 7),
            MgBoneLine(fraction: _titleW[i], height: 11),
          ]),
        ),
      ]),
    );
  }
}
