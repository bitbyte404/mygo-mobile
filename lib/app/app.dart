import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mygo_mobile/features/shell/shell.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'services.dart';

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
        home: const AppShell(),
      ),
    );
  }
}
