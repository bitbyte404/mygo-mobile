// Installing a plugin: from GitHub or a zip, with the permission review.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/data/plugins/installer.dart';
import 'package:mygo_mobile/ui/ui.dart';

class PermissionsView extends StatelessWidget {
  const PermissionsView({super.key, required this.manifest, this.highlight = const []});
  final Manifest manifest;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final pal = context.mg;
    final m = manifest;
    if (m.network.isEmpty && m.process.isEmpty) return Text(s['noPermissions'], style: TextStyle(color: pal.muted));
    Widget host(String h, bool warn) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            MgIcon(MgIcons.globe, size: 14, color: warn ? pal.accent : pal.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(h == '*' ? '* (${s['anySite']})' : h, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: warn ? pal.accent : pal.text))),
          ]),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (m.network.isNotEmpty) ...[
        Text(s['network'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.muted)),
        const SizedBox(height: 6),
        for (final h in m.network) host(h, highlight.contains(h) || h == '*'),
      ],
      if (m.process.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(s['process'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.muted)),
        for (final h in m.process) Text(h, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: pal.text)),
      ],
    ]);
  }
}

Future<void> addPlugin(BuildContext context) async {
  final s = svc.s;
  final choice = await showMgSheet<String>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: Text(s['addPlugin'], style: MgType.section.copyWith(fontSize: 17, color: ctx.mg.text))),
        MgListRow(icon: MgIcons.code, label: s['fromGithub'], sub: s['repoHint'], onTap: () => Navigator.pop(ctx, 'github')),
        MgListRow(icon: MgIcons.archive, label: s['fromZip'], onTap: () => Navigator.pop(ctx, 'zip')),
      ]),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'github') {
    final controller = TextEditingController();
    final repo = await showMgDialog<String>(
      context,
      title: s['fromGithub'],
      content: MgTextField(controller: controller, hint: s['repoHint'], icon: MgIcons.code, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
      actions: (ctx) => [
        PillButton(label: s['cancel'], onTap: () => Navigator.pop(ctx)),
        PillButton(primary: true, label: s['install'], onTap: () => Navigator.pop(ctx, controller.text)),
      ],
    );
    if (repo != null && repo.trim().isNotEmpty && context.mounted) await installFromRepo(context, repo);
  } else {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null || !context.mounted) return;
    await _install(context, () async => svc.plugins.installer.prepareZipBytes(await picked.readAsBytes()));
  }
}

Future<void> installFromRepo(BuildContext context, String repo) => _install(context, () => svc.plugins.installer.prepareGitHub(repo));

Future<void> _install(BuildContext context, Future<PendingInstall> Function() prepare) async {
  final s = svc.s;
  final nav = Navigator.of(context, rootNavigator: true);
  showMgDialog<void>(
    context,
    dismissible: false,
    content: Row(children: [const MgSpinner(), const SizedBox(width: 16), Text(s['installing'])]),
    actions: (_) => const [],
  );
  PendingInstall pending;
  try {
    pending = await prepare();
  } catch (e) {
    nav.pop();
    if (!context.mounted) return;
    var msg = '$e';
    if (msg.startsWith('needsNewerApp:')) msg = '${s['needsNewerApp']} (${msg.substring(14)})';
    toast(context, msg);
    return;
  }
  nav.pop();
  if (!context.mounted) {
    pending.discard();
    return;
  }
  final m = pending.manifest;
  final isUpdate = pending.previous != null;
  final yes = await showMgDialog<bool>(
    context,
    title: isUpdate ? s['updateAsk'] : s['installAsk'],
    content: SingleChildScrollView(
      child: Builder(builder: (ctx) {
        final pal = ctx.mg;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.text)),
          const SizedBox(height: 4),
          Text('${m.id} · ${s['version']} ${isUpdate ? '${pending.previous!.version} → ' : ''}${m.version}', style: TextStyle(color: pal.muted, fontSize: 13)),
          if (pending.origin.repo.isNotEmpty) Text('github.com/${pending.origin.repo}', style: TextStyle(color: pal.muted, fontSize: 12.5)),
          const SizedBox(height: 16),
          if (pending.newHosts.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s['newPermissions'], style: TextStyle(color: pal.accent))),
          PermissionsView(manifest: m, highlight: pending.newHosts),
        ]);
      }),
    ),
    actions: (ctx) => [
      PillButton(label: s['cancel'], onTap: () => Navigator.pop(ctx, false)),
      PillButton(primary: true, label: isUpdate ? s['update'] : s['install'], onTap: () => Navigator.pop(ctx, true)),
    ],
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

