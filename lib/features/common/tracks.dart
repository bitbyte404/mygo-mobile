// Songs in lists: the row, the song menu, Play/Shuffle, and the paged list.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/ui/ui.dart';
import 'package:mygo_mobile/features/album/album_screen.dart';
import 'package:mygo_mobile/features/artist/artist_screen.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'skeletons.dart';

/// A song in a list (ui_pages.go trackRow): its number or cover, its name
/// (the accent while it plays, with dancing bars), its artists, a heart if
/// liked, its length, and the song menu. A tap plays it; holding opens the
/// menu. Unavailable songs show at 42%.
class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, required this.onTap, this.index, this.showCover = true, this.trailing, this.showAlbum = true});
  final Track track;
  final VoidCallback onTap;
  final int? index;
  final bool showCover, showAlbum;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final compact = isCompact(context);
    return ValueListenableBuilder<Track?>(
      valueListenable: svc.player.current,
      builder: (context, cur, _) {
        final playing = cur?.key == track.key;
        final sub = [track.artistNames, if (showAlbum && track.album.name.isNotEmpty) track.album.name].where((x) => x.isNotEmpty).join(' · ');
        Widget lead;
        if (showCover) {
          lead = SizedBox.square(
            dimension: 44,
            child: Stack(fit: StackFit.expand, children: [
              CoverArt(track.album.imageUrl, size: 44, radius: MgRadius.rowCover),
              if (playing)
                DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(MgRadius.rowCover)),
                  child: Center(child: ValueListenableBuilder<bool>(valueListenable: svc.player.playingN, builder: (_, on, _) => NowPlayingBars(playing: on, color: Colors.white))),
                ),
            ]),
          );
        } else {
          lead = SizedBox(
            width: 28,
            child: Center(
              child: playing
                  ? ValueListenableBuilder<bool>(valueListenable: svc.player.playingN, builder: (_, on, _) => NowPlayingBars(playing: on))
                  : Text('${(index ?? 0) + 1}', style: TextStyle(fontSize: 13, color: p.faint, fontFeatures: MgType.tnum)),
            ),
          );
        }
        return Opacity(
          opacity: track.unavailable ? 0.42 : 1,
          child: Pressable(
            onTap: track.unavailable ? null : onTap,
            onLongPress: () => showTrackMenu(context, track),
            pressedScale: 0.985,
            color: playing ? p.accent.withValues(alpha: 0.09) : Colors.transparent,
            pressedColor: p.press,
            borderRadius: BorderRadius.circular(MgRadius.row),
            semanticLabel: track.name,
            child: SizedBox(
              height: compact ? MgSize.rowHeightCompact : MgSize.rowHeight + 4,
              child: Padding(
                padding: EdgeInsets.only(left: compact ? 8 : 12, right: compact ? 0 : 4),
                child: Row(children: [
                  lead,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.rowTitle.copyWith(fontSize: compact ? 15 : 14, color: playing ? p.accent : p.text)),
                      const SizedBox(height: 3),
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.rowSub.copyWith(color: p.muted)),
                    ]),
                  ),
                  ValueListenableBuilder(
                    valueListenable: svc.likes.liked,
                    builder: (context, liked, _) => liked[track.key] == true
                        ? Padding(padding: const EdgeInsets.only(left: 6), child: MgIcon(MgIcons.heartFill, size: 14, color: p.accent))
                        : const SizedBox.shrink(),
                  ),
                  if (!compact && track.duration > 0)
                    SizedBox(
                      width: 52,
                      child: Text(fmtDuration(Duration(milliseconds: track.duration)), textAlign: TextAlign.end, style: MgType.rowSub.copyWith(color: p.faint, fontFeatures: MgType.tnum)),
                    ),
                  trailing ?? MgIconButton(MgIcons.more, size: 18, color: p.muted, tooltip: svc.s['more'], onTap: () => showTrackMenu(context, track)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The song menu (MyGo's songItems), as a sheet: play next, add to queue,
/// like, go to the album / an artist.
Future<void> showTrackMenu(BuildContext context, Track t) async {
  final s = svc.s;
  final music = svc.music;
  svc.likes.refresh(t.source, [t]);
  await showMgSheet<void>(
    context,
    builder: (ctx) {
      final p = ctx.mg;
      void go(Widget page) {
        Navigator.pop(ctx);
        pushPage(context, page);
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Row(children: [
              CoverArt(t.album.imageUrl, size: 52, radius: 8),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
                  const SizedBox(height: 3),
                  Text(t.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.rowSub.copyWith(color: p.muted)),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: 6),
          MgListRow(icon: MgIcons.listNext, label: s['playNext'], onTap: () {
            Navigator.pop(ctx);
            svc.player.addNext(t);
            toast(context, s['addedNext']);
          }),
          MgListRow(icon: MgIcons.listPlus, label: s['addToQueue'], onTap: () {
            Navigator.pop(ctx);
            svc.player.addToQueue(t);
            toast(context, s['addedQueue']);
          }),
          if (music.can(t.source, 'like'))
            ValueListenableBuilder(
              valueListenable: svc.likes.liked,
              builder: (_, liked, _) {
                final on = liked[t.key] ?? false;
                return MgListRow(
                  leading: MgIcon(on ? MgIcons.heartFill : MgIcons.heart, size: 19, color: on ? p.accent : p.text),
                  label: on ? s['unlike'] : s['like'],
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await svc.likes.setLiked(t, !on);
                    } catch (e) {
                      if (context.mounted) toast(context, svc.describe(e));
                    }
                  },
                );
              },
            ),
          if (music.can(t.source, 'album') && t.album.id.isNotEmpty)
            MgListRow(icon: MgIcons.album, label: '${s['viewAlbum']} · ${t.album.name}', onTap: () => go(AlbumScreen(pluginId: t.source, album: t.album))),
          if (music.can(t.source, 'artist'))
            for (final a in t.artists.where((a) => a.id.isNotEmpty))
              MgListRow(icon: MgIcons.user, label: '${s['viewArtist']} · ${a.name}', onTap: () => go(ArtistScreen(pluginId: t.source, artist: a))),
        ]),
      );
    },
  );
}

/// Play and Shuffle (ui_pages.go playButtons): the accent pill and the
/// secondary one. [all], if given, is asked for the whole list first (a list
/// loaded a page at a time plays all of it, not just what is loaded).
class PlayButtons extends StatefulWidget {
  const PlayButtons({super.key, required this.tracks, this.all, this.extra = const []});
  final List<Track> tracks;
  final Future<List<Track>> Function()? all;
  final List<Widget> extra;

  @override
  State<PlayButtons> createState() => _PlayButtonsState();
}

class _PlayButtonsState extends State<PlayButtons> {
  bool _busy = false;

  Future<void> _play(bool shuffled) async {
    if (_busy) return;
    var list = widget.tracks;
    if (widget.all != null) {
      setState(() => _busy = true);
      try {
        list = await widget.all!();
      } catch (e) {
        if (mounted) toast(context, svc.describe(e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    await svc.player.playTracks(list, start: shuffled ? -1 : 0, shuffled: shuffled);
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final n = widget.tracks.length;
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      PillButton(primary: true, icon: MgIcons.play, label: widget.all == null ? '${s['playAll']} ($n)' : s['playAll'], onTap: n == 0 ? null : () => _play(false)),
      PillButton(icon: MgIcons.shuffle, label: s['shuffle'], onTap: n == 0 ? null : () => _play(true)),
      if (_busy) const Padding(padding: EdgeInsets.only(left: 4), child: MgSpinner(size: 18)),
      ...widget.extra,
    ]);
  }
}

/// A list of tracks under a header, with Play / Shuffle; with [onLoadMore],
/// the next page is asked for as the end comes within a screen (MyGo
/// pageFoot), with a spinner at the foot meanwhile.
class TrackListView extends StatefulWidget {
  const TrackListView({super.key, required this.tracks, this.header, this.onLoadMore, this.more = false, this.numbered = false, this.playAll, this.showButtons = true, this.showAlbum = true});
  final List<Track> tracks;
  final Widget? header;
  final Future<void> Function()? onLoadMore;
  final bool more, numbered, showButtons, showAlbum;
  final Future<List<Track>> Function()? playAll;

  @override
  State<TrackListView> createState() => _TrackListViewState();
}

class _TrackListViewState extends State<TrackListView> {
  bool _loading = false;

  void _maybeMore() {
    if (_loading || !widget.more || widget.onLoadMore == null) return;
    _loading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.onLoadMore!();
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final p = context.mg;
    final tracks = widget.tracks;
    final h = pageHPad(context);
    final ins = pageInsets(context, h: h - (isCompact(context) ? 8 : 12));
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: ins,
      itemCount: tracks.length + 3,
      itemBuilder: (context, i) {
        if (i == 0) return Padding(padding: EdgeInsets.symmetric(horizontal: isCompact(context) ? 8 : 12), child: widget.header ?? const SizedBox.shrink());
        if (i == 1) {
          if (tracks.isEmpty) return Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(s['nothing'], style: TextStyle(color: p.muted))));
          if (!widget.showButtons) return const SizedBox(height: 4);
          return Padding(
            padding: EdgeInsets.fromLTRB(isCompact(context) ? 8 : 12, 0, 8, 14),
            child: PlayButtons(tracks: tracks, all: widget.playAll),
          );
        }
        final k = i - 2;
        if (k == tracks.length) {
          if (!widget.more) return const SizedBox(height: 8);
          _maybeMore();
          return const SkeletonMoreRows();
        }
        if (widget.more && k > tracks.length - 15) _maybeMore();
        return TrackTile(
          track: tracks[k],
          index: k,
          showCover: !widget.numbered,
          showAlbum: widget.showAlbum,
          onTap: () => svc.player.playTracks(tracks, start: k),
        );
      },
    );
  }
}

