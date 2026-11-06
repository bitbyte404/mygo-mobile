import 'package:flutter/material.dart';

import '../models.dart';
import '../runtime/plugin_host.dart';
import '../services.dart';
import 'detail_pages.dart';
import 'me_page.dart';
import 'plugins_page.dart';

String fmtDuration(Duration d) {
  final m = d.inMinutes, s = d.inSeconds % 60;
  if (m >= 60) return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}

class Cover extends StatelessWidget {
  const Cover(this.url, {super.key, this.size = 48, this.radius = 6, this.round = false, this.icon = Icons.music_note});
  final String url;
  final double size, radius;
  final bool round;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(icon, size: size * 0.45, color: scheme.onSurfaceVariant),
    );
    final img = url.isEmpty
        ? fallback
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 1200),
            errorBuilder: (_, _, _) => fallback,
            loadingBuilder: (c, child, p) => p == null ? child : fallback,
          );
    return ClipRRect(borderRadius: BorderRadius.circular(round ? size / 2 : radius), child: img);
  }
}

/// Loads what a page shows each time it opens (unlike the desktop's cache),
/// with pull-to-refresh, and an error view that knows sign-in and settings.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.pluginId});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T value, Future<void> Function() refresh) builder;
  final String? pluginId;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> _refresh() async {
    final f = widget.load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorView(error: snap.error!, onRetry: _refresh, pluginId: widget.pluginId);
        }
        return RefreshIndicator(onRefresh: _refresh, child: widget.builder(context, snap.data as T, _refresh));
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.pluginId});
  final Object error;
  final VoidCallback? onRetry;
  final String? pluginId;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final code = error is PluginError ? (error as PluginError).code : '';
    final p = pluginId == null ? null : svc.plugin(pluginId!);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Icon(code == PluginError.signIn ? Icons.lock_outline : Icons.error_outline, size: 48),
        const SizedBox(height: 16),
        Text(svc.describe(error), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
          if (code == PluginError.signIn && p != null)
            FilledButton(
              onPressed: () async {
                final ok = await signIn(context, p);
                if (ok) onRetry?.call();
              },
              child: Text(s['signIn']),
            ),
          if (code == PluginError.setup && p != null)
            FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PluginSettingsPage(plugin: p))),
              child: Text(s['openSettings']),
            ),
          if (onRetry != null) OutlinedButton(onPressed: onRetry, child: Text(s['retry'])),
        ]),
      ],
    );
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, required this.onTap, this.index, this.showCover = true, this.trailing});
  final Track track;
  final VoidCallback onTap;
  final int? index;
  final bool showCover;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Track?>(
      valueListenable: svc.player.current,
      builder: (context, cur, _) {
        final playing = cur?.key == track.key;
        final sub = [track.artistNames, if (track.album.name.isNotEmpty) track.album.name].join(' · ');
        return ListTile(
          enabled: !track.unavailable,
          onTap: onTap,
          leading: showCover
              ? Cover(track.album.imageUrl, size: 44)
              : SizedBox(width: 32, child: Center(child: Text('${(index ?? 0) + 1}', style: TextStyle(color: scheme.onSurfaceVariant)))),
          title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: playing ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w600) : null),
          subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: trailing ??
              IconButton(icon: const Icon(Icons.more_vert), onPressed: () => showTrackMenu(context, track)),
          onLongPress: () => showTrackMenu(context, track),
        );
      },
    );
  }
}

Future<void> showTrackMenu(BuildContext context, Track t) async {
  final s = svc.s;
  final p = svc.plugin(t.source);
  await svc.refreshLiked(t.source, [t]);
  if (!context.mounted) return;
  final liked = svc.isLiked(t) ?? false;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Cover(t.album.imageUrl, size: 44),
          title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(t.artistNames, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.playlist_play),
          title: Text(s['playNext']),
          onTap: () {
            Navigator.pop(ctx);
            svc.player.addNext(t);
          },
        ),
        ListTile(
          leading: const Icon(Icons.queue_music),
          title: Text(s['addToQueue']),
          onTap: () {
            Navigator.pop(ctx);
            svc.player.addToQueue(t);
          },
        ),
        if (p != null && p.can('like'))
          ListTile(
            leading: Icon(liked ? Icons.favorite : Icons.favorite_border),
            title: Text(liked ? s['unlike'] : s['like']),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await svc.setLiked(t, !liked);
              } catch (e) {
                if (context.mounted) toast(context, svc.describe(e));
              }
            },
          ),
        if (p != null && p.can('album') && t.album.id.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.album),
            title: Text('${s['viewAlbum']}: ${t.album.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(pluginId: t.source, album: t.album)));
            },
          ),
        if (p != null && p.can('artist'))
          for (final a in t.artists.where((a) => a.id.isNotEmpty))
            ListTile(
              leading: const Icon(Icons.person),
              title: Text('${s['viewArtist']}: ${a.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(pluginId: t.source, artist: a)));
              },
            ),
      ]),
    ),
  );
}

/// A list of tracks with "play all" / "shuffle" on top.
class TrackListView extends StatelessWidget {
  const TrackListView({super.key, required this.tracks, this.header, this.onLoadMore, this.more = false, this.numbered = false});
  final List<Track> tracks;
  final Widget? header;
  final VoidCallback? onLoadMore;
  final bool more;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: tracks.length + 2 + (more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == 0) return header ?? const SizedBox.shrink();
        if (i == 1) {
          if (tracks.isEmpty) return Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(s['nothing'])));
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(children: [
              FilledButton.icon(
                onPressed: () => svc.player.playTracks(tracks),
                icon: const Icon(Icons.play_arrow),
                label: Text('${s['playAll']} (${tracks.length})'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => svc.player.playTracks(tracks, start: -1, shuffled: true),
                icon: const Icon(Icons.shuffle),
                label: Text(s['shuffle']),
              ),
            ]),
          );
        }
        final k = i - 2;
        if (k == tracks.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: TextButton(onPressed: onLoadMore, child: Text(s['loadMore']))),
          );
        }
        return TrackTile(
          track: tracks[k],
          index: k,
          showCover: !numbered,
          onTap: () => svc.player.playTracks(tracks, start: k),
        );
      },
    );
  }
}

/// A page header: big cover, title, subtitle, description.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle = '', this.imageUrl = '', this.description = '', this.round = false, this.actions = const []});
  final String title, subtitle, imageUrl, description;
  final bool round;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (imageUrl.isNotEmpty || round) ...[
            Cover(imageUrl, size: 120, radius: 10, round: round, icon: round ? Icons.person : Icons.album),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: tt.headlineSmall, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: tt.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              if (actions.isNotEmpty) Row(children: actions),
            ]),
          ),
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(description, style: tt.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}

/// A horizontal row of cards.
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.children, this.height = 190});
  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.title, this.subtitle = '', this.imageUrl = '', this.round = false, this.icon = Icons.album, required this.onTap});
  final String title, subtitle, imageUrl;
  final bool round;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: 130,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Column(crossAxisAlignment: round ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
          Cover(imageUrl, size: 130, radius: 8, round: round, icon: icon),
          const SizedBox(height: 6),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodyMedium, textAlign: round ? TextAlign.center : TextAlign.start),
          if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.onMore});
  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
        if (onMore != null) TextButton(onPressed: onMore, child: Text(svc.s['more'])),
      ]),
    );
  }
}
