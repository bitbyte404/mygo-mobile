import 'package:flutter/material.dart';

import '../plugins/installer.dart';
import '../services.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: svc.app,
      builder: (context, _) {
        final s = svc.s;
        final app = svc.app;
        return Scaffold(
          appBar: AppBar(title: Text(s['settings'])),
          body: ListView(children: [
            ListTile(title: Text(s['quality']), subtitle: Text(s[app.quality])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: [
                  for (final q in const ['standard', 'high', 'lossless']) ButtonSegment(value: q, label: Text(s[q])),
                ],
                selected: {app.quality},
                onSelectionChanged: (v) => app.setQuality(v.first),
              ),
            ),
            const Divider(height: 32),
            ListTile(title: Text(s['language'])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'zh-CN', label: Text('简体中文')), ButtonSegment(value: 'en', label: Text('English'))],
                selected: {app.language},
                onSelectionChanged: (v) {
                  app.setLanguage(v.first);
                  svc.plugins.setLanguage(v.first);
                },
              ),
            ),
            const Divider(height: 32),
            ListTile(title: Text(s['theme'])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(value: ThemeMode.system, label: Text(s['themeSystem'])),
                  ButtonSegment(value: ThemeMode.light, label: Text(s['themeLight'])),
                  ButtonSegment(value: ThemeMode.dark, label: Text(s['themeDark'])),
                ],
                selected: {app.themeMode},
                onSelectionChanged: (v) => app.setTheme(v.first),
              ),
            ),
            const Divider(height: 32),
            ListTile(
              title: Text(s['about']),
              subtitle: Text('${s['aboutText']}\nPlugin API: MyGo Music $kPluginApiVersion · JS: QuickJS-ng'),
              isThreeLine: true,
            ),
          ]),
        );
      },
    );
  }
}
