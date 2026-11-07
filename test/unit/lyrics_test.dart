import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/lyrics/lyrics_controller.dart';

void main() {
  final lines = [LyricLine(start: 1000, text: 'a'), LyricLine(start: 3000, text: 'b'), LyricLine(start: 7000, text: 'c')];

  test('lyricIndex: the last line started, -1 before the first', () {
    expect(lyricIndex(lines, 0), -1);
    expect(lyricIndex(lines, 1000), 0);
    expect(lyricIndex(lines, 2999), 0);
    expect(lyricIndex(lines, 3000), 1);
    expect(lyricIndex(lines, 99999), 2);
    expect(lyricIndex(const [], 5), -1);
  });

  test('wordLit grows over the word', () {
    final w = LyricWord(1000, 2000, 'x');
    expect(wordLit(w, 500), 0);
    expect(wordLit(w, 1500), closeTo(0.5, 1e-9));
    expect(wordLit(w, 2500), 1);
  });

  test('parseLyrics reads LRC with translations', () {
    final l = parseLyrics({'lrc': '[00:01.00]hello\n[00:03.50]world', 'translation': '[00:01.00]你好'});
    expect(l.map((x) => x.text), ['hello', 'world']);
    expect(l.first.start, 1000);
    expect(l[1].start, 3500);
    expect(l.first.translation, '你好');
  });

  test('LyricsCache loads once per track and retries after a failure', () async {
    var n = 0;
    final c = LyricsCache((t) async {
      n++;
      if (n == 1) throw StateError('net');
      return lines;
    });
    final t = Track.fromJson({'id': '1', 'name': 'x'}, 'p');
    await expectLater(c.of(t), throwsStateError);
    expect(await c.of(t), lines);
    expect(await c.of(t), lines);
    expect(n, 2);
  });
}
