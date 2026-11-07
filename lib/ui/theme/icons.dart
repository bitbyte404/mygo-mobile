// Icons drawn on a 24-point grid in the color of the text, as MyGo Music
// draws its own (internal/app/icons.go): transport controls filled, the rest a
// 1.75-point stroke. The SVG markup is MyGo's, copied verbatim; the extra ones
// (history, shield, qr, ...) are Lucide icons in the same style.
import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

class MgIconData {
  const MgIconData(this.filled, this.svg, {this.strokeToo = false});
  final bool filled;
  final String svg;
  final bool strokeToo;
}

class MgIcons {
  MgIcons._();
  static const play = MgIconData(true, r'''<path d="M7 4.6v14.8c0 .8.9 1.3 1.6.9l12-7.4c.6-.4.6-1.3 0-1.7l-12-7.4C7.9 3.3 7 3.8 7 4.6z"/>''');
  static const pause = MgIconData(true, r'''<rect x="5.5" y="4" width="4.5" height="16" rx="1.4"/><rect x="14" y="4" width="4.5" height="16" rx="1.4"/>''');
  static const next = MgIconData(true, r'''<path d="M3 5.6v12.8c0 .8.9 1.3 1.6.8l9.4-6.4c.6-.4.6-1.2 0-1.6L4.6 4.8C3.9 4.3 3 4.8 3 5.6z"/><path d="M12 5.6v12.8c0 .8.9 1.3 1.6.8l9.4-6.4c.6-.4.6-1.2 0-1.6l-9.4-6.4c-.7-.5-1.6 0-1.6.8z" transform="translate(-1.5 0)"/>''');
  static const prev = MgIconData(true, r'''<g transform="matrix(-1 0 0 1 24 0)"><path d="M3 5.6v12.8c0 .8.9 1.3 1.6.8l9.4-6.4c.6-.4.6-1.2 0-1.6L4.6 4.8C3.9 4.3 3 4.8 3 5.6z"/><path d="M12 5.6v12.8c0 .8.9 1.3 1.6.8l9.4-6.4c.6-.4.6-1.2 0-1.6l-9.4-6.4c-.7-.5-1.6 0-1.6.8z" transform="translate(-1.5 0)"/></g>''');
  static const shuffle = MgIconData(false, r'''<path d="M2 18h1.4c1.3 0 2.5-.6 3.3-1.7l6.1-8.6c.8-1.1 2-1.7 3.3-1.7H22"/><path d="m18 2 4 4-4 4"/><path d="M2 6h1.9c1.5 0 2.9.9 3.6 2.2"/><path d="M22 18h-5.9c-1.3 0-2.6-.7-3.3-1.8l-.5-.8"/><path d="m18 14 4 4-4 4"/>''');
  static const repeat = MgIconData(false, r'''<path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/>''');
  static const repeat1 = MgIconData(false, r'''<path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/><path d="M11 10h1v4"/>''');
  static const volume = MgIconData(false, r'''<path d="M11 4.7a.7.7 0 0 0-1.2-.5L6.4 7.6A1.4 1.4 0 0 1 5.4 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.4a1.4 1.4 0 0 1 1 .4l3.4 3.4a.7.7 0 0 0 1.2-.5z"/><path d="M16 9a5 5 0 0 1 0 6"/><path d="M19.4 18.4a9 9 0 0 0 0-12.8"/>''');
  static const volumeLow = MgIconData(false, r'''<path d="M11 4.7a.7.7 0 0 0-1.2-.5L6.4 7.6A1.4 1.4 0 0 1 5.4 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.4a1.4 1.4 0 0 1 1 .4l3.4 3.4a.7.7 0 0 0 1.2-.5z"/><path d="M16 9a5 5 0 0 1 0 6"/>''');
  static const mute = MgIconData(false, r'''<path d="M11 4.7a.7.7 0 0 0-1.2-.5L6.4 7.6A1.4 1.4 0 0 1 5.4 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.4a1.4 1.4 0 0 1 1 .4l3.4 3.4a.7.7 0 0 0 1.2-.5z"/><line x1="22" x2="16" y1="9" y2="15"/><line x1="16" x2="22" y1="9" y2="15"/>''');
  static const search = MgIconData(false, r'''<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>''');
  static const home = MgIconData(false, r'''<path d="M12 3 4 9v11a1 1 0 0 0 1 1h4v-6h6v6h4a1 1 0 0 0 1-1V9z"/>''');
  static const calendar = MgIconData(false, r'''<rect x="3" y="4.5" width="18" height="16.5" rx="2.5"/><path d="M8 2.5v4"/><path d="M16 2.5v4"/><path d="M3 10h18"/>''');
  static const album = MgIconData(false, r'''<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3"/>''');
  static const playlist = MgIconData(false, r'''<path d="M3 6h13"/><path d="M3 12h13"/><path d="M3 18h9"/><path d="M21 9v9"/><circle cx="18.5" cy="18" r="2.5"/>''');
  static const star = MgIconData(false, r'''<path d="m12 3 2.7 5.8 6.3.8-4.6 4.3 1.2 6.2L12 17l-5.6 3.1 1.2-6.2L3 9.6l6.3-.8z"/>''');
  static const folder = MgIconData(false, r'''<path d="M3 7a2 2 0 0 1 2-2h4l2 2.5h8a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>''');
  static const charts = MgIconData(false, r'''<path d="M4 20V10"/><path d="M10 20V4"/><path d="M16 20v-7"/><path d="M22 20H2"/>''');
  static const queue = MgIconData(false, r'''<path d="M16 5H3"/><path d="M11 12H3"/><path d="M11 19H3"/><path d="M21 16V5"/><circle cx="18" cy="16" r="3"/>''');
  static const lyrics = MgIconData(false, r'''<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/><path d="M8 9h8"/><path d="M8 13h5"/>''');
  static const down = MgIconData(false, r'''<path d="m6 9 6 6 6-6"/>''');
  static const back = MgIconData(false, r'''<path d="m15 18-6-6 6-6"/>''');
  static const forward = MgIconData(false, r'''<path d="m9 18 6-6-6-6"/>''');
  static const note = MgIconData(false, r'''<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>''');
  static const heart = MgIconData(false, r'''<path d="M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z"/>''');
  static const heartFill = MgIconData(true, r'''<path d="M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4 3 5.5l7 7z"/>''');
  static const user = MgIconData(false, r'''<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>''');
  static const podcast = MgIconData(false, r'''<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M19 10v1a7 7 0 0 1-14 0v-1"/><path d="M12 18v4"/>''');
  static const radio = MgIconData(false, r'''<circle cx="12" cy="12" r="2"/><path d="M16.24 7.76a6 6 0 0 1 0 8.49"/><path d="M7.76 16.24a6 6 0 0 1 0-8.49"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M4.93 19.07a10 10 0 0 1 0-14.14"/>''');
  static const trash = MgIconData(false, r'''<path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>''');
  static const thumb = MgIconData(false, r'''<path d="M7 10v12"/><path d="M15 5.88 14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H4a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h2.76a2 2 0 0 0 1.79-1.11L12 2a3.13 3.13 0 0 1 3 3.88Z"/>''');
  static const comment = MgIconData(false, r'''<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>''');
  static const plus = MgIconData(false, r'''<path d="M12 5v14"/><path d="M5 12h14"/>''');
  static const check = MgIconData(false, r'''<path d="m5 12 4 4L19 6"/>''');
  static const x = MgIconData(false, r'''<path d="M18 6 6 18"/><path d="m6 6 12 12"/>''');
  static const more = MgIconData(true, r'''<circle cx="5" cy="12" r="1.9"/><circle cx="12" cy="12" r="1.9"/><circle cx="19" cy="12" r="1.9"/>''');
  static const upDown = MgIconData(false, r'''<path d="m7 15 5 5 5-5"/><path d="m7 9 5-5 5 5"/>''');
  static const plug = MgIconData(false, r'''<path d="M12 22v-5M9 8V2M15 8V2M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8z"/>''');
  static const laptop = MgIconData(false, r'''<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M2 20h20M9 4v1.5a1.5 1.5 0 0 0 1.5 1.5h3A1.5 1.5 0 0 0 15 5.5V4"/>''');
  static const database = MgIconData(false, r'''<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0 0 18 0V5M3 12a9 3 0 0 0 18 0"/>''');
  static const flask = MgIconData(false, r'''<path d="M9 3h6M10 3v6.5L4.6 18.2A2 2 0 0 0 6.3 21h11.4a2 2 0 0 0 1.7-2.8L14 9.5V3M7.5 15h9"/>''');
  static const refresh = MgIconData(false, r'''<path d="M21 12a9 9 0 1 1-2.64-6.36L21 8M21 3v5h-5"/>''');
  static const settings = MgIconData(false, r'''<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>''');
  static const signOut = MgIconData(false, r'''<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>''');
  static const thumbFill = MgIconData(true, r'''<path d="M2.9 10.9h2.3v10.2H2.9z"/><path d="M9 10.4 12 2a3.13 3.13 0 0 1 3 3.88L14 10h5.83a2 2 0 0 1 1.92 2.56l-2.33 8A2 2 0 0 1 17.5 22H9z"/>''', strokeToo: true);
  static const history = MgIconData(false, r'''<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>''');
  static const shield = MgIconData(false, r'''<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>''');
  static const qr = MgIconData(false, r'''<rect width="5" height="5" x="3" y="3" rx="1"/><rect width="5" height="5" x="16" y="3" rx="1"/><rect width="5" height="5" x="3" y="16" rx="1"/><path d="M21 16h-3a2 2 0 0 0-2 2v3"/><path d="M21 21v.01"/><path d="M12 7v3a2 2 0 0 1-2 2H7"/><path d="M3 12h.01"/><path d="M12 3h.01"/><path d="M12 16v.01"/><path d="M16 12h1"/><path d="M21 12v.01"/><path d="M12 21v-1"/>''');
  static const code = MgIconData(false, r'''<path d="m16 18 6-6-6-6"/><path d="m8 6-6 6 6 6"/>''');
  static const archive = MgIconData(false, r'''<rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>''');
  static const alert = MgIconData(false, r'''<circle cx="12" cy="12" r="10"/><path d="M12 8v4"/><path d="M12 16h.01"/>''');
  static const lock = MgIconData(false, r'''<rect width="18" height="11" x="3" y="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>''');
  static const library = MgIconData(false, r'''<path d="m16 6 4 14"/><path d="M12 6v14"/><path d="M8 8v12"/><path d="M4 4v16"/>''');
  static const sliders = MgIconData(false, r'''<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M2 14h4M10 8h4M18 16h4"/>''');
  static const listPlus = MgIconData(false, r'''<path d="M11 12H3"/><path d="M16 6H3"/><path d="M16 18H3"/><path d="M18 9v6"/><path d="M21 12h-6"/>''');
  static const listNext = MgIconData(false, r'''<path d="M21 5H3"/><path d="M21 12H10"/><path d="M21 19H10"/><path d="m3 9 4 3-4 3"/>''');
  static const externalLink = MgIconData(false, r'''<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>''');
  static const swap = MgIconData(false, r'''<path d="m16 3 4 4-4 4"/><path d="M20 7H4"/><path d="m8 21-4-4 4-4"/><path d="M4 17h16"/>''');
  static const cloud = MgIconData(false, r'''<path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/>''');
  static const globe = MgIconData(false, r'''<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>''');
  static const palette = MgIconData(false, r'''<circle cx="13.5" cy="6.5" r=".5" fill="currentColor"/><circle cx="17.5" cy="10.5" r=".5" fill="currentColor"/><circle cx="8.5" cy="7.5" r=".5" fill="currentColor"/><circle cx="6.5" cy="12.5" r=".5" fill="currentColor"/><path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z"/>''');
  static const info = MgIconData(false, r'''<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>''');
}

/// An [MgIconData] at [size], in [color] (the ambient text/icon color if null).
class MgIcon extends StatelessWidget {
  const MgIcon(this.icon, {super.key, this.size = 20, this.color, this.strokeWidth = 1.75});
  final MgIconData icon;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _IconPainter(icon, c, strokeWidth)),
    );
  }
}

class _Shape {
  _Shape(this.path, this.fill);
  final Path path;
  final bool? fill; // null: as the icon
}

final _parsed = <String, List<_Shape>>{};

List<_Shape> _parse(MgIconData icon) => _parsed[icon.svg] ??= () {
      final out = <_Shape>[];
      final el = RegExp(r'<(path|circle|rect|line|ellipse|g)\b([^>]*?)(/?)>|</g>');
      final attr = RegExp(r'([a-zA-Z-]+)="([^"]*)"');
      final stack = <Matrix4>[Matrix4.identity()];
      for (final m in el.allMatches(icon.svg)) {
        if (m.group(0) == '</g>') {
          if (stack.length > 1) stack.removeLast();
          continue;
        }
        final tag = m.group(1)!;
        final a = {for (final x in attr.allMatches(m.group(2)!)) x.group(1)!: x.group(2)!};
        double n(String k, [double d = 0]) => double.tryParse(a[k] ?? '') ?? d;
        var t = stack.last.clone();
        final tr = a['transform'];
        if (tr != null) t = t.multiplied(_transform(tr));
        if (tag == 'g') {
          if (m.group(3) != '/') stack.add(t);
          continue;
        }
        final p = Path();
        switch (tag) {
          case 'path':
            writeSvgPathDataToPath(a['d'] ?? '', _PathProxy(p));
          case 'circle':
            p.addOval(Rect.fromCircle(center: Offset(n('cx'), n('cy')), radius: n('r')));
          case 'ellipse':
            p.addOval(Rect.fromCenter(center: Offset(n('cx'), n('cy')), width: 2 * n('rx'), height: 2 * n('ry')));
          case 'rect':
            final rx = n('rx', n('ry'));
            p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(n('x'), n('y'), n('width'), n('height')), Radius.circular(rx)));
          case 'line':
            p
              ..moveTo(n('x1'), n('y1'))
              ..lineTo(n('x2'), n('y2'));
        }
        final fillAttr = a['fill'];
        out.add(_Shape(p.transform(t.storage), fillAttr == null ? null : fillAttr != 'none'));
      }
      return out;
    }();

Matrix4 _transform(String s) {
  final nums = RegExp(r'-?[0-9]*\.?[0-9]+').allMatches(s).map((m) => double.parse(m.group(0)!)).toList();
  if (s.startsWith('translate')) {
    return Matrix4.translationValues(nums[0], nums.length > 1 ? nums[1] : 0, 0);
  }
  if (s.startsWith('matrix') && nums.length == 6) {
    return Matrix4(nums[0], nums[1], 0, 0, nums[2], nums[3], 0, 0, 0, 0, 1, 0, nums[4], nums[5], 0, 1);
  }
  return Matrix4.identity();
}

class _PathProxy extends PathProxy {
  _PathProxy(this.p);
  final Path p;
  @override
  void close() => p.close();
  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) => p.cubicTo(x1, y1, x2, y2, x3, y3);
  @override
  void lineTo(double x, double y) => p.lineTo(x, y);
  @override
  void moveTo(double x, double y) => p.moveTo(x, y);
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color, this.strokeWidth);
  final MgIconData icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.save();
    canvas.scale(k, k);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final s in _parse(icon)) {
      final filled = s.fill ?? icon.filled;
      if (filled) canvas.drawPath(s.path, fill);
      if (!filled || icon.strokeToo) canvas.drawPath(s.path, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}
