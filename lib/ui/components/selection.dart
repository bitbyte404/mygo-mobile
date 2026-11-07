// Segmented control and chips (ui_kit.go segmented, ui_nowplaying.go paneTab).

import 'package:flutter/material.dart';
import 'package:mygo_mobile/ui/theme/mg_theme.dart';
import 'buttons.dart';

/// A segmented control as AppKit draws one (ui_kit.go segmented): equal
/// segments in a small gray track, the one chosen raised on a capsule that
/// slides to the next on a 280 ms spring.
class MgSegmented<T> extends StatelessWidget {
  const MgSegmented({super.key, required this.values, required this.labels, required this.selected, required this.onChanged, this.height = 32});
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final track = p.dark ? const Color.fromRGBO(255, 255, 255, 0.08) : const Color.fromRGBO(0, 0, 0, 0.06);
    final capsule = p.dark ? const Color.fromRGBO(255, 255, 255, 0.24) : Colors.white;
    final i = values.indexOf(selected);
    const inset = 2.0;
    return Container(
      height: height,
      padding: const EdgeInsets.all(inset),
      decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(8)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / values.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: SpringCurve(MgMotion.segmentSpring),
            left: w * i,
            top: 0,
            bottom: 0,
            width: w,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: capsule,
                borderRadius: BorderRadius.circular(7),
                boxShadow: p.dark
                    ? null
                    : const [
                        BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.2), blurRadius: 1, offset: Offset(0, 0.5)),
                        BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.06), blurRadius: 3, offset: Offset(0, 1)),
                      ],
              ),
            ),
          ),
          Row(children: [
            for (var k = 0; k < values.length; k++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(values[k]),
                  child: Center(
                    child: Text(labels[k], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.text, fontWeight: k == i ? FontWeight.w600 : FontWeight.w400)),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// A pill to choose among a few (Now Playing's pane tabs, ui_nowplaying.go
/// paneTab): 13/600, the chosen one on a 14% fill. On the page's own colors
/// unless [onDark].
class MgChip extends StatelessWidget {
  const MgChip({super.key, required this.label, required this.selected, required this.onTap, this.onDark = false, this.icon});
  final String label;
  final bool selected, onDark;
  final VoidCallback onTap;
  final MgIconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final on = onDark ? Colors.white : p.text;
    final bg = selected ? on.withValues(alpha: onDark ? 0.14 : 0.1) : (onDark ? Colors.transparent : p.hover);
    final fg = selected ? on : on.withValues(alpha: onDark ? 0.55 : 0.62);
    return Pressable(
      onTap: onTap,
      color: bg,
      pressedColor: on.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      semanticLabel: label,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[MgIcon(icon!, size: 14, color: fg), const SizedBox(width: 6)],
        Text(label, style: MgType.npTab.copyWith(color: fg)),
      ]),
    );
  }
}
