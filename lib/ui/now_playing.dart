import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../player/player.dart';
import '../services.dart';
import 'common.dart';
import 'detail_pages.dart';

/// The bar above the bottom navigation while something plays.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = svc.player;
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Track?>(
      valueListenable: player.current,
      builder: (context, t, _) {
        if (t == null) return const SizedBox.shrink();
        return Material(
          color: scheme.surfaceContainerHigh,
          child: InkWell(
            onTap: () => openNowPlaying(context),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _ProgressLine(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(children: [
                  Hero(tag: 'cover', child: Cover(t.album.imageUrl, size: 44)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge),
                      Text(t.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                  const _PlayPauseButton(size: 32),
                  IconButton(icon: const Icon(Icons.skip_next), onPressed: player.skipToNext),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _ProgressLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: svc.player.positionStream,
      builder: (context, snap) {
        final d = svc.player.duration ?? Duration.zero;
        final p = snap.data ?? Duration.zero;
        final v = d.inMilliseconds <= 0 ? 0.0 : (p.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
        return LinearProgressIndicator(value: v, minHeight: 2);
      },
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({this.size = 40, this.filled = false});
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final player = svc.player;
    return ValueListenableBuilder<bool>(
      valueListenable: player.loading,
      builder: (context, loading, _) => StreamBuilder<bool>(
        stream: player.playingStream,
        initialData: player.playing,
        builder: (context, snap) {
          final playing = snap.data ?? false;
          if (loading) {
            return SizedBox(width: size + 16, height: size + 16, child: const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.5)));
          }
          final icon = Icon(playing ? Icons.pause : Icons.play_arrow, size: size);
          final onPressed = playing ? player.pause : player.play;
          return filled ? IconButton.filled(iconSize: size, icon: icon, onPressed: onPressed) : IconButton(icon: icon, onPressed: onPressed);
        },
      ),
    );
  }
}

void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const NowPlayingPage()));
}

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    svc.player.current.addListener(_onTrack);
    _onTrack();
  }

  @override
  void dispose() {
    svc.player.current.removeListener(_onTrack);
    super.dispose();
  }

  void _onTrack() {
    final t = svc.player.current.value;
    if (t != null) svc.refreshLiked(t.source, [t]);
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final player = svc.player;
    return ValueListenableBuilder<Track?>(
      valueListenable: player.current,
      builder: (context, t, _) {
        if (t == null) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text(s['nothing'])));
        }
        final p = svc.plugin(t.source);
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => Navigator.pop(context)),
            title: Text(s['nowPlaying']),
            centerTitle: true,
            actions: [
              if (p != null && p.can('comments'))
                IconButton(icon: const Icon(Icons.comment_outlined), tooltip: s['comments'], onPressed: () => _comments(context, t)),
              IconButton(icon: const Icon(Icons.queue_music), tooltip: s['queue'], onPressed: () => _queue(context)),
            ],
          ),
          body: SafeArea(
            child: Column(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _showLyrics = !_showLyrics),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _showLyrics
                        ? LyricsView(key: ValueKey('lyrics-${t.key}'), track: t)
                        : Center(
                            key: ValueKey('cover-${t.key}'),
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: LayoutBuilder(
                                builder: (context, c) {
                                  final size = c.biggest.shortestSide.clamp(120.0, 420.0);
                                  return Hero(tag: 'cover', child: Cover(t.album.imageUrl, size: size, radius: 16));
                                },
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.name, style: Theme.of(context).textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: p != null && p.can('artist') && t.artists.isNotEmpty && t.artists.first.id.isNotEmpty
                            ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(pluginId: t.source, artist: t.artists.first)))
                            : null,
                        child: Text(t.artistNames, style: Theme.of(context).textTheme.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ),
                  if (p != null && p.can('like'))
                    ValueListenableBuilder(
                      valueListenable: svc.liked,
                      builder: (context, liked, _) {
                        final on = liked[t.key] ?? false;
                        return IconButton(
                          icon: Icon(on ? Icons.favorite : Icons.favorite_border, color: on ? Colors.redAccent : null),
                          onPressed: () async {
                            try {
                              await svc.setLiked(t, !on);
                            } catch (e) {
                              if (context.mounted) toast(context, svc.describe(e));
                            }
                          },
                        );
                      },
                    ),
                ]),
              ),
              const _SeekBar(),
              const _Controls(),
              ValueListenableBuilder<String?>(
                valueListenable: player.error,
                builder: (context, err, _) => ValueListenableBuilder<StreamInfo?>(
                  valueListenable: player.streamInfo,
                  builder: (context, si, _) {
                    final text = err ??
                        (si == null
                            ? ''
                            : [si.type.toUpperCase(), if (si.bitRate > 0) '${si.bitRate} kbps', if (si.quality.isNotEmpty) s[si.quality]].join(' · '));
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: err != null ? Theme.of(context).colorScheme.error : null)),
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _queue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => ValueListenableBuilder<List<Track>>(
          valueListenable: svc.player.tracks,
          builder: (ctx, tracks, _) {
            final order = svc.player.order;
            return ListView.builder(
              controller: controller,
              itemCount: order.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return ListTile(title: Text('${svc.s['queue']} (${tracks.length})', style: Theme.of(ctx).textTheme.titleMedium));
                }
                final idx = order[i - 1];
                if (idx >= tracks.length) return const SizedBox.shrink();
                final t = tracks[idx];
                final cur = idx == svc.player.index;
                return ListTile(
                  leading: cur ? Icon(Icons.graphic_eq, color: Theme.of(ctx).colorScheme.primary) : Cover(t.album.imageUrl, size: 40),
                  title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: cur ? TextStyle(color: Theme.of(ctx).colorScheme.primary) : null),
                  subtitle: Text(t.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: cur ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => svc.player.removeAt(idx)),
                  onTap: () => svc.player.skipToQueueItem(idx),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _comments(BuildContext context, Track t) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, controller) => CommentsView(track: t, controller: controller),
      ),
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar();
  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = svc.player;
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        var d = player.duration ?? Duration.zero;
        final cur = player.current.value;
        if (d == Duration.zero && cur != null && cur.duration > 0) d = Duration(milliseconds: cur.duration);
        final pos = snap.data ?? Duration.zero;
        final max = d.inMilliseconds.toDouble().clamp(1.0, double.infinity);
        final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            Slider(
              value: value,
              max: max,
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                player.seek(Duration(milliseconds: v.round()));
                setState(() => _drag = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(fmtDuration(Duration(milliseconds: value.round())), style: Theme.of(context).textTheme.bodySmall),
                Text(fmtDuration(d), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final player = svc.player;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        ValueListenableBuilder<bool>(
          valueListenable: player.shuffle,
          builder: (context, on, _) => IconButton(icon: Icon(Icons.shuffle, color: on ? primary : null), onPressed: player.toggleShuffle),
        ),
        IconButton(iconSize: 36, icon: const Icon(Icons.skip_previous), onPressed: player.skipToPrevious),
        const _PlayPauseButton(size: 44, filled: true),
        IconButton(iconSize: 36, icon: const Icon(Icons.skip_next), onPressed: player.skipToNext),
        ValueListenableBuilder<Repeat>(
          valueListenable: player.repeat,
          builder: (context, m, _) => IconButton(
            icon: Icon(m == Repeat.one ? Icons.repeat_one : Icons.repeat, color: m == Repeat.off ? null : primary),
            onPressed: player.cycleRepeat,
          ),
        ),
      ]),
    );
  }
}

/// Synced lyrics: the line at the current position is highlighted and kept
/// in view; tapping a line seeks to it.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.track});
  final Track track;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  late Future<List<LyricLine>> _future;
  final _scroll = ScrollController();
  StreamSubscription<Duration>? _sub;
  int _current = -1;
  List<LyricLine> _lines = const [];
  static const _lineHeight = 56.0;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _sub = svc.player.positionStream.listen(_onPosition);
  }

  Future<List<LyricLine>> _load() async {
    final p = svc.plugin(widget.track.source);
    if (p == null || !p.can('lyrics')) return const [];
    final r = await p.call('lyrics', {'id': widget.track.id});
    _lines = r is Map ? parseLyrics(r) : const [];
    return _lines;
  }

  void _onPosition(Duration pos) {
    if (_lines.isEmpty) return;
    final ms = pos.inMilliseconds;
    var i = -1;
    for (var k = 0; k < _lines.length; k++) {
      if (_lines[k].start <= ms) {
        i = k;
      } else {
        break;
      }
    }
    if (i != _current && mounted) {
      setState(() => _current = i);
      if (_scroll.hasClients && i >= 0) {
        final target = (i * _lineHeight - _scroll.position.viewportDimension / 2 + _lineHeight / 2).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<LyricLine>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(svc.describe(snap.error!))));
        final lines = snap.data ?? const [];
        if (lines.isEmpty) return Center(child: Text(svc.s['noLyrics']));
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 160, horizontal: 24),
          itemExtent: _lineHeight,
          itemCount: lines.length,
          itemBuilder: (context, i) {
            final l = lines[i];
            final on = i == _current;
            return InkWell(
              onTap: () => svc.player.seek(Duration(milliseconds: l.start)),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(l.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: on ? 19 : 16,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                        color: on ? scheme.primary : scheme.onSurfaceVariant,
                      )),
                  if (l.translation.isNotEmpty)
                    Text(l.translation, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

class CommentsView extends StatefulWidget {
  const CommentsView({super.key, required this.track, required this.controller});
  final Track track;
  final ScrollController controller;

  @override
  State<CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends State<CommentsView> {
  final List<Comment> _comments = [];
  int _total = 0;
  bool _more = false, _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await svc.plugin(widget.track.source)!.call('comments', {'trackId': widget.track.id, 'offset': _comments.length}) as Map? ?? const {};
      final list = ((r['comments'] as List?) ?? const []).whereType<Map>().map(Comment.fromJson).toList();
      setState(() {
        _comments.addAll(list);
        _total = (r['total'] as num?)?.toInt() ?? _total;
        _more = r['more'] == true && list.isNotEmpty;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    if (_error != null && _comments.isEmpty) return Center(child: Text(svc.describe(_error!)));
    return ListView.builder(
      controller: widget.controller,
      itemCount: _comments.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return ListTile(title: Text('${s['comments']}${_total > 0 ? ' ($_total)' : ''}', style: Theme.of(context).textTheme.titleMedium));
        }
        if (i == _comments.length + 1) {
          if (_loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          if (_comments.isEmpty) return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(s['noComments'])));
          return _more ? TextButton(onPressed: _load, child: Text(s['loadMore'])) : const SizedBox(height: 24);
        }
        final c = _comments[i - 1];
        final time = c.time > 0 ? DateTime.fromMillisecondsSinceEpoch(c.time).toLocal().toString().substring(0, 16) : '';
        return ListTile(
          leading: Cover(c.avatarUrl, size: 36, round: true, icon: Icons.person),
          title: Text(c.author, style: Theme.of(context).textTheme.bodySmall),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.text, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text([time, if (c.likes > 0) '♥ ${c.likes}'].where((x) => x.isNotEmpty).join('  '), style: Theme.of(context).textTheme.labelSmall),
          ]),
        );
      },
    );
  }
}
