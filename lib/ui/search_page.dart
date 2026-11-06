import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services.dart';
import 'common.dart';
import 'detail_pages.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key, required this.pluginId});
  final String pluginId;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = TextEditingController();
  String _kind = 'tracks';
  String _query = '';
  SearchResult? _result;
  Object? _error;
  bool _loading = false;
  bool _loadingMore = false;
  List<String> _suggestions = [];
  Timer? _debounce;
  int _seq = 0;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    final p = svc.plugin(widget.pluginId)!;
    final seq = ++_seq;
    setState(() {
      _query = q;
      _suggestions = [];
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final offset = more ? (_result?.length ?? 0) : 0;
      final r = SearchResult.fromJson((await p.call('search', {'query': q, 'kind': _kind, 'offset': offset})) as Map? ?? const {}, widget.pluginId);
      if (seq != _seq) return;
      setState(() {
        if (more && _result != null) {
          _result = SearchResult(
            tracks: [..._result!.tracks, ...r.tracks],
            albums: [..._result!.albums, ...r.albums],
            artists: [..._result!.artists, ...r.artists],
            playlists: [..._result!.playlists, ...r.playlists],
            more: r.more && r.length > 0,
          );
        } else {
          _result = r;
        }
      });
    } catch (e) {
      if (seq != _seq) return;
      if (more) {
        if (mounted) toast(context, svc.describe(e));
      } else {
        setState(() => _error = e);
      }
    } finally {
      if (seq == _seq && mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final p = svc.plugin(widget.pluginId);
    if (p == null || !p.can('suggest') || text.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await p.call('suggest', {'query': text.trim()});
        if (!mounted || _controller.text != text) return;
        setState(() => _suggestions = ((r as List?) ?? const []).map((e) => '$e').take(8).toList());
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final kinds = {'tracks': s['tracks'], 'albums': s['albums'], 'artists': s['artists'], 'playlists': s['playlists']};
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SearchBar(
          controller: _controller,
          hintText: s['search'],
          leading: const Icon(Icons.search),
          trailing: [
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  setState(() => _suggestions = []);
                },
              ),
          ],
          onChanged: _onChanged,
          onSubmitted: (_) => _search(),
          textInputAction: TextInputAction.search,
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final e in kinds.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: _kind == e.key,
                onSelected: (_) {
                  setState(() => _kind = e.key);
                  if (_controller.text.trim().isNotEmpty) _search();
                },
              ),
            ),
        ]),
      ),
      Expanded(child: _body(context)),
    ]);
  }

  Widget _body(BuildContext context) {
    final s = svc.s;
    if (_suggestions.isNotEmpty) {
      return ListView(children: [
        for (final sug in _suggestions)
          ListTile(
            leading: const Icon(Icons.search),
            title: Text(sug),
            onTap: () {
              _controller.text = sug;
              _search();
            },
          ),
      ]);
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(error: _error!, onRetry: _search, pluginId: widget.pluginId);
    final r = _result;
    if (r == null) return const SizedBox.shrink();
    if (r.length == 0) return Center(child: Text(s['nothing']));
    final more = r.more
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : TextButton(onPressed: () => _search(more: true), child: Text(s['loadMore'])),
            ),
          )
        : const SizedBox(height: 16);
    final pid = widget.pluginId;
    return ListView(key: ValueKey('$_query/$_kind'), children: [
      for (var i = 0; i < r.tracks.length; i++) TrackTile(track: r.tracks[i], onTap: () => svc.player.playTracks(r.tracks, start: i)),
      for (final a in r.albums)
        ListTile(
          leading: Cover(a.imageUrl, size: 48),
          title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([a.artistNames, a.released].where((x) => x.isNotEmpty).join(' · '), maxLines: 1),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(pluginId: pid, album: a))),
        ),
      for (final a in r.artists)
        ListTile(
          leading: Cover(a.imageUrl, size: 48, round: true, icon: Icons.person),
          title: Text(a.name),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(pluginId: pid, artist: a))),
        ),
      for (final p in r.playlists)
        ListTile(
          leading: Cover(p.imageUrl, size: 48, icon: Icons.queue_music),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([p.owner, if (p.trackCount > 0) '${p.trackCount} ${s['songs']}'].where((x) => x.isNotEmpty).join(' · ')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(pluginId: pid, playlist: p))),
        ),
      more,
    ]);
  }
}
