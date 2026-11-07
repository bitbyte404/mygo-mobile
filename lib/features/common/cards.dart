// Cover cards, in rows that scroll sideways (phone) or grids (wider), and section titles.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// A cover over its name and a line under that (ui_pages.go coverCardWith):
/// 10-point corners and a soft shadow, the name 13/500 in up to two lines,
/// the line 12 muted. Pressed, it sinks a little.
class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.title, this.subtitle = '', this.imageUrl = '', this.round = false, this.icon = MgIcons.note, required this.onTap, this.width, this.heroTag});
  final String title, subtitle, imageUrl;
  final bool round;
  final MgIconData icon;
  final VoidCallback onTap;
  final double? width;
  final Object? heroTag;

  /// The height a card [w] wide takes, text included, at the text scale of
  /// [context]: a row of cards is exactly this tall, so nothing overflows.
  static double heightFor(BuildContext context, double w) {
    final ts = MediaQuery.textScalerOf(context);
    return w + 10 + 2 * ts.scale(13) * 1.35 + 4 + ts.scale(12) * 1.45 + 6;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return LayoutBuilder(builder: (context, c) {
      final w = width ?? c.maxWidth;
      Widget art = CoverArt(imageUrl, size: w, radius: MgRadius.card, round: round, icon: icon);
      if (heroTag != null) art = Hero(tag: heroTag!, child: art);
      return SizedBox(
        width: w,
        child: Pressable(
          onTap: onTap,
          pressedScale: 0.97,
          semanticLabel: title,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: round ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(round ? w : MgRadius.card),
                boxShadow: [BoxShadow(color: p.cardShade, blurRadius: 8, spreadRadius: -2, offset: const Offset(0, 2))],
              ),
              child: art,
            ),
            const SizedBox(height: 10),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: round ? TextAlign.center : TextAlign.start, style: MgType.cardTitle.copyWith(color: p.text)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.cardSub.copyWith(color: p.muted)),
            ],
          ]),
        ),
      );
    });
  }
}

/// Cards in a row that scrolls sideways (a phone), or in a grid of as many
/// columns of at least 156 as fit (MyGo cardRow, wider screens).
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.count, required this.itemBuilder, this.cardWidth = 140, this.grid});
  final int count;
  final Widget Function(BuildContext context, int i, double width) itemBuilder;
  final double cardWidth;
  final bool? grid;

  @override
  Widget build(BuildContext context) {
    final h = pageHPad(context);
    final pad = MediaQuery.paddingOf(context);
    final useGrid = grid ?? !isCompact(context);
    if (useGrid) {
      return LayoutBuilder(builder: (context, c) {
        final inner = c.maxWidth - 2 * h - pad.left - pad.right;
        final cols = math.max(2, ((inner + MgSize.gridGapX) / (156 + MgSize.gridGapX)).floor());
        final w = (inner - MgSize.gridGapX * (cols - 1)) / cols;
        final shown = math.min(count, cols * 2);
        return Padding(
          padding: EdgeInsets.fromLTRB(h + pad.left, 0, h + pad.right, 8),
          child: Wrap(spacing: MgSize.gridGapX, runSpacing: MgSize.gridGapY - 8, children: [for (var i = 0; i < shown; i++) itemBuilder(context, i, w)]),
        );
      });
    }
    return SizedBox(
      height: MediaCard.heightFor(context, cardWidth),
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: h + pad.left),
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) => Align(alignment: Alignment.topLeft, child: itemBuilder(context, i, cardWidth)),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.onMore, this.first = false});
  final String title;
  final VoidCallback? onMore;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final h = pageHPad(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(h + pad.left, 0, h - 6 + pad.right, 0),
      child: MgSectionTitle(title, onMore: onMore, top: first ? 4 : 26, moreLabel: svc.s['seeAll']),
    );
  }
}
