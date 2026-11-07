// Search: a field, kinds as chips, suggestions while typing, results paged.
import 'package:flutter/material.dart' hide SearchController;
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/features/album/album_screen.dart';
import 'package:mygo_mobile/features/artist/artist_screen.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/skeletons.dart';
import 'package:mygo_mobile/features/common/tracks.dart';
import 'package:mygo_mobile/features/playlist/playlist_screens.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'search_controller.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key, required this.pluginId, this.initialQuery = ''});
  final String pluginId;
  final String initialQuery;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  final _focus = FocusNode();
  late final SearchController _c = SearchController(
    searchFn: (q, kind, offset) => svc.music.search(widget.pluginId, query: q, kind: kind, offset: offset),
    suggestFn: svc.music.can(widget.pluginId, 'suggest') ? (q) => svc.music.suggest(widget.pluginId, q) : null,
  );

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    if (widget.initialQuery.trim().isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _c.removeListener(_changed);
    _c.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    try {
      await _c.search(_controller.text, more: more);
    } catch (e) {
      if (mounted) toast(context, svc.describe(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final kinds = {'tracks': s['tracks'], 'albums': s['albums'], 'artists': s['artists'], 'playlists': s['playlists']};
    final pad = MediaQuery.paddingOf(context);
    final h = pageHPad(context);
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(h + pad.left, pad.top + MgSize.pageGap, h + pad.right, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MgHeading(s['search'], compact: isCompact(context)),
          MgTextField(
            controller: _controller,
            focusNode: _focus,
            hint: s['searchHint'],
            icon: MgIcons.search,
            onChanged: _c.typed,
            onSubmitted: (_) => _search(),
            onClear: _c.clearSuggestions,
            action: TextInputAction.search,
          ),
          const SizedBox(height: 12),
        ]),
      ),
      SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: h + pad.left),
          children: [
            for (final e in kinds.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: MgChip(
                  label: e.value,
                  selected: _c.kind == e.key,
                  onTap: () {
                    _c.query = _controller.text.trim();
                    _c.setKind(e.key);
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: AnimatedSwitcher(duration: MgMotion.reveal, child: _body(context)),
        ),
      ),
    ]);
  }

  Widget _body(BuildContext context) {
    final s = svc.s;
    final p = context.mg;
    final ins = pageInsets(context, h: pageHPad(context) - (isCompact(context) ? 8 : 12));
    final insets = ins.copyWith(top: 4);
    if (_c.suggestions.isNotEmpty && _focus.hasFocus) {
      return ListView(key: const ValueKey('suggest'), padding: insets, children: [
        for (final sug in _c.suggestions)
          MgListRow(
            icon: MgIcons.search,
            label: sug,
            onTap: () {
              _controller.text = sug;
              _focus.unfocus();
              _search();
            },
          ),
      ]);
    }
    if (_c.loading) {
      final compact = isCompact(context);
      return MgShimmer(
        key: const ValueKey('loading'),
        child: ListView(physics: const NeverScrollableScrollPhysics(), padding: insets, children: [for (var i = 0; i < 12; i++) SkeletonSongRow(index: i, compact: compact)]),
      );
    }
    if (_c.error != null) return ErrorView(key: const ValueKey('error'), error: _c.error!, onRetry: _search, pluginId: widget.pluginId);
    final r = _c.result;
    if (r == null) {
      return Center(key: const ValueKey('empty'), child: MgEmpty(icon: MgIcons.search, title: s['searchEmpty'], message: s['searchEmptyHint']));
    }
    if (r.length == 0) return Center(key: const ValueKey('none'), child: Text(s['nothing'], style: TextStyle(color: p.muted)));
    final pid = widget.pluginId;
    final rows = <Widget>[
      for (var i = 0; i < r.tracks.length; i++) TrackTile(track: r.tracks[i], onTap: () => svc.player.playTracks(r.tracks, start: i)),
      for (var i = 0; i < r.albums.length; i++)
        MgListRow(
          leading: Hero(tag: 'album:search/$i/${r.albums[i].id}', child: CoverArt(r.albums[i].imageUrl, size: 48, radius: MgRadius.rowCover, icon: MgIcons.album)),
          label: r.albums[i].name,
          sub: [r.albums[i].artistNames, r.albums[i].released].where((x) => x.isNotEmpty).join(' · '),
          onTap: () => pushPage(context, AlbumScreen(pluginId: pid, album: r.albums[i], heroTag: 'album:search/$i/${r.albums[i].id}')),
        ),
      for (var i = 0; i < r.artists.length; i++)
        MgListRow(
          leading: Hero(tag: 'artist:search/$i/${r.artists[i].id}', child: CoverArt(r.artists[i].imageUrl, size: 48, round: true, icon: MgIcons.user)),
          label: r.artists[i].name,
          onTap: () => pushPage(context, ArtistScreen(pluginId: pid, artist: r.artists[i], heroTag: 'artist:search/$i/${r.artists[i].id}')),
        ),
      for (var i = 0; i < r.playlists.length; i++)
        MgListRow(
          leading: Hero(tag: 'playlist:search/$i/${r.playlists[i].id}', child: CoverArt(r.playlists[i].imageUrl, size: 48, radius: MgRadius.rowCover, icon: MgIcons.playlist)),
          label: r.playlists[i].name,
          sub: [r.playlists[i].owner, if (r.playlists[i].trackCount > 0) '${r.playlists[i].trackCount} ${s['songs']}'].where((x) => x.isNotEmpty).join(' · '),
          onTap: () => pushPage(context, PlaylistScreen(pluginId: pid, playlist: r.playlists[i], heroTag: 'playlist:search/$i/${r.playlists[i].id}')),
        ),
    ];
    return NotificationListener<ScrollNotification>(
      key: ValueKey('${_c.query}/${_c.kind}'),
      onNotification: (n) {
        if (r.more && !_c.loadingMore && n.metrics.extentAfter < 600) _search(more: true);
        return false;
      },
      child: ListView(
        padding: insets,
        children: [
          ...rows,
          if (r.more) const SkeletonMoreRows(),
        ],
      ),
    );
  }
}
