import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/ui/ui.dart';
import 'package:url_launcher/url_launcher.dart';

class PluginSettingsPage extends StatefulWidget {
  const PluginSettingsPage({super.key, required this.plugin});
  final InstalledPlugin plugin;

  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  final Map<String, TextEditingController> _c = {};

  @override
  void initState() {
    super.initState();
    for (final st in widget.plugin.manifest.settings) {
      _c[st.key] = TextEditingController(text: widget.plugin.settings[st.key] ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final p = widget.plugin;
    final pal = context.mg;
    return MgPage(
      title: s['pluginSettings'],
      child: ListView(padding: pageInsets(context), children: [
        MgHeading(s['pluginSettings'], eyebrow: p.name, compact: isCompact(context)),
        for (final st in p.manifest.settings) ...[
          Text(p.t(st.label), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.text)),
          const SizedBox(height: 6),
          MgTextField(controller: _c[st.key]!),
          if (st.help.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.t(st.help), style: TextStyle(fontSize: 12.5, color: pal.muted, height: 1.4))),
          if (st.link.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextAction(st.link, accent: true, onTap: () => launchUrl(Uri.parse(st.link), mode: LaunchMode.externalApplication)),
            ),
          const SizedBox(height: 18),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: PillButton(
            primary: true,
            label: s['save'],
            onTap: () async {
              try {
                for (final st in p.manifest.settings) {
                  final v = _c[st.key]!.text;
                  if (v != (p.settings[st.key] ?? '')) await p.setSetting(st.key, v);
                }
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) toast(context, svc.describe(e));
              }
            },
          ),
        ),
      ]),
    );
  }
}
