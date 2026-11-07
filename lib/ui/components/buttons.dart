// Pressable, icon and pill buttons (ui_kit.go iconButton, roundButton, pillButton, playPause).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:mygo_mobile/ui/theme/mg_theme.dart';

/// Something to press: it scales to [pressedScale] on a spring while held
/// (roundButton 0.88, pillButton 0.96, MyGo's ui.Snappy) and fills with
/// [pressedColor] over 120 ms, as MyGo fills what is under the pointer.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.color,
    this.pressedColor,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.semanticLabel,
    this.padding,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final double pressedScale;
  final Color? color, pressedColor;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final String? semanticLabel;
  final EdgeInsetsGeometry? padding;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);
  bool _down = false;

  void _to(double v) {
    _scale.animateWith(SpringSimulation(MgMotion.snappy, _scale.value, v, _scale.velocity));
  }

  void _set(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
    _to(down ? widget.pressedScale : 1);
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    final bg = _down && active ? (widget.pressedColor ?? widget.color) : widget.color;
    Widget box = AnimatedContainer(
      duration: MgMotion.hover,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: bg ?? Colors.transparent,
        borderRadius: widget.shape == BoxShape.circle ? null : widget.borderRadius,
        shape: widget.shape,
      ),
      child: widget.child,
    );
    box = AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
      child: box,
    );
    if (!active) return Opacity(opacity: widget.enabled ? 1 : 0.4, child: box);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: box,
      ),
    );
  }
}

/// A borderless round button showing an icon (ui_kit.go iconButton): a soft
/// circle under the finger, and it gives to 0.88 as it is pressed. [size] is
/// the icon's; the button is 16 larger, and at least 44 to touch.
class MgIconButton extends StatelessWidget {
  const MgIconButton(this.icon, {super.key, this.onTap, this.size = 20, this.color, this.tooltip, this.minTouch = 44});
  final MgIconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final String? tooltip;
  final double minTouch;

  @override
  Widget build(BuildContext context) {
    final d = math.max(size + 16, minTouch);
    final b = Pressable(
      onTap: onTap,
      pressedScale: 0.88,
      shape: BoxShape.circle,
      color: Colors.transparent,
      pressedColor: const Color.fromRGBO(128, 128, 128, 0.14),
      semanticLabel: tooltip,
      child: SizedBox.square(dimension: d, child: Center(child: MgIcon(icon, size: size, color: color ?? context.mg.text))),
    );
    return b;
  }
}

/// The play/pause glyph: as it changes, the one going shrinks and fades
/// while the one coming grows in, on a spring of 340 ms with a 0.3 bounce
/// (ui_kit.go playPause).
class PlayPauseGlyph extends StatefulWidget {
  const PlayPauseGlyph({super.key, required this.playing, this.size = 24, this.color});
  final bool playing;
  final double size;
  final Color? color;

  @override
  State<PlayPauseGlyph> createState() => _PlayPauseGlyphState();
}

class _PlayPauseGlyphState extends State<PlayPauseGlyph> with SingleTickerProviderStateMixin {
  late final AnimationController _v = AnimationController.unbounded(vsync: this, value: widget.playing ? 1 : 0);

  @override
  void didUpdateWidget(PlayPauseGlyph old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      _v.animateWith(SpringSimulation(MgMotion.playPauseSpring, _v.value, widget.playing ? 1 : 0, _v.velocity));
    }
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? context.mg.text;
    return AnimatedBuilder(
      animation: _v,
      builder: (context, _) {
        final v = _v.value;
        Widget one(MgIconData icon, double shown) {
          if (shown <= 0.01) return const SizedBox.shrink();
          final s = 0.4 + 0.6 * shown;
          return Transform.scale(scale: s, child: Opacity(opacity: shown.clamp(0.0, 1.0), child: MgIcon(icon, size: widget.size, color: c)));
        }

        return SizedBox.square(
          dimension: widget.size,
          child: Stack(alignment: Alignment.center, children: [one(MgIcons.play, 1 - v), one(MgIcons.pause, v)]),
        );
      },
    );
  }
}

/// A rounded button with an icon and a label (ui_kit.go pillButton): 36
/// tall, 18 in from its ends, a 14/600 label; it gives to 0.96.
class PillButton extends StatelessWidget {
  const PillButton({super.key, this.icon, required this.label, this.onTap, this.primary = false, this.background, this.foreground, this.height = 36});
  final MgIconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final Color? background, foreground;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final bg = background ?? (primary ? p.accent : p.secondaryFill);
    final fg = foreground ?? (primary ? p.onAccent : p.text);
    final pressed = primary ? p.accentPressed : Color.alphaBlend(p.press, p.bg);
    return Pressable(
      onTap: onTap,
      color: bg,
      pressedColor: background != null ? Color.lerp(bg, Colors.white, 0.12) : pressed,
      borderRadius: BorderRadius.circular(999),
      semanticLabel: label,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[MgIcon(icon!, size: 14, color: fg), const SizedBox(width: 8)],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.pill.copyWith(color: fg))),
          ]),
        ),
      ),
    );
  }
}

/// A plain text button: muted, the accent when [accent].
class TextAction extends StatelessWidget {
  const TextAction(this.label, {super.key, this.onTap, this.accent = false});
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.96,
      color: Colors.transparent,
      pressedColor: p.press,
      borderRadius: BorderRadius.circular(999),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent ? p.accent : p.muted)),
    );
  }
}
