import 'package:flutter/foundation.dart';
import 'package:mygo_mobile/core/models/models.dart';

import 'music_repository.dart';

/// What the app knows of liked songs, by track key (source:id), shared by
/// every list that shows a heart. Liking is optimistic and rolls back on error.
class LikedStore {
  LikedStore(this._music);
  final MusicRepository _music;

  final liked = ValueNotifier<Map<String, bool>>({});

  bool? isLiked(Track t) => liked.value[t.key];

  void mark(Iterable<Track> tracks, bool on) => _set({for (final t in tracks) t.key: on});

  void _set(Map<String, bool> m) => liked.value = {...liked.value, ...m};

  /// Asks the source which of these it has liked.
  Future<void> refresh(String source, List<Track> tracks) async {
    if (!_music.can(source, 'isLiked') || tracks.isEmpty) return;
    try {
      final r = await _music.isLiked(source, tracks.map((t) => t.id).toList());
      _set({for (final e in r.entries) '$source:${e.key}': e.value});
    } catch (e) {
      debugPrint('isLiked: $e');
    }
  }

  Future<void> setLiked(Track t, bool on) async {
    final before = liked.value[t.key];
    _set({t.key: on});
    try {
      await _music.like(t.source, t, on);
    } catch (e) {
      _set({t.key: before ?? !on});
      rethrow;
    }
  }
}
