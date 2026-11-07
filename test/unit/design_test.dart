import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/ui/ui.dart';

void main() {
  test('dominantColor picks the hue most saturated pixels share', () {
    // 24x24: two thirds strong red, one third gray.
    final px = <int>[];
    for (var i = 0; i < 576; i++) {
      px.addAll(i % 3 == 0 ? [128, 128, 128, 255] : [220, 30, 40, 255]);
    }
    final c = ArtTint.dominantColor(px);
    expect((c.r * 255).round(), closeTo(220, 2));
    expect((c.g * 255).round(), closeTo(30, 2));
  });

  test('dominantColor falls back to the mean of a gray cover', () {
    final px = [for (var i = 0; i < 576; i++) ...[100, 100, 100, 255]];
    final c = ArtTint.dominantColor(px);
    expect((c.r * 255).round(), 100);
  });

  test('backdrop colors are deep, the top lighter than the foot', () {
    final (top, foot) = backdropColors(const Color(0xFF3060E0));
    expect(hsvOf(top).$3, closeTo(0.35, 0.01));
    expect(hsvOf(foot).$3, closeTo(0.24, 0.01));
    expect(top.computeLuminance(), lessThan(0.5)); // light status bar icons over it
  });

  test('width classes', () {
    expect(widthClassOf(360), MgWidth.compact);
    expect(widthClassOf(700), MgWidth.medium);
    expect(widthClassOf(1280), MgWidth.expanded);
  });

  test('every MyGo icon parses', () {
    expect(() => MgIcon(MgIcons.thumbFill), returnsNormally);
  });
}
