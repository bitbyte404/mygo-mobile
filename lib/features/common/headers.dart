// A page's header: cover, kind, title, facts, buttons.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// A page's header (ui_pages.go playlistHeader): the cover, 212 square with
/// 14 corners and a deep soft shadow, beside (on a phone, over) a line in the
/// accent saying what it is, the title 30/800, a line of facts, the
/// description, and the buttons.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow = '',
    this.subtitle = '',
    this.imageUrl = '',
    this.description = '',
    this.round = false,
    this.heroTag,
    this.cover,
    this.actions = const [],
    this.icon = MgIcons.note,
  });
  final String title, eyebrow, subtitle, imageUrl, description;
  final bool round;
  final Object? heroTag;
  final Widget? cover; // in place of the artwork (Liked Songs' gradient)
  final List<Widget> actions;
  final MgIconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final compact = isCompact(context);
    final w = MediaQuery.sizeOf(context).width;
    final size = compact ? math.min(w * 0.5, 200.0) : MgSize.headerCover;
    Widget art = cover ?? CoverArt(imageUrl, size: size, radius: MgRadius.header, round: round, icon: icon);
    if (heroTag != null) art = Hero(tag: heroTag!, child: art);
    art = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(round ? size : MgRadius.header),
        boxShadow: [BoxShadow(color: p.cardShade, blurRadius: 40, spreadRadius: -10, offset: const Offset(0, 18))],
      ),
      child: art,
    );
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (eyebrow.isNotEmpty) ...[Text(eyebrow, style: MgType.eyebrow.copyWith(color: p.accent, letterSpacing: 0)), const SizedBox(height: 8)],
      Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: (compact ? MgType.pageTitleCompact : MgType.pageTitle).copyWith(color: p.text)),
      if (subtitle.isNotEmpty) ...[const SizedBox(height: 8), Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.muted))],
      if (description.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(description.replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, height: 1.45, color: p.muted)),
      ],
      if (actions.isNotEmpty) ...[const SizedBox(height: 16), ...actions],
    ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [art, const SizedBox(height: 20), text])
          : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [art, const SizedBox(width: 28), Expanded(child: text)]),
    );
  }
}

