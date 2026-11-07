import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mygo_mobile/features/shell/shell.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'services.dart';
import 'system_insets.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// The app: MyGo's palette for the system's appearance (or the one chosen),
/// the listener's language, the adaptive shell.
class MyGoApp extends StatelessWidget {
  const MyGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: svc.app,
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: svc.s['appName'],
        debugShowCheckedModeBanner: false,
        themeMode: svc.app.themeMode,
        theme: mgTheme(MgPalette.lightPalette),
        darkTheme: mgTheme(MgPalette.darkPalette),
        locale: svc.app.language == 'zh-CN' ? const Locale('zh', 'CN') : const Locale('en'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => SystemInsets(child: PlayerShortcuts(child: child!)),
        home: const AppShell(),
      ),
    );
  }
}

/// Keyboard control of the player, for desktop browsers and keyboards on
/// tablets: Space plays or pauses, ←/→ seek 5 s, Shift+←/→ previous/next.
/// Text fields keep their keys (they handle them before these bubble up).
class PlayerShortcuts extends StatelessWidget {
  const PlayerShortcuts({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = svc.player;
    void seekBy(int seconds) {
      if (p.current.value == null) return;
      var to = p.position + Duration(seconds: seconds);
      if (to < Duration.zero) to = Duration.zero;
      final d = p.duration;
      if (d != null && to > d) to = d;
      p.seek(to);
    }

    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): () {
        if (p.current.value == null) return;
        p.playing ? p.pause() : p.play();
      },
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seekBy(-5),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => seekBy(5),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () => p.skipToPrevious(),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () => p.skipToNext(),
    };
    // Not while a text field has focus: there Space and the arrows are typing
    // (on the web a handled key event would also swallow the character).
    bool typing() => FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (typing()) return KeyEventResult.ignored;
        for (final e in bindings.entries) {
          if (e.key.accepts(event, HardwareKeyboard.instance)) {
            e.value();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
