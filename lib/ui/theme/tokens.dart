// MyGo Music's design tokens, adapted to a phone. Every value here is taken
// from the desktop app's source (egoist/mygo-music 0.1.18) unless marked
// "mobile": see docs/DESIGN.md for where each one comes from.
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// The app's colors for one appearance (internal/app/ui_kit.go `paletteFor`).
@immutable
class MgPalette extends ThemeExtension<MgPalette> {
  const MgPalette({
    required this.dark,
    required this.bg,
    required this.sidebar,
    required this.text,
    required this.muted,
    required this.faint,
    required this.hairline,
    required this.hover,
    required this.press,
    required this.accent,
    required this.onAccent,
    required this.cardShade,
    required this.popover,
    required this.popoverEdge,
  });

  final bool dark;
  final Color bg; // the content's background
  final Color sidebar; // under the sidebar; mobile: also sheets, the mini player and the tab bar
  final Color text, muted, faint;
  final Color hairline, hover, press;
  final Color accent, onAccent;
  final Color cardShade;
  final Color popover, popoverEdge; // ui_player.go popoverColors

  static const darkPalette = MgPalette(
    dark: true,
    bg: Color(0xFF141416),
    sidebar: Color(0xFF1C1C1F),
    text: Color(0xFFF5F5F7),
    muted: Color.fromRGBO(235, 235, 245, 0.56),
    faint: Color.fromRGBO(235, 235, 245, 0.3),
    hairline: Color.fromRGBO(255, 255, 255, 0.07),
    hover: Color.fromRGBO(255, 255, 255, 0.06),
    press: Color.fromRGBO(255, 255, 255, 0.1),
    accent: Color(0xFFF45058), // oklch(0.66 0.2 22)
    onAccent: Color(0xFFFFFFFF),
    cardShade: Color.fromRGBO(0, 0, 0, 0.45),
    popover: Color(0xFF2B2B2E),
    popoverEdge: Color.fromRGBO(255, 255, 255, 0.14),
  );

  static const lightPalette = MgPalette(
    dark: false,
    bg: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF4F4F6),
    text: Color(0xFF1D1D1F),
    muted: Color.fromRGBO(60, 60, 67, 0.62),
    faint: Color.fromRGBO(60, 60, 67, 0.32),
    hairline: Color.fromRGBO(0, 0, 0, 0.07),
    hover: Color.fromRGBO(0, 0, 0, 0.04),
    press: Color.fromRGBO(0, 0, 0, 0.08),
    accent: Color(0xFFE2333C), // oklch(0.6 0.21 24)
    onAccent: Color(0xFFFFFFFF),
    cardShade: Color.fromRGBO(0, 0, 0, 0.16),
    popover: Color(0xFFF6F6F6),
    popoverEdge: Color.fromRGBO(0, 0, 0, 0.12),
  );

  /// `hover.Over(bg)`: the fill of a secondary pill (ui_pages.go playButtons).
  Color get secondaryFill => Color.alphaBlend(hover, bg);

  /// Accent under the finger: darker in light mode, lighter in dark, as
  /// ui_kit.go useAccent mixes it.
  Color get accentPressed => dark ? Color.lerp(accent, Colors.white, 0.15)! : Color.lerp(accent, Colors.black, 0.2)!;

  @override
  MgPalette copyWith({Color? accent, Color? bg}) => MgPalette(
        dark: dark,
        bg: bg ?? this.bg,
        sidebar: sidebar,
        text: text,
        muted: muted,
        faint: faint,
        hairline: hairline,
        hover: hover,
        press: press,
        accent: accent ?? this.accent,
        onAccent: onAccent,
        cardShade: cardShade,
        popover: popover,
        popoverEdge: popoverEdge,
      );

  @override
  MgPalette lerp(MgPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MgPalette(
      dark: t < 0.5 ? dark : other.dark,
      bg: l(bg, other.bg),
      sidebar: l(sidebar, other.sidebar),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      hairline: l(hairline, other.hairline),
      hover: l(hover, other.hover),
      press: l(press, other.press),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      cardShade: l(cardShade, other.cardShade),
      popover: l(popover, other.popover),
      popoverEdge: l(popoverEdge, other.popoverEdge),
    );
  }
}

extension MgContext on BuildContext {
  MgPalette get mg => Theme.of(this).extension<MgPalette>() ?? MgPalette.darkPalette;
}

/// Liked Songs' cover: oklch(0.72 0.17 10) to oklch(0.58 0.22 350) at 135°
/// (ui_pages.go likedPage).
const likedGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFB718C), Color(0xFFD0268C)],
);

/// The lossless badge's gold (ui_nowplaying.go qualityBadge).
const losslessGold = Color(0xFFF5D58A);

/// Now Playing's base under the artwork colors (ui_nowplaying.go).
const npBase = Color(0xFF0B0B0D);

/// Type sizes, weights and tracking (letterSpacing) from the desktop pages.
class MgType {
  MgType._();
  // Page heading (ui_pages.go heading): 30/700, -0.6; its line above 12/600 +0.4.
  static const heading = TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.2);
  static const headingCompact = TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.2); // mobile
  static const eyebrow = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4);
  // Section (ui_pages.go section): 19/700, -0.3.
  static const section = TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3);
  // Playlist header title: 30/800, -0.6, line height 1.2.
  static const pageTitle = TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.2);
  static const pageTitleCompact = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.2); // mobile
  // Track row: name 14/500, artists 12.5, number 13 tabular, time 12.5 tabular.
  static const rowTitle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
  static const rowSub = TextStyle(fontSize: 12.5);
  static const tnum = [FontFeature.tabularFigures()];
  // Card: name 13/500 line height 1.35, line under it 12.
  static const cardTitle = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.35);
  static const cardSub = TextStyle(fontSize: 12);
  // Sidebar entry: 13.5/500.
  static const nav = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500);
  // Player bar: title 13.5/600, artists 12, times 10.5 tabular.
  static const barTitle = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);
  static const barSub = TextStyle(fontSize: 12);
  static const barTime = TextStyle(fontSize: 10.5, fontFeatures: tnum);
  // Pill button label 14/600.
  static const pill = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  // Now Playing: title 22/700 -0.3, artists 15, times 11 tabular, tab 13/600.
  static const npTitle = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3);
  static const npArtist = TextStyle(fontSize: 15);
  static const npTime = TextStyle(fontSize: 11, fontFeatures: tnum);
  static const npTab = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  // Lyrics: 30/800, line height 1.25, -0.4; translation 17/600 (ui_nowplaying.go lyricsPane).
  static const lyric = TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.4);
  static const lyricCompact = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.4); // mobile
  static const lyricTranslation = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
  static const badge = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6);
}

/// Corner radii (DIPs).
class MgRadius {
  MgRadius._();
  static const card = 10.0; // coverCardWith art
  static const header = 14.0; // playlist header cover
  static const row = 10.0; // trackRow
  static const rowCover = 6.0; // a cover in a row
  static const queueRow = 12.0; // Now Playing queue row, lyric line
  static const barCover = 8.0; // npFromRadius: the player bar's cover
  static const nav = 8.0; // sidebar entry
  static const popover = 12.0;
  static const pill = 999.0;
  static const npCover = 14.0; // mobile: Now Playing's cover (desktop: ui_cover.go)
  static const sheet = 20.0; // mobile
}

/// Sizes and spacing.
class MgSize {
  MgSize._();
  static const sidebarWidth = 232.0;
  static const railWidth = 76.0; // mobile: medium width
  static const playerBarHeight = 84.0;
  static const pagePad = 40.0; // desktop page padding
  static const pagePadCompact = 16.0; // mobile
  static const pageGap = 12.0;
  static const rowHeight = 54.0; // desktop track row
  static const rowHeightCompact = 60.0; // mobile: a 48dp touch target and room to breathe
  static const cardMin = 168.0; // the least card width of a grid (ui_pages.go homePage)
  static const cardMinCompact = 136.0; // mobile
  static const gridGapX = 20.0, gridGapY = 28.0;
  static const navItemHeight = 34.0;
  static const miniPlayerHeight = 60.0; // mobile
  static const tabBarHeight = 56.0; // mobile
  static const headerCover = 212.0;
}

/// Window-size classes, as Material's: compact < 600 ≤ medium < 840 ≤ expanded.
enum MgWidth { compact, medium, expanded }

MgWidth widthClassOf(double w) => w >= 840 ? MgWidth.expanded : (w >= 600 ? MgWidth.medium : MgWidth.compact);

/// Durations and curves. MyGo animates with springs given as a duration and a
/// bounce (SwiftUI-style), which Flutter has as SpringDescription.withDurationAndBounce.
class MgMotion {
  MgMotion._();
  static const hover = Duration(milliseconds: 120); // background color under the finger/pointer
  static const rowBg = Duration(milliseconds: 100); // track row background
  static const artFade = Duration(milliseconds: 320); // artwork fading in over its placeholder
  static const reveal = Duration(milliseconds: 200); // controls fading in/out
  static const edge = Duration(milliseconds: 180); // the scroll edge under the top bar
  static const lineFade = Duration(milliseconds: 380); // a lyric line dimming / lighting
  static const backdropFade = Duration(milliseconds: 700); // another song's backdrop
  static const npFade = Duration(milliseconds: 200); // Now Playing with reduced motion
  static const page = Duration(milliseconds: 360); // mobile: page push (website --ease)
  static const tab = Duration(milliseconds: 180); // switching tabs: a cross-fade in place

  /// The website's `--ease: cubic-bezier(0.22, 1, 0.36, 1)` (website/src/styles.css).
  static const ease = Cubic(0.22, 1, 0.36, 1);

  /// The website's `--spring: cubic-bezier(0.34, 1.56, 0.64, 1)`.
  static const springCurve = Cubic(0.34, 1.56, 0.64, 1);

  /// npSpring: Now Playing growing out of the bar's cover, 440 ms, no bounce.
  static final npSpring = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 440));

  /// The play/pause icon swap: 340 ms, bounce 0.3.
  static final playPauseSpring = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 340), bounce: 0.3);

  /// A lyric line growing to full size as it is sung: 600 ms, bounce 0.1.
  static final lineSpring = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 600), bounce: 0.1);

  /// The segmented control's capsule: 280 ms, bounce 0.08.
  static final segmentSpring = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 280), bounce: 0.08);

  /// MyGo's `ui.Snappy` pose spring (press scale, card lift). Its exact
  /// parameters live in the MyGo framework, not in this repository; a short,
  /// barely bouncing spring is used in its place.
  static final snappy = SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 240), bounce: 0.15);

  /// The lyrics' glide to the line sung: a critically damped spring of ω = 10
  /// (ui_nowplaying.go lyricOmega), i.e. stiffness ω², damping 2ω for mass 1.
  static const lyricGlide = SpringDescription(mass: 1, stiffness: 100, damping: 20);

  /// Where the line sung settles: 30% of the way down the lyrics.
  static const lyricAnchor = 0.3;
}

/// A spring stepping [from] to [to] as a Curve over [duration], for implicit
/// animations that take a Curve (the spring is sampled; settle time = duration).
class SpringCurve extends Curve {
  const SpringCurve(this.spring);
  final SpringDescription spring;

  @override
  double transformInternal(double t) {
    final sim = SpringSimulation(spring, 0, 1, 0);
    return sim.x(t * spring.duration.inMicroseconds / 1e6);
  }
}

double smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double rubberband(double offset, double dimension, [double c = 0.55]) {
  // UIKit's rubber band: offset grows ever more slowly past the edge.
  final sign = offset.sign;
  final x = offset.abs();
  return sign * (1 - 1 / (x * c / dimension + 1)) * dimension;
}

double lerpD(double a, double b, double t) => lerpDouble(a, b, t)!;

/// HSV of a color: hue in degrees, saturation and value 0-1 (artwork.go hsv).
(double, double, double) hsvOf(Color c) {
  final r = c.r, g = c.g, b = c.b;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  if (mx == 0) return (0, 0, 0);
  final d = mx - mn;
  var h = 0.0;
  if (d != 0) {
    if (mx == r) {
      h = ((g - b) / d % 6) * 60;
    } else if (mx == g) {
      h = ((b - r) / d + 2) * 60;
    } else {
      h = ((r - g) / d + 4) * 60;
    }
  }
  if (h < 0) h += 360;
  return (h, d / mx, mx);
}

Color hsvColor(double h, double s, double v) => HSVColor.fromAHSV(1, h % 360, s.clamp(0, 1), v.clamp(0, 1)).toColor();

/// Now Playing's backdrop gradient for an artwork's tint, top and foot
/// (backdrop.go backdropColors).
(Color, Color) backdropColors(Color tint) {
  final (h, s0, _) = hsvOf(tint);
  var s = s0;
  if (s > 0.12) s = math.min(math.max(s * 1.3, 0.45), 0.66);
  return (hsvColor(h, s, 0.35), hsvColor(h, math.min(s * 1.05, 0.7), 0.24));
}
