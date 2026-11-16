// A plugin's settings page: one field per plugin.json setting, drawn by
// its type (setting_fields.dart); what is saved and when is the
// controller's (data/plugins/plugin_settings.dart).
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/data/plugins/plugin_settings.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'setting_fields.dart';

class PluginSettingsPage extends StatefulWidget {
  const PluginSettingsPage({super.key, required this.plugin});
  final InstalledPlugin plugin;

  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  late final PluginSettingsController _controller = PluginSettingsController(
    defs: widget.plugin.manifest.settings,
    saved: widget.plugin.settings,
    save: widget.plugin.setSetting,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext context) async {
    final ok = await _controller.saveDrafts();
    if (!context.mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      final failed = _controller.fields.firstWhere((f) => f.failed);
      toast(context, '${svc.s['settingsSaveFailed']}: ${svc.describe(failed.error ?? '')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final p = widget.plugin;
    return MgPage(
      title: s['pluginSettings'],
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => ListView(padding: pageInsets(context), children: [
          MgHeading(s['pluginSettings'], eyebrow: p.name, compact: isCompact(context)),
          for (final f in _controller.fields) ...[
            SettingFieldView(field: f, controller: _controller, translate: p.t, strings: s),
            const SizedBox(height: 18),
          ],
          // Switches and selects save as they change; Save is for what is typed.
          if (_controller.fields.any((f) => !f.savesOnChange))
            Align(
              alignment: Alignment.centerLeft,
              child: PillButton(primary: true, label: s['save'], onTap: _controller.busy ? null : () => _save(context)),
            ),
        ]),
      ),
    );
  }
}
