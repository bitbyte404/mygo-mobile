import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/features/common/skeletons.dart';
import 'package:mygo_mobile/ui/ui.dart';

Widget _app(Widget child, {bool dark = false, bool still = false}) => MaterialApp(
      theme: mgTheme(dark ? MgPalette.darkPalette : MgPalette.lightPalette),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: Scaffold(body: child),
        ),
      ),
    );

void main() {
  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    for (final kind in SkeletonKind.values) {
      for (final dark in const [false, true]) {
        testWidgets('page skeleton ${kind.name} at ${size.width.toInt()} ${dark ? 'dark' : 'light'} lays out', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(_app(PageSkeleton(kind: kind), dark: dark));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(find.byType(MgBone), findsWidgets);
          expect(find.byType(MgShimmer), findsOneWidget);
        });
      }
    }
  }

  testWidgets('the sweep runs, and stops for reduced motion', (tester) async {
    await tester.pumpWidget(_app(const PageSkeleton()));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(_app(const PageSkeleton(), still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('lyrics and comment shapes lay out on the dark backdrop', (tester) async {
    await tester.pumpWidget(_app(
      ListView(children: [
        const SizedBox(height: 300, child: SkeletonLyrics()),
        MgShimmer(onDark: true, child: Column(children: [for (var i = 0; i < 4; i++) SkeletonCommentRow(index: i)])),
      ]),
      dark: true,
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.byType(SkeletonCommentRow), findsNWidgets(4));
  });

  test('skeleton colors differ between light, dark and Now Playing', () {
    final l = mgSkeletonColors(MgPalette.lightPalette);
    final d = mgSkeletonColors(MgPalette.darkPalette);
    final np = mgSkeletonColors(MgPalette.darkPalette, onDark: true);
    expect(l.base, isNot(d.base));
    expect(np.highlight.a, greaterThan(np.base.a));
  });
}
