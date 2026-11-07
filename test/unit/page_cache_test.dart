import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/features/common/loader.dart';

void main() {
  setUp(PageCache.clear);

  Widget host(Future<String> Function() load, {Duration fresh = const Duration(minutes: 10)}) => MaterialApp(
        home: Scaffold(
          body: Loader<String>(cacheKey: 'p/home', fresh: fresh, load: load, builder: (_, v, _) => ListView(children: [Text(v)])),
        ),
      );

  testWidgets('a page opened again shows its kept data without loading', (t) async {
    var calls = 0;
    Future<String> load() async => 'v${++calls}';
    await t.pumpWidget(host(load));
    await t.pumpAndSettle();
    expect(find.text('v1'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(load));
    await t.pump();
    expect(find.text('v1'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('stale kept data shows at once and is replaced quietly', (t) async {
    var calls = 0;
    Future<String> load() async {
      final n = ++calls;
      if (n > 1) await Future<void>.delayed(const Duration(milliseconds: 200));
      return 'v$n';
    }
    await t.pumpWidget(host(load, fresh: Duration.zero));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(load, fresh: Duration.zero));
    await t.pump();
    expect(find.text('v1'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.text('v2'), findsOneWidget);
    expect(calls, 2);
  });

  test('clearing a plugin drops only its pages', () {
    PageCache.put('a/home', 1);
    PageCache.put('b/home', 2);
    PageCache.clear('a');
    expect(PageCache.get('a/home'), isNull);
    expect(PageCache.get('b/home')?.$1, 2);
  });
}
