// Headings, list rows, empty states, spinners and the now-playing bars.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mygo_mobile/ui/theme/mg_theme.dart';
import 'buttons.dart';

/// Bars that dance in the row of what plays (ui_pages.go nowPlayingBars):
/// four rounded bars, 16 by 14, in the accent. There are no audio levels on
/// the phone, so they move on a gentle sum of sines while playing and rest
/// low when paused.
class NowPlayingBars extends StatefulWidget {
  const NowPlayingBars({super.key, required this.playing, this.color});
  final bool playing;
  final Color? color;

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((e) => setState(() => _t = e.inMicroseconds / 1e6));
  double _t = 0;

  @override
  void initState() {
    super.initState();
    if (widget.playing && !_disabled) _ticker.start();
  }

  bool get _disabled => WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  @override
  void didUpdateWidget(NowPlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_ticker.isActive && !_disabled) _ticker.start();
    if (!widget.playing && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(16, 14), painter: _BarsPainter(widget.playing ? _t : -1, widget.color ?? context.mg.accent));
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 4;
    final gap = size.width / n * 0.38;
    final w = (size.width - gap * (n - 1)) / n;
    final paint = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      var v = 0.18;
      if (t >= 0) {
        v = 0.25 + 0.75 * (0.5 + 0.25 * math.sin(t * (5.1 + i * 1.7) + i * 1.3) + 0.25 * math.sin(t * (8.3 - i) + i * 2.1)).abs();
      }
      final h = math.max(2.5, size.height * v.clamp(0.0, 1.0));
      final x = i * (w + gap);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, w, h), Radius.circular(w / 2)), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter o) => o.t != t || o.color != color;
}

/// The loading mark: a short arc turning, in the muted color.
class MgSpinner extends StatefulWidget {
  const MgSpinner({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  State<MgSpinner> createState() => _MgSpinnerState();
}

class _MgSpinnerState extends State<MgSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.mg.muted;
    return RotationTransition(
      turns: _c,
      child: CustomPaint(size: Size.square(widget.size), painter: _ArcPainter(color)),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    canvas.drawArc(r, -math.pi / 2, math.pi * 0.6, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_ArcPainter o) => o.color != color;
}

/// A page's heading (ui_pages.go heading): an optional line above it, 12/600
/// muted with +0.4 tracking, and the title 30/700 (26 on a phone).
class MgHeading extends StatelessWidget {
  const MgHeading(this.title, {super.key, this.eyebrow = '', this.compact = false, this.trailing});
  final String title, eyebrow;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (eyebrow.isNotEmpty) ...[Text(eyebrow.toUpperCase(), style: MgType.eyebrow.copyWith(color: p.muted)), const SizedBox(height: 4)],
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: (compact ? MgType.headingCompact : MgType.heading).copyWith(color: p.text)),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// A section's title (ui_pages.go section): 19/700, -0.3, 34 above and 14
/// below; "more" at its end when there is more to see.
class MgSectionTitle extends StatelessWidget {
  const MgSectionTitle(this.title, {super.key, this.onMore, this.top = 26, this.moreLabel = 'See All'});
  final String title, moreLabel;
  final VoidCallback? onMore;
  final double top;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 12),
      child: Row(children: [
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.section.copyWith(color: p.text))),
        if (onMore != null)
          Pressable(
            onTap: onMore,
            pressedColor: p.press,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(moreLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
              MgIcon(MgIcons.forward, size: 14, color: p.muted),
            ]),
          ),
      ]),
    );
  }
}


/// A centered message with an icon in a soft square (ui_pages.go emptyHome).
class MgEmpty extends StatelessWidget {
  const MgEmpty({super.key, required this.icon, required this.title, this.message = '', this.actions = const []});
  final MgIconData icon;
  final String title, message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: p.hover, borderRadius: BorderRadius.circular(20)),
          child: Center(child: MgIcon(icon, size: 32, color: p.muted)),
        ),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: p.text)),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.45, color: p.muted)),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: actions),
        ],
      ]),
    );
  }
}

/// A row of a settings-like list: icon, label, optional trailing.
class MgListRow extends StatelessWidget {
  const MgListRow({super.key, this.icon, required this.label, this.sub = '', this.onTap, this.trailing, this.selected = false, this.leading, this.danger = false});
  final MgIconData? icon;
  final Widget? leading;
  final String label, sub;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool selected, danger;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final fg = danger ? p.accent : p.text;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      color: selected ? p.press : Colors.transparent,
      pressedColor: p.press,
      borderRadius: BorderRadius.circular(MgRadius.row),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 30),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 14)] else if (icon != null) ...[
            MgIcon(icon!, size: 19, color: selected ? p.accent : (danger ? p.accent : p.text)),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: fg)),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(sub, maxLines: 3, overflow: TextOverflow.ellipsis, style: MgType.rowSub.copyWith(color: p.muted)),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      ),
    );
  }
}
