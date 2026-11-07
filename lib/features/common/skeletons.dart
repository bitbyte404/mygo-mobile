// Loading pages: skeletons laid out like the pages they stand in for, with
// the same paddings, rows and card grids (phone and wide), so the content
// lands where its shapes were.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/features/common/cards.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// The kinds of page [Loader] can stand a skeleton in for.
enum SkeletonKind {
  /// Home and browse pages: a heading, a section of songs, rows of cards.
  browse,

  /// A list of songs under a heading (liked, recent, daily picks, charts).
  tracks,

  /// A playlist or album: the big header, then its songs.
  collection,

  /// An artist: a round header, top songs, albums.
  artist,

  /// A grid of cards (saved albums, playlists, stations).
  cards,
}

/// A whole page's skeleton, scrolling like the page (but not scrollable).
class PageSkeleton extends StatelessWidget {
  const PageSkeleton({super.key, this.kind = SkeletonKind.tracks, this.header, this.rows = 10});
  final SkeletonKind kind;

  /// What the page shows over its content regardless (the source switcher).
  final Widget? header;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final h = pageHPad(context);
    final compact = isCompact(context);
    Widget padded(Widget w, {double inset = 0}) => Padding(padding: EdgeInsets.fromLTRB(h - inset + pad.left, 0, h - inset + pad.right, 0), child: w);
    Widget songRows(int n, {int from = 0}) => Column(children: [
          for (var i = 0; i < n; i++) padded(SkeletonSongRow(index: from + i, compact: compact), inset: compact ? 8 : 12),
        ]);
    Widget cards({bool round = false, double width = 140}) => CardRow(
          count: 8,
          cardWidth: width,
          itemBuilder: (context, i, w) => SkeletonCardTile(width: w, round: round, index: i),
        );
    final children = <Widget>[
      if (header != null) padded(header!),
    ];
    switch (kind) {
      case SkeletonKind.browse:
        children
          ..add(padded(SkeletonHeading(compact: compact)))
          ..add(padded(const SkeletonSectionHeader(first: true)))
          ..add(songRows(compact ? 5 : 6))
          ..add(padded(const SkeletonSectionHeader(width: 160)))
          ..add(cards())
          ..add(padded(const SkeletonSectionHeader(width: 112)))
          ..add(cards());
      case SkeletonKind.tracks:
        children
          ..add(padded(SkeletonHeading(compact: compact)))
          ..add(padded(const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Row(children: [MgBone(width: 96, height: 36, radius: 999), SizedBox(width: 10), MgBone(width: 96, height: 36, radius: 999)]),
          )))
          ..add(songRows(rows));
      case SkeletonKind.collection:
        children
          ..add(padded(const SkeletonCollectionHeader()))
          ..add(songRows(rows));
      case SkeletonKind.artist:
        children
          ..add(padded(const SkeletonCollectionHeader(round: true)))
          ..add(padded(const SkeletonSectionHeader(first: true)))
          ..add(songRows(5))
          ..add(padded(const SkeletonSectionHeader(width: 96)))
          ..add(cards());
      case SkeletonKind.cards:
        children
          ..add(padded(SkeletonHeading(compact: compact)))
          ..add(CardRow(count: compact ? 6 : 12, grid: true, itemBuilder: (context, i, w) => SkeletonCardTile(width: w, index: i)));
    }
    return MgShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, pad.top + MgSize.pageGap, 0, pad.bottom + 32),
        children: children,
      ),
    );
  }
}

/// More songs coming at the end of a list: two song rows' shapes.
class SkeletonMoreRows extends StatelessWidget {
  const SkeletonMoreRows({super.key, this.count = 2});
  final int count;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return MgShimmer(child: Column(children: [for (var i = 0; i < count; i++) SkeletonSongRow(index: i + 3, compact: compact)]));
  }
}
