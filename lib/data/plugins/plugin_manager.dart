// The installed plugins, each running on its own isolate, and which one the
// app is showing.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/core/runtime/plugin_runtime.dart';
import 'package:mygo_mobile/core/storage/store.dart';

import 'installer.dart';

/// Told when plugins come and go. In the browser this registers them with
/// the relay, whose allowlist is the installed plugins' network permissions.
abstract interface class PluginRegistrar {
  /// Before an install is committed; throws to stop it (the relay refused).
  Future<void> register(Manifest manifest, Origin origin);
  Future<void> unregister(String id);

  /// At startup: make sure every installed plugin is registered.
  Future<void> sync(List<InstalledPlugin> installed);
}

class SignInPrompt {
  SignInPrompt(this.qr, this.text);
  final String qr, text;
}

class InstalledPlugin {
  InstalledPlugin(this.dir, this.manifest, this.origin, this.locales);
  final String dir; // in the Store: plugins/<id>
  Manifest manifest;
  Origin? origin;
  Map<String, String> locales; // English -> listener's language
  /// The running plugin, null if it failed to start ([error] says why).
  PluginConnection? worker;
  String? error;
  String? latestVersion;

  String get id => manifest.id;
  bool get updateAvailable => latestVersion != null && isNewerVersion(latestVersion!, manifest.version);
  bool can(String method) => worker?.can(method) ?? false;
  bool get running => worker != null;

  /// The plugin's settings (plugin.json "settings"), as saved.
  Map<String, String> get settings => worker?.settings ?? const {};

  Future<void> setSetting(String key, String value) async {
    final w = worker;
    if (w == null) throw PluginError('', error ?? 'the plugin isn\'t running');
    await w.setSetting(key, value);
  }
  String t(String text) => (locales[text]?.isNotEmpty ?? false) ? locales[text]! : text;
  String get name => t(manifest.name);

  /// The sidebar: plugin.json's navigation, or one entry for each of the
  /// app's pages the plugin can do, as the desktop app does without it.
  List<NavItem> get navigation {
    if (manifest.navigation.isNotEmpty) return manifest.navigation;
    return [
      if (can('home')) NavItem(title: '', builtin: 'home'),
      if (can('liked')) NavItem(title: '', builtin: 'liked'),
      if (can('savedAlbums')) NavItem(title: '', builtin: 'savedAlbums'),
      if (can('stations')) NavItem(title: '', builtin: 'stations'),
      if (can('shows')) NavItem(title: '', builtin: 'shows'),
    ];
  }

  Future<Object?> call(String method, [Object? params, Duration? timeout]) {
    final w = worker;
    if (w == null) return Future.error(PluginError('', error ?? 'the plugin isn\'t running'));
    return w.call(method, params, timeout);
  }
}

class PluginManager extends ChangeNotifier {
  PluginManager({
    required this.store,
    required this.prelude,
    required String language,
    required this.platform,
    required this.arch,
    required this.runtime,
    GitHubEndpoints? github,
    this.registrar,
  })  : _language = language, // ignore: prefer_initializing_formals
        _github = github; // ignore: prefer_initializing_formals

  /// How plugins run on this platform (QuickJS/FFI on Android, iOS and
  /// desktop; a Web Worker in the browser).
  final PluginRuntime runtime;

  /// Where plugins and their data are kept (a folder, or IndexedDB).
  final Store store;
  final String prelude;
  final String platform, arch;
  final PluginRegistrar? registrar;
  final GitHubEndpoints? _github;
  String _language;

  static const pluginsDir = 'plugins';
  static const dataRoot = 'plugin-data';

  final List<InstalledPlugin> plugins = [];
  String? _activeId;
  final signInPrompt = ValueNotifier<SignInPrompt?>(null);

  /// Something a plugin reported that the app should surface (the relay
  /// asking for its token again).
  final relayAuthNeeded = ValueNotifier<bool>(false);
  late final Installer installer = Installer(store: store, pluginsDir: pluginsDir, github: _github);

  InstalledPlugin? get active {
    for (final p in plugins) {
      if (p.id == _activeId) return p;
    }
    return plugins.isEmpty ? null : plugins.first;
  }

  InstalledPlugin? byId(String id) {
    for (final p in plugins) {
      if (p.id == id) return p;
    }
    return null;
  }

  void setActive(String id) {
    _activeId = id;
    notifyListeners();
  }

  String? get activeId => active?.id;

  Future<void> init({String? activeId}) async {
    await store.delete('tmp'); // 0.1.x unpacked installs there
    _activeId = activeId;
    final loaded = <InstalledPlugin>[];
    for (final name in await store.list(pluginsDir)) {
      if (name.startsWith('.')) {
        await store.delete('$pluginsDir/$name'); // an install the app didn't finish
        continue;
      }
      final p = await _read('$pluginsDir/$name');
      if (p != null) loaded.add(p);
    }
    if (registrar != null) {
      try {
        await registrar!.sync(loaded);
      } catch (e) {
        debugPrint('plugin registrar: $e');
      }
    }
    await Future.wait(loaded.map(_startWorker));
    plugins.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Future<Map<String, String>> _readLocales(String dir) async {
    if (_language == 'en') return {};
    final m = await store.readJson('$dir/locales/$_language.json');
    return m is Map ? m.map((k, v) => MapEntry('$k', '$v')) : {};
  }

  /// Reads an installed plugin (not started yet) and lists it.
  Future<InstalledPlugin?> _read(String dir) async {
    Manifest m;
    try {
      final text = await store.readString('$dir/plugin.json');
      if (text == null) return null;
      m = Manifest.parse(text, where: '$dir/plugin.json');
    } catch (e) {
      debugPrint('plugin $dir: $e');
      return null;
    }
    final p = InstalledPlugin(dir, m, await Origin.read(store, dir), await _readLocales(dir));
    plugins.removeWhere((x) => x.id == m.id);
    plugins.add(p);
    return p;
  }

  Future<void> _startWorker(InstalledPlugin p) async {
    p.worker?.close();
    p.worker = null;
    p.error = null;
    try {
      final w = await runtime.start(PluginSpec(
        dir: store.localPath(p.dir) ?? p.dir,
        dataRoot: store.localPath(dataRoot) ?? dataRoot,
        language: _language,
        platform: platform,
        arch: arch,
        prelude: prelude,
      ));
      p.worker = w;
      p.manifest = w.manifest;
      w.events.listen((e) => _onEvent(p, e));
    } catch (e) {
      p.error = '$e';
      debugPrint('plugin ${p.id}: $e');
    }
  }

  void _onEvent(InstalledPlugin p, WorkerEvent e) {
    switch (e.type) {
      case 'log':
        debugPrint('plugin ${p.id} [${e.data['level']}]: ${e.data['msg']}');
      case 'signInPrompt':
        signInPrompt.value = SignInPrompt('${e.data['qr']}', '${e.data['text']}');
      case 'openURL':
        launchUrl(Uri.parse('${e.data['url']}'), mode: LaunchMode.externalApplication);
      case 'relayAuth':
        relayAuthNeeded.value = true;
    }
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    for (final p in plugins) {
      p.locales = await _readLocales(p.dir);
      await p.worker?.setLanguage(lang);
    }
    notifyListeners();
  }

  Future<void> commit(PendingInstall pending) async {
    await registrar?.register(pending.manifest, pending.origin);
    final old = byId(pending.manifest.id);
    old?.worker?.close();
    await pending.commit(store, pluginsDir);
    final p = await _read('$pluginsDir/${pending.manifest.id}');
    if (p != null) await _startWorker(p);
    plugins.sort((a, b) => a.name.compareTo(b.name));
    if (p != null && (_activeId == null || plugins.length == 1)) _activeId = p.id;
    notifyListeners();
  }

  Future<void> remove(InstalledPlugin p) async {
    p.worker?.close();
    await store.delete(p.dir);
    await store.delete('$dataRoot/${p.id}');
    plugins.remove(p);
    try {
      await registrar?.unregister(p.id);
    } catch (e) {
      debugPrint('plugin registrar: $e');
    }
    if (_activeId == p.id) _activeId = plugins.isEmpty ? null : plugins.first.id;
    notifyListeners();
  }

  Future<void> restart(InstalledPlugin p) async {
    await _startWorker(p);
    notifyListeners();
  }

  Future<void> checkUpdates() async {
    await Future.wait(plugins.map((p) async {
      if (p.origin == null) return;
      p.latestVersion = await installer.latestVersion(p.origin!);
    }));
    notifyListeners();
  }

  @override
  void dispose() {
    for (final p in plugins) {
      p.worker?.close();
    }
    super.dispose();
  }
}
