// The Flutter ThemeData that carries MyGo's palette. Material is only the
// plumbing here (Navigator, text selection, dialogs' barrier): ripples are
// off, every visible control is drawn by lib/ui/kit.dart.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

export 'icons.dart';
export 'tokens.dart';

ThemeData mgTheme(MgPalette p) {
  final base = p.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final scheme = ColorScheme(
    brightness: p.dark ? Brightness.dark : Brightness.light,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    error: p.accent,
    onError: p.onAccent,
    surface: p.bg,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerHighest: p.sidebar,
    surfaceContainerHigh: p.sidebar,
    surfaceContainer: p.sidebar,
    outline: p.faint,
    outlineVariant: p.hairline,
  );
  final text = base.textTheme.apply(bodyColor: p.text, displayColor: p.text);
  return base.copyWith(
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: p.hover,
    focusColor: p.press,
    dividerColor: p.hairline,
    textTheme: text,
    iconTheme: IconThemeData(color: p.text, size: 20),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: 0.3), // useAccent: t.Selection = accent at 0.3
      selectionHandleColor: p.accent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.popoverEdge, width: 0.5)),
      titleTextStyle: MgType.section.copyWith(color: p.text, fontSize: 17),
      contentTextStyle: TextStyle(fontSize: 14, color: p.text, height: 1.45),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.popover,
      contentTextStyle: TextStyle(color: p.text, fontSize: 13.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.popoverEdge, width: 0.5)),
      elevation: 0,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.muted, linearTrackColor: p.press, circularTrackColor: Colors.transparent),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: MgPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: MgPageTransitionsBuilder(),
      TargetPlatform.macOS: MgPageTransitionsBuilder(),
      TargetPlatform.windows: MgPageTransitionsBuilder(),
    }),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent, elevation: 0, modalElevation: 0),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.popover, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.popoverEdge, width: 0.5)),
      textStyle: TextStyle(color: p.text, fontSize: 12),
    ),
  );
}

SystemUiOverlayStyle mgOverlay(bool darkContent) => SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      statusBarIconBrightness: darkContent ? Brightness.dark : Brightness.light,
      statusBarBrightness: darkContent ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: darkContent ? Brightness.dark : Brightness.light,
    );

/// A page comes in from a little to the right while fading in, on the
/// website's ease (cubic-bezier(0.22, 1, 0.36, 1)); the page under it drifts
/// left and dims slightly. Cheap: one opacity and one translation each.
class MgPageTransitionsBuilder extends PageTransitionsBuilder {
  const MgPageTransitionsBuilder();

  @override
  Duration get transitionDuration => MgMotion.page;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final inT = CurvedAnimation(parent: animation, curve: MgMotion.ease, reverseCurve: MgMotion.ease.flipped);
    final outT = CurvedAnimation(parent: secondaryAnimation, curve: MgMotion.ease, reverseCurve: MgMotion.ease.flipped);
    return AnimatedBuilder(
      animation: Listenable.merge([inT, outT]),
      child: child,
      builder: (context, child) {
        final w = MediaQuery.sizeOf(context).width;
        final dx = (1 - inT.value) * 0.18 * w - outT.value * 0.06 * w;
        return Opacity(
          opacity: (inT.value * 1.4).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
    );
  }
}
