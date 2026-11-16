// Installing a plugin. Every way in (the Add sheet, an update, the shell's
// suggestion, a mygo-music://install-plugin link, the web app's ?install=)
// calls [installPlugin], which runs one [InstallFlow]: download, permission
// review, write, start, and a message the listener sees whatever happens,
// worded by [installErrorText]. Nothing here is per entry point.
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/app.dart' show navigatorKey;
import 'package:mygo_mobile/app/platform/platform.dart' show reportClientError;
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/data/plugins/installer.dart';
import 'package:mygo_mobile/data/relay/relay_client.dart' show RelayError;
import 'package:mygo_mobile/l10n/strings.dart';
import 'package:mygo_mobile/ui/ui.dart';

class PermissionsView extends StatelessWidget {
  const PermissionsView({super.key, required this.manifest, required this.strings, this.highlight = const []});
  final Manifest manifest;
  final S strings;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final s = strings;
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

/// Where a plugin is installed from.
sealed class InstallSource {
  const InstallSource();
}

/// A GitHub repository, as the listener or a link gives it (owner/repo or
/// a github.com address).
class GitHubSource extends InstallSource {
  const GitHubSource(this.repo);
  final String repo;
}

/// A zip file's bytes, read when the install starts.
class ZipSource extends InstallSource {
  const ZipSource(this.bytes);
  final Future<Uint8List> Function() bytes;
}

/// The install a link asks for: mygo-music://install-plugin?repo=owner/repo
/// (the desktop's link), or null for any other link.
InstallSource? installSourceFromLink(Uri uri) {
  if (uri.scheme != 'mygo-music' || uri.host != 'install-plugin') return null;
  return GitHubSource(uri.queryParameters['repo'] ?? '');
}

/// The install the web app's address asks for: ?install=owner/repo (or
/// ?repo=, as the desktop's link has it), or null when it asks for none.
InstallSource? installSourceFromQuery(Map<String, String> query) {
  final repo = query['install'] ?? query['repo'];
  return repo == null ? null : GitHubSource(repo);
}

enum InstallOutcome { installed, updated, cancelled, failed }

/// What an install shows the listener. The app's is [NavigatorInstallPresenter];
/// tests record the calls.
abstract interface class InstallPresenter {
  void showBusy(String label);
  void hideBusy();

  /// The permission review; true to go on.
  Future<bool> confirm(PendingInstall pending);

  /// The outcome, success or failure; it must be visible.
  void notify(String message, {required bool error});
}

/// The listener's words for why an install failed.
String installErrorText(Object e, S s) {
  if (e is InstallError) {
    final why = switch (e.kind) {
      InstallErrorKind.badRepo => s['installBadRepo'],
      InstallErrorKind.network => s['installNetwork'],
      InstallErrorKind.notFound => s['installNotFound'],
      InstallErrorKind.invalidPlugin => '${s['installInvalid']}: ${e.message}',
      InstallErrorKind.needsNewerApp =>
        '${s['needsNewerApp']} (${s['installNeedsVersion'].replaceAll('{need}', e.detail).replaceAll('{have}', kPluginApiVersion)})',
      InstallErrorKind.tooBig => s['installTooBig'],
      InstallErrorKind.timeout => s['installTimeout'],
      InstallErrorKind.start => '${s['installStartFailed']}: ${e.message}',
      InstallErrorKind.other => e.message,
    };
    return '${s['installFailed']}: $why';
  }
  if (e is RelayError) return '${s['installFailed']}: ${s['installRelayRefused']} (${e.message})';
  if (e is TimeoutException) return '${s['installFailed']}: ${s['installTimeout']}';
  return '${s['installFailed']}: $e';
}

/// One install, from [prepare] (download and read plugin.json) through the
/// review and [commit] (write and start). Every step ends either in the
/// plugin running or in a message through [presenter]; nothing waits forever.
class InstallFlow {
  InstallFlow({required this.prepare, required this.commit, required this.presenter, required this.strings, this.report});

  final Future<PendingInstall> Function(InstallSource source) prepare;

  /// Writes and starts it; answers why it couldn't start, or null.
  final Future<String?> Function(PendingInstall pending, void Function(String step) onStep) commit;
  final InstallPresenter presenter;
  final S Function() strings;

  /// Where failures are logged (the relay's client log on the web).
  final void Function(String step, Object error)? report;

  static const prepareLimit = Duration(minutes: 2), commitLimit = Duration(minutes: 2);

  Future<InstallOutcome> run(InstallSource source) async {
    final s = strings();
    var step = 'download';
    var busy = false;
    void hide() {
      if (busy) presenter.hideBusy();
      busy = false;
    }

    PendingInstall? pending;
    try {
      presenter.showBusy(s['downloading']);
      busy = true;
      pending = await prepare(source).timeout(prepareLimit, onTimeout: () => throw InstallError('the download took too long', kind: InstallErrorKind.timeout));
      hide();
      step = 'confirm';
      if (!await presenter.confirm(pending)) {
        pending.discard();
        return InstallOutcome.cancelled;
      }
      final m = pending.manifest;
      final isUpdate = pending.previous != null;
      step = 'commit';
      presenter.showBusy(s['installing']);
      busy = true;
      final startError = await commit(pending, (st) => step = st)
          .timeout(commitLimit, onTimeout: () => throw InstallError('the install took too long ($step)', kind: InstallErrorKind.timeout));
      hide();
      if (startError != null) {
        step = 'start';
        throw InstallError(startError, kind: InstallErrorKind.start);
      }
      presenter.notify('${isUpdate ? s['pluginUpdated'] : s['installed']}: ${m.name} ${m.version}', error: false);
      return isUpdate ? InstallOutcome.updated : InstallOutcome.installed;
    } catch (e) {
      hide();
      pending?.discard();
      debugPrint('install ($step): $e');
      report?.call(step, e);
      presenter.notify(installErrorText(e, strings()), error: true);
      return InstallOutcome.failed;
    }
  }
}

/// Shows an install on the app's root navigator: a progress dialog, the
/// permission review, and a toast for the outcome. It never needs the
/// caller's BuildContext, so a link that arrives while no page is open (or
/// before the first frame) gets the same dialogs and messages as a tap.
class NavigatorInstallPresenter implements InstallPresenter {
  NavigatorInstallPresenter(this.navigator, this.strings);
  final GlobalKey<NavigatorState> navigator;
  final S Function() strings;
  bool _busy = false;

  /// A context under the root Overlay, where dialogs and toasts go.
  BuildContext? get _context => navigator.currentState?.overlay?.context;

  @override
  void showBusy(String label) {
    final ctx = _context;
    if (ctx == null) return;
    _busy = true;
    showMgDialog<void>(
      ctx,
      dismissible: false,
      content: Row(children: [const MgSpinner(), const SizedBox(width: 16), Flexible(child: Text(label))]),
      actions: (_) => const [],
    ).whenComplete(() => _busy = false);
  }

  @override
  void hideBusy() {
    final nav = navigator.currentState;
    if (_busy && nav != null && nav.mounted) nav.pop();
    _busy = false;
  }

  @override
  Future<bool> confirm(PendingInstall pending) async {
    final ctx = _context;
    if (ctx == null) return false;
    final s = strings();
    final m = pending.manifest;
    final isUpdate = pending.previous != null;
    final yes = await showMgDialog<bool>(
      ctx,
      // Only the buttons answer: a tap beside them (a touch a little off on
      // a phone) must not quietly cancel the install.
      dismissible: false,
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
            PermissionsView(manifest: m, strings: s, highlight: pending.newHosts),
          ]);
        }),
      ),
      actions: (ctx) => [
        PillButton(label: s['cancel'], onTap: () => Navigator.pop(ctx, false)),
        PillButton(primary: true, label: isUpdate ? s['update'] : s['install'], onTap: () => Navigator.pop(ctx, true)),
      ],
    );
    return yes == true;
  }

  @override
  void notify(String message, {required bool error}) {
    final ctx = _context;
    if (ctx == null) {
      debugPrint('install: $message (no screen to show it on)');
      return;
    }
    toast(ctx, message, duration: Duration(seconds: error ? 7 : 3));
  }
}

/// Waits (a frame at a time, up to [limit]) for the root navigator to be up:
/// a link can arrive as the app starts, before its first frame.
Future<void> _navigatorReady(GlobalKey<NavigatorState> key, {Duration limit = const Duration(seconds: 15)}) async {
  final until = DateTime.now().add(limit);
  while (key.currentState?.overlay == null && DateTime.now().isBefore(until)) {
    await WidgetsBinding.instance.endOfFrame;
    if (key.currentState?.overlay == null) await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// The install running now, if one is: the next waits for it.
Future<void>? _running;

/// Builds the flow [installPlugin] runs: the app's plugins and navigator.
/// Tests swap it for one over their own installer.
@visibleForTesting
InstallFlow Function() installFlowFactory = _appInstallFlow;

InstallFlow _appInstallFlow() {
  final plugins = svc.plugins;
  return InstallFlow(
    prepare: (src) => switch (src) {
      GitHubSource(:final repo) => plugins.installer.prepareGitHub(repo),
      ZipSource(:final bytes) => bytes().then(plugins.installer.prepareZipBytes),
    },
    commit: (pending, onStep) async {
      await plugins.commit(pending, onStep: onStep);
      plugins.setActive(pending.manifest.id);
      return plugins.byId(pending.manifest.id)?.error;
    },
    presenter: NavigatorInstallPresenter(navigatorKey, () => svc.s),
    strings: () => svc.s,
    report: (step, e) => reportClientError('install', '$step: $e'),
  );
}

/// The one way to install a plugin. Installs run one after another (two
/// links in a row don't stack two reviews).
Future<InstallOutcome> installPlugin(InstallSource source) async {
  while (_running != null) {
    await _running;
  }
  final done = Completer<void>();
  _running = done.future;
  try {
    await _navigatorReady(navigatorKey);
    return await installFlowFactory().run(source);
  } finally {
    _running = null;
    done.complete();
  }
}

/// A mygo-music://install-plugin link (Android, iOS): installs what it asks
/// for; null for a link that isn't one.
Future<InstallOutcome>? installFromLink(Uri uri) {
  final source = installSourceFromLink(uri);
  return source == null ? null : installPlugin(source);
}

/// The web app's ?install= (or ?repo=): installs what it asks for; null
/// when the address asks for nothing.
Future<InstallOutcome>? installFromQuery(Map<String, String> query) {
  final source = installSourceFromQuery(query);
  return source == null ? null : installPlugin(source);
}

/// The Add sheet: from GitHub or from a zip.
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
      content: MgTextField(controller: controller, hint: s['repoHint'], icon: MgIcons.code, autofocus: true, onSubmitted: (v) => Navigator.of(context, rootNavigator: true).pop(v)),
      actions: (ctx) => [
        PillButton(label: s['cancel'], onTap: () => Navigator.pop(ctx)),
        PillButton(primary: true, label: s['install'], onTap: () => Navigator.pop(ctx, controller.text)),
      ],
    );
    if (repo != null && repo.trim().isNotEmpty) await installPlugin(GitHubSource(repo));
  } else {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return;
    await installPlugin(ZipSource(picked.readAsBytes));
  }
}
