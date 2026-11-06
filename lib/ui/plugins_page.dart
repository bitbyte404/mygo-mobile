import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../plugins/installer.dart';
import '../plugins/plugin_manager.dart';
import '../runtime/manifest.dart';
import '../services.dart';
import 'common.dart';

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

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
    return Scaffold(
      appBar: AppBar(title: Text(s['plugins']), actions: [
        IconButton(
          tooltip: s['checkUpdates'],
          icon: _checking ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.update),
          onPressed: _checking ? null : _check,
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addPlugin(context),
        icon: const Icon(Icons.add),
        label: Text(s['addPlugin']),
      ),
      body: ListenableBuilder(
        listenable: svc.plugins,
        builder: (context, _) {
          final list = svc.plugins.plugins;
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.extension_outlined, size: 56),
                  const SizedBox(height: 12),
                  Text(s['noPlugins'], style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(s['noPluginsHint'], textAlign: TextAlign.center),
                ]),
              ),
            );
          }
          return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            for (final p in list) _PluginTile(plugin: p),
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
    final p = plugin;
    final origin = p.origin;
    final sub = [
      '${s['version']} ${p.manifest.version.isEmpty ? '-' : p.manifest.version}',
      if (origin?.kind == 'github') origin!.repo,
      if (origin?.kind == 'zip') 'zip',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.extension),
          title: Text(p.name),
          subtitle: Text(p.error != null ? '⚠ ${p.error}' : sub, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: p.updateAvailable
              ? FilledButton.tonal(onPressed: () => _update(context), child: Text('${s['update']} ${p.latestVersion}'))
              : (p.latestVersion != null ? Text(s['upToDate'], style: Theme.of(context).textTheme.bodySmall) : null),
          onTap: () => svc.plugins.setActive(p.id),
        ),
        OverflowBar(alignment: MainAxisAlignment.end, children: [
          TextButton.icon(
            icon: const Icon(Icons.shield_outlined, size: 18),
            label: Text(s['permissions']),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('${p.name} · ${s['permissions']}'),
                content: PermissionsView(manifest: p.manifest),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s['ok']))],
              ),
            ),
          ),
          if (p.manifest.settings.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.tune, size: 18),
              label: Text(s['settings']),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PluginSettingsPage(plugin: p))),
            ),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(s['remove']),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('${s['remove']} ${p.name}'),
                  content: Text(s['removeConfirm']),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s['remove'])),
                  ],
                ),
              );
              if (yes == true) await svc.plugins.remove(p);
            },
          ),
        ]),
      ]),
    );
  }

  Future<void> _update(BuildContext context) async {
    final origin = plugin.origin;
    if (origin == null || origin.kind != 'github') return;
    await installFromRepo(context, origin.repo);
  }
}

class PermissionsView extends StatelessWidget {
  const PermissionsView({super.key, required this.manifest, this.highlight = const []});
  final Manifest manifest;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final m = manifest;
    if (m.network.isEmpty && m.process.isEmpty) return Text(s['noPermissions']);
    final warn = Theme.of(context).colorScheme.error;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (m.network.isNotEmpty) ...[
        Text(s['network'], style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final h in m.network)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text('• ${h == '*' ? '* (任何网站 / any site)' : h}',
                style: TextStyle(fontFamily: 'monospace', color: highlight.contains(h) || h == '*' ? warn : null)),
          ),
      ],
      if (m.process.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(s['process'], style: Theme.of(context).textTheme.titleSmall),
        for (final h in m.process) Text('• $h', style: const TextStyle(fontFamily: 'monospace')),
      ],
    ]);
  }
}

Future<void> addPlugin(BuildContext context) async {
  final s = svc.s;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.code), title: Text(s['fromGithub']), onTap: () => Navigator.pop(ctx, 'github')),
        ListTile(leading: const Icon(Icons.folder_zip_outlined), title: Text(s['fromZip']), onTap: () => Navigator.pop(ctx, 'zip')),
      ]),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'github') {
    final controller = TextEditingController();
    final repo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s['fromGithub']),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: s['repoHint'], labelText: 'GitHub'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s['cancel'])),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(s['install'])),
        ],
      ),
    );
    if (repo != null && repo.trim().isNotEmpty && context.mounted) await installFromRepo(context, repo);
  } else {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null || !context.mounted) return;
    await _install(context, () async => svc.plugins.installer.prepareZipBytes(await picked.readAsBytes()));
  }
}

Future<void> installFromRepo(BuildContext context, String repo) =>
    _install(context, () => svc.plugins.installer.prepareGitHub(repo));

Future<void> _install(BuildContext context, Future<PendingInstall> Function() prepare) async {
  final s = svc.s;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 20), Text(s['installing'])])),
  );
  PendingInstall pending;
  try {
    pending = await prepare();
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context);
    var msg = '$e';
    if (msg.startsWith('needsNewerApp:')) msg = '${s['needsNewerApp']} (${msg.substring(14)})';
    toast(context, msg);
    return;
  }
  if (!context.mounted) {
    pending.discard();
    return;
  }
  Navigator.pop(context);
  final m = pending.manifest;
  final isUpdate = pending.previous != null;
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isUpdate ? s['updateAsk'] : s['installAsk']),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.name, style: Theme.of(ctx).textTheme.titleLarge),
          Text('${m.id} · ${s['version']} ${isUpdate ? '${pending.previous!.version} → ' : ''}${m.version}'),
          if (pending.origin.repo.isNotEmpty) Text('github.com/${pending.origin.repo}', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (pending.newHosts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(s['newPermissions'], style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          Text(s['permissions'], style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 4),
          PermissionsView(manifest: m, highlight: pending.newHosts),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isUpdate ? s['update'] : s['install'])),
      ],
    ),
  );
  if (yes != true) {
    pending.discard();
    return;
  }
  try {
    await svc.plugins.commit(pending);
    svc.plugins.setActive(m.id);
    if (context.mounted) toast(context, '${s['installed']}: ${m.name} ${m.version}');
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

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
      _c[st.key] = TextEditingController(text: widget.plugin.worker?.settings[st.key] ?? '');
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
    return Scaffold(
      appBar: AppBar(title: Text('${p.name} · ${s['pluginSettings']}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final st in p.manifest.settings) ...[
          TextField(
            controller: _c[st.key],
            decoration: InputDecoration(labelText: p.t(st.label), helperText: st.help.isEmpty ? null : p.t(st.help), helperMaxLines: 4, border: const OutlineInputBorder()),
          ),
          if (st.link.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => launchUrl(Uri.parse(st.link), mode: LaunchMode.externalApplication),
                child: Text(st.link, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: () async {
            try {
              for (final st in p.manifest.settings) {
                final v = _c[st.key]!.text;
                if (v != (p.worker?.settings[st.key] ?? '')) await p.worker?.setSetting(st.key, v);
              }
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) toast(context, svc.describe(e));
            }
          },
          child: Text(s['save']),
        ),
      ]),
    );
  }
}
