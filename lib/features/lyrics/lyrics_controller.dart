import 'package:mygo_mobile/core/models/models.dart';

/// The line sung at [ms]: the last whose start is at or before it, or -1
/// before the first (lyrics.go Index).
int lyricIndex(List<LyricLine> lines, int ms) {
  var lo = 0, hi = lines.length - 1, at = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].start <= ms) {
      at = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return at;
}

/// How lit each word of a line is at [ms], 0 to 1 (ui_nowplaying.go: a word
/// brightens over its own time).
double wordLit(LyricWord w, int ms) {
  final len = (w.end - w.start).clamp(50, 1 << 30);
  return ((ms - w.start) / len).clamp(0.0, 1.0);
}

/// Lyrics by track, loaded once per song while the app runs.
class LyricsCache {
  LyricsCache(this._load);
  final Future<List<LyricLine>> Function(Track t) _load;
  final _byKey = <String, Future<List<LyricLine>>>{};

  Future<List<LyricLine>> of(Track t) => _byKey[t.key] ??= _load(t).catchError((Object e) {
        _byKey.remove(t.key); // try again next time
        throw e;
      });
}
