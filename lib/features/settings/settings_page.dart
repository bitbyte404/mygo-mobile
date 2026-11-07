import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/data/plugins/installer.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// The app's settings, as segmented controls (ui_kit.go segmented).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.back});
  final bool? back;

  @override
  Widget build(BuildContext context) {
    return MgPage(
      title: svc.s['settings'],
      back: back,
      child: ListenableBuilder(
        listenable: svc.app,
        builder: (context, _) {
          final s = svc.s;
          final app = svc.app;
          final p = context.mg;
          Widget group(MgIconData icon, String title, Widget control) => Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    MgIcon(icon, size: 17, color: p.muted),
                    const SizedBox(width: 8),
                    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.muted)),
                  ]),
                  const SizedBox(height: 10),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: control),
                ]),
              );
          return ListView(padding: pageInsets(context), children: [
            MgHeading(s['settings'], compact: isCompact(context)),
            group(
              MgIcons.sliders,
              s['quality'],
              MgSegmented<String>(
                values: const ['standard', 'high', 'lossless'],
                labels: [s['standard'], s['high'], s['lossless']],
                selected: app.quality,
                onChanged: app.setQuality,
              ),
            ),
            group(
              MgIcons.globe,
              s['language'],
              MgSegmented<String>(
                values: const ['zh-CN', 'en'],
                labels: const ['简体中文', 'English'],
                selected: app.language,
                onChanged: (v) {
                  app.setLanguage(v);
                  svc.plugins.setLanguage(v);
                },
              ),
            ),
            group(
              MgIcons.palette,
              s['theme'],
              MgSegmented<ThemeMode>(
                values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
                labels: [s['themeSystem'], s['themeLight'], s['themeDark']],
                selected: app.themeMode,
                onChanged: app.setTheme,
              ),
            ),
            group(
              MgIcons.info,
              s['about'],
              Text('${s['aboutText']}\nPlugin API: MyGo Music $kPluginApiVersion · JS: QuickJS-ng', style: TextStyle(fontSize: 13, height: 1.5, color: p.muted)),
            ),
          ]);
        },
      ),
    );
  }
}
