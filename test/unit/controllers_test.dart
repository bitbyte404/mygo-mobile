import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/liked/liked_controller.dart';
import 'package:mygo_mobile/features/search/search_controller.dart';

Track t(int i) => Track.fromJson({'id': '$i', 'name': 'song $i'}, 'p');

void main() {
  test('Play all on liked songs loads every page first', () async {
    final asked = <int>[];
    final c = LikedController((offset) async {
      asked.add(offset);
      final page = [for (var i = offset; i < offset + 30 && i < 75; i++) t(i)];
      return TrackPage(tracks: page, more: offset + 30 < 75);
    });
    await c.load();
    expect(c.tracks.length, 30);
    expect(c.more, isTrue);
    final all = await c.all();
    expect(all.length, 75);
    expect(asked, [0, 30, 60]);
    expect(c.more, isFalse);
  });

  test('loadMore calls made together share one request', () async {
    var calls = 0;
    final c = LikedController((offset) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return TrackPage(tracks: [t(offset), t(offset + 1)], more: true);
    });
    await c.load();
    await Future.wait([c.loadMore(), c.loadMore(), c.loadMore()]);
    expect(calls, 2);
    expect(c.tracks.length, 4);
  });

  test('a search cancels the pending suggestion, which never covers results', () {
    fakeAsync((async) {
      var suggested = 0;
      final c = SearchController(
        searchFn: (q, k, o) async => SearchResult(tracks: [t(1)], albums: const [], artists: const [], playlists: const [], more: false),
        suggestFn: (q) async {
          suggested++;
          return ['$q suggestion'];
        },
      );
      c.typed('周杰伦');
      async.elapse(const Duration(milliseconds: 100));
      c.search('周杰伦');
      async.elapse(const Duration(seconds: 1));
      expect(suggested, 0);
      expect(c.suggestions, isEmpty);
      expect(c.result?.tracks.length, 1);
    });
  });

  test('a suggestion already on its way when the search starts is dropped', () {
    fakeAsync((async) {
      final gate = Completer<List<String>>();
      final c = SearchController(
        searchFn: (q, k, o) async => SearchResult(tracks: [t(1)], albums: const [], artists: const [], playlists: const [], more: false),
        suggestFn: (q) => gate.future,
      );
      c.typed('晴天');
      async.elapse(const Duration(milliseconds: 400)); // the debounce fired; the call is out
      c.search('晴天');
      async.flushMicrotasks();
      gate.complete(['晴天 周杰伦']);
      async.flushMicrotasks();
      expect(c.suggestions, isEmpty);
      expect(c.loading, isFalse);
    });
  });
}
