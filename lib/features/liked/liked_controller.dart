import 'package:flutter/foundation.dart';
import 'package:mygo_mobile/core/models/models.dart';

/// Liked songs, a page at a time. [all] loads the pages not loaded yet first,
/// so "Play all" plays every liked song, not just those on screen.
class LikedController extends ChangeNotifier {
  LikedController(this._fetch, {this.onTracks});

  /// liked({offset}) of the plugin.
  final Future<TrackPage> Function(int offset) _fetch;

  /// Told of each page that arrives (the liked store marks them).
  final void Function(List<Track>)? onTracks;

  static const maxPages = 100; // a guard against a source that never says it is done

  final List<Track> tracks = [];
  bool more = false;
  Future<void>? _paging;

  Future<List<Track>> load() async {
    final r = await _fetch(0);
    tracks
      ..clear()
      ..addAll(r.tracks);
    more = r.more && r.tracks.isNotEmpty;
    onTracks?.call(r.tracks);
    notifyListeners();
    return tracks;
  }

  /// The next page; calls made while one is on its way share it.
  Future<void> loadMore() => _paging ??= () async {
        try {
          final r = await _fetch(tracks.length);
          final seen = {for (final t in tracks) t.key};
          final fresh = r.tracks.where((t) => !seen.contains(t.key)).toList();
          tracks.addAll(fresh);
          more = r.more && fresh.isNotEmpty;
          onTracks?.call(r.tracks);
          notifyListeners();
        } finally {
          _paging = null;
        }
      }();

  /// Every liked song, loading what is left first. [keep] filters (songs
  /// unliked meanwhile).
  Future<List<Track>> all({bool Function(Track)? keep}) async {
    for (var i = 0; more && i < maxPages; i++) {
      await loadMore();
    }
    return keep == null ? List.of(tracks) : tracks.where(keep).toList();
  }
}
