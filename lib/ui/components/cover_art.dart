// Covers that fade in over a placeholder, and the artwork tint (artwork.go dominantColor).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mygo_mobile/ui/theme/mg_theme.dart';

/// An artwork, or a placeholder of the same size while it loads: the
/// placeholder is the hover fill with a music note at 30%, and the art fades
/// in over it in 320 ms (ui_kit.go cover / artIn).
class CoverArt extends StatelessWidget {
  const CoverArt(this.url, {super.key, this.size, this.radius = MgRadius.rowCover, this.round = false, this.icon = MgIcons.note, this.shadow = false, this.placeholderColor});
  final String url;
  final double? size; // null: fill the parent (which must be bounded)
  final double radius;
  final bool round;
  final MgIconData icon;
  final bool shadow;
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final r = BorderRadius.circular(round ? 9999 : radius);
    return LayoutBuilder(builder: (context, c) {
      final side = size ?? (c.biggest.shortestSide.isFinite ? c.biggest.shortestSide : 120);
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final ph = DecoratedBox(
        decoration: BoxDecoration(color: placeholderColor ?? p.hover, borderRadius: r),
        child: Center(child: MgIcon(icon, size: side * 0.3, color: p.faint)),
      );
      Widget child = ph;
      if (url.isNotEmpty) {
        child = Image(
          image: ResizeImage.resizeIfNeeded((side * dpr).round().clamp(48, 1200), null, NetworkImage(url)),
          width: side,
          height: side,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => ph,
          frameBuilder: (context, img, frame, sync) {
            if (sync) return img;
            return Stack(fit: StackFit.passthrough, children: [
              ph,
              AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: MgMotion.artFade, curve: Curves.easeOut, child: img),
            ]);
          },
        );
      }
      return Container(
        width: side,
        height: side,
        decoration: shadow ? BoxDecoration(borderRadius: r, boxShadow: [BoxShadow(color: p.cardShade, blurRadius: 8, offset: const Offset(0, 2), spreadRadius: -2)]) : null,
        child: ClipRRect(borderRadius: r, child: child),
      );
    });
  }
}

/// The most vivid color that covers much of an artwork: the hue its
/// saturated pixels share most, at their mean, from a 24-pixel copy
/// (artwork.go dominantColor). Computed once per url and cached.
class ArtTint {
  ArtTint._();
  static final _cache = <String, Color?>{};
  static final _pending = <String, Future<Color?>>{};

  static Color? cached(String url) => _cache[url];

  static Future<Color?> of(String url) {
    if (url.isEmpty) return Future.value(null);
    if (_cache.containsKey(url)) return Future.value(_cache[url]);
    return _pending[url] ??= _compute(url).then((c) {
      _cache[url] = c;
      _pending.remove(url);
      return c;
    });
  }

  static Future<Color?> _compute(String url) async {
    final done = Completer<ui.Image?>();
    final stream = ResizeImage(NetworkImage(url), width: 24, height: 24, policy: ResizeImagePolicy.exact).resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      stream.removeListener(l);
    }, onError: (_, _) {
      if (!done.isCompleted) done.complete(null);
      stream.removeListener(l);
    });
    stream.addListener(l);
    final img = await done.future;
    if (img == null) return null;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (data == null) return null;
    return dominantColor(data.buffer.asUint8List());
  }

  static Color dominantColor(List<int> px) {
    const buckets = 18;
    final weight = List<double>.filled(buckets, 0);
    final sum = List.generate(buckets, (_) => [0.0, 0.0, 0.0]);
    final gray = [0.0, 0.0, 0.0];
    final n = px.length ~/ 4;
    for (var i = 0; i < px.length; i += 4) {
      final r = px[i] / 255, g = px[i + 1] / 255, b = px[i + 2] / 255;
      gray[0] += r;
      gray[1] += g;
      gray[2] += b;
      final (h, s, v) = hsvOf(Color.from(alpha: 1, red: r, green: g, blue: b));
      if (s < 0.15 || v < 0.15) continue;
      final w = s * s * v;
      final k = (h / 360 * buckets).floor() % buckets;
      weight[k] += w;
      sum[k][0] += r * w;
      sum[k][1] += g * w;
      sum[k][2] += b * w;
    }
    var best = 0;
    for (var k = 0; k < buckets; k++) {
      if (weight[k] > weight[best]) best = k;
    }
    // Scaled for a 24x24 copy as artwork.go's threshold (2) is.
    if (weight[best] < 2 || n == 0) {
      return Color.from(alpha: 1, red: gray[0] / n, green: gray[1] / n, blue: gray[2] / n);
    }
    final w = weight[best];
    return Color.from(alpha: 1, red: sum[best][0] / w, green: sum[best][1] / w, blue: sum[best][2] / w);
  }
}

/// Builds with an artwork's tint once known (null until then, or [fallback]).
class ArtTintBuilder extends StatefulWidget {
  const ArtTintBuilder({super.key, required this.url, required this.builder});
  final String url;
  final Widget Function(BuildContext context, Color? tint) builder;

  @override
  State<ArtTintBuilder> createState() => _ArtTintBuilderState();
}

class _ArtTintBuilderState extends State<ArtTintBuilder> {
  Color? _tint;
  String? _for;

  void _load() {
    final url = widget.url;
    _for = url;
    final c = ArtTint.cached(url);
    if (c != null) {
      _tint = c;
      return;
    }
    ArtTint.of(url).then((c) {
      if (!mounted || _for != url || c == null) return;
      setState(() => _tint = c);
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtTintBuilder old) {
    super.didUpdateWidget(old);
    // The colors stay the last song's while the next cover loads.
    if (old.url != widget.url) _load();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _tint);
}
