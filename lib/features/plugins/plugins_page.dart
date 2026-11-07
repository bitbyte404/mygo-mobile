// Installed plugins: which is active, updates, permissions, settings, removal.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'install_flow.dart';
import 'plugin_settings_page.dart';

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key, this.back});
  final bool? back;

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await svc.plugins.checkUpdates();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final pal = context.mg;
    return MgPage(
      title: s['plugins'],
      back: widget.back,
      actions: [
        _checking
            ? const SizedBox(width: 44, height: 44, child: Center(child: MgSpinner(size: 18)))
            : MgIconButton(MgIcons.refresh, key: const ValueKey('check-updates'), size: 19, color: pal.text, tooltip: s['checkUpdates'], onTap: _check),
        MgIconButton(MgIcons.plus, size: 21, color: pal.text, tooltip: s['addPlugin'], onTap: () => addPlugin(context)),
      ],
      child: ListenableBuilder(
        listenable: svc.plugins,
        builder: (context, _) {
          final list = svc.plugins.plugins;
          return ListView(padding: pageInsets(context), children: [
            MgHeading(s['plugins'], compact: isCompact(context)),
            if (list.isEmpty)
              MgEmpty(icon: MgIcons.plug, title: s['noPlugins'], message: s['noPluginsHint'], actions: [
                PillButton(primary: true, icon: MgIcons.plus, label: s['addPlugin'], onTap: () => addPlugin(context)),
              ]),
            for (final p in list) _PluginTile(plugin: p),
            if (list.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: PillButton(icon: MgIcons.plus, label: s['addPlugin'], onTap: () => addPlugin(context))),
            ],
          ]);
        },
      ),
    );
  }
}

class _PluginTile extends StatelessWidget {
  const _PluginTile({required this.plugin});
  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final pal = context.mg;
    final p = plugin;
    final origin = p.origin;
    final active = svc.plugins.active?.id == p.id;
    final sub = [
      '${s['version']} ${p.manifest.version.isEmpty ? '-' : p.manifest.version}',
      if (origin?.kind == 'github') origin!.repo,
      if (origin?.kind == 'zip') 'zip',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        onTap: () => svc.plugins.setActive(p.id),
        pressedScale: 0.985,
        color: pal.hover,
        pressedColor: pal.press,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: active ? pal.accent : pal.press, borderRadius: BorderRadius.circular(12)),
              child: Center(child: MgIcon(MgIcons.plug, size: 22, color: active ? pal.onAccent : pal.text)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text))),
                  if (active) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: pal.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                      child: Text(s['inUse'], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: pal.accent)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(p.error != null ? '⚠ ${p.error}' : sub, maxLines: 3, overflow: TextOverflow.ellipsis, style: MgType.rowSub.copyWith(color: p.error != null ? pal.accent : pal.muted)),
              ]),
            ),
            if (p.updateAvailable)
              PillButton(primary: true, height: 32, label: '${s['update']} ${p.latestVersion}', onTap: () => _update(context))
            else if (p.latestVersion != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                MgIcon(MgIcons.check, size: 14, color: pal.muted),
                const SizedBox(width: 4),
                Text(s['upToDate'], style: TextStyle(fontSize: 12, color: pal.muted)),
              ]),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 2, children: [
            TextAction(s['permissions'], onTap: () => showMgDialog<void>(
                  context,
                  title: '${p.name} · ${s['permissions']}',
                  content: SingleChildScrollView(child: PermissionsView(manifest: p.manifest)),
                  actions: (ctx) => [PillButton(primary: true, label: s['ok'], onTap: () => Navigator.pop(ctx))],
                )),
            if (p.manifest.settings.isNotEmpty) TextAction(s['settings'], onTap: () => pushPage(context, PluginSettingsPage(plugin: p))),
            TextAction(s['remove'], accent: true, onTap: () async {
              final yes = await showMgConfirm(context, title: '${s['remove']} ${p.name}', message: s['removeConfirm'], ok: s['remove'], cancel: s['cancel']);
              if (yes) await svc.plugins.remove(p);
            }),
          ]),
        ]),
      ),
    );
  }

  Future<void> _update(BuildContext context) async {
    final origin = plugin.origin;
    if (origin == null || origin.kind != 'github') return;
    await installFromRepo(context, origin.repo);
  }
}

