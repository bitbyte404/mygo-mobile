// The progress bar (ui_player.go scrubber).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mygo_mobile/ui/theme/mg_theme.dart';

/// How far the track is, seeking where it is dragged or tapped: a 4-point
/// bar that thickens to 6 under the finger and shows a 12-point knob
/// (ui_player.go scrubber), on a 32-point tall touch area.
class Scrubber extends StatefulWidget {
  const Scrubber({super.key, required this.value, required this.max, required this.onSeek, this.track, this.fill, this.height = 28, this.onDrag, this.guardEnd = true});
  /// Not right at the end, which would end the song as it begins to play.
  final bool guardEnd;
  final double value, max; // ms
  final ValueChanged<double> onSeek;
  final ValueChanged<double?>? onDrag; // the value dragged, null when let go
  final Color? track, fill;
  final double height;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> with SingleTickerProviderStateMixin {
  double? _drag;
  late final AnimationController _hot = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));

  @override
  void dispose() {
    _hot.dispose();
    super.dispose();
  }

  double _at(Offset local, double w) => (local.dx / w).clamp(0.0, 1.0) * widget.max;

  void _start(double v) {
    _hot.forward();
    setState(() => _drag = v);
    widget.onDrag?.call(v);
  }

  void _move(double v) {
    setState(() => _drag = v);
    widget.onDrag?.call(v);
  }

  void _end() {
    _hot.reverse();
    final v = _drag;
    setState(() => _drag = null);
    widget.onDrag?.call(null);
    // Not right at the end, which would end the song as it begins to play.
    if (v != null) widget.onSeek(widget.guardEnd ? math.min(v, math.max(0, widget.max - 1000)) : v);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _start(_at(d.localPosition, w)),
        onHorizontalDragUpdate: (d) => _move(_at(d.localPosition, w)),
        onHorizontalDragEnd: (_) => _end(),
        onHorizontalDragCancel: _end,
        onTapDown: (d) => _start(_at(d.localPosition, w)),
        onTapUp: (_) => _end(),
        onTapCancel: () {
          if (_drag != null) _end();
        },
        child: AnimatedBuilder(
          animation: _hot,
          builder: (context, _) => CustomPaint(
            size: Size(w, widget.height),
            painter: _ScrubPainter(
              frac: widget.max <= 0 ? 0 : ((_drag ?? widget.value) / widget.max).clamp(0.0, 1.0),
              hot: Curves.easeOut.transform(_hot.value),
              track: widget.track ?? p.press,
              fill: widget.fill ?? p.text.withValues(alpha: 0.75),
            ),
          ),
        ),
      );
    });
  }
}

class _ScrubPainter extends CustomPainter {
  _ScrubPainter({required this.frac, required this.hot, required this.track, required this.fill});
  final double frac, hot;
  final Color track, fill;

  @override
  void paint(Canvas canvas, Size size) {
    final thick = 4 + 2 * hot;
    final y = (size.height - thick) / 2;
    final r = Radius.circular(thick / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, y, size.width, thick), r), Paint()..color = track);
    final head = size.width * frac;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, y, math.max(thick, head), thick), r), Paint()..color = fill);
    if (hot > 0.01) {
      final k = 12 * hot;
      final c = Offset(head.clamp(k / 2, size.width - k / 2), size.height / 2);
      canvas.drawCircle(c + const Offset(0, 1), k / 2, Paint()
        ..color = const Color.fromRGBO(0, 0, 0, 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
      canvas.drawCircle(c, k / 2, Paint()..color = fill.withValues(alpha: 1));
    }
  }

  @override
  bool shouldRepaint(_ScrubPainter o) => o.frac != frac || o.hot != hot || o.track != track || o.fill != fill;
}
