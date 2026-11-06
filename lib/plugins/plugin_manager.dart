// The installed plugins, each running on its own isolate, and which one the
// app is showing.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../runtime/manifest.dart';
import '../runtime/plugin_host.dart';
import '../runtime/plugin_worker.dart';
import 'installer.dart';

class SignInPrompt {
  SignInPrompt(this.qr, this.text);
  final String qr, text;
}

class InstalledPlugin {
  InstalledPlugin(this.dir, this.manifest, this.origin, this.locales);
  final String dir;
  Manifest manifest;
  Origin? origin;
  Map<String, String> locales; // English -> listener's language
  PluginWorker? worker;
  String? error;
  String? latestVersion;

  String get id => manifest.id;
  bool get updateAvailable => latestVersion != null && isNewerVersion(latestVersion!, manifest.version);
  bool can(String method) => worker?.can(method) ?? false;
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
  PluginManager({required this.root, required this.prelude, required String language, required this.platform, required this.arch})
      // ignore: prefer_initializing_formals
      : _language = language;

  final String root; // app support dir
  final String prelude;
  final String platform, arch;
  String _language;

  String get pluginsDir => '$root/plugins';
  String get dataRoot => '$root/plugin-data';
  String get tmpDir => '$root/tmp';

  final List<InstalledPlugin> plugins = [];
  String? _activeId;
  final signInPrompt = ValueNotifier<SignInPrompt?>(null);
  late final Installer installer = Installer(pluginsDir: pluginsDir, tmpDir: tmpDir);

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
    Directory(pluginsDir).createSync(recursive: true);
    Directory(dataRoot).createSync(recursive: true);
    final tmp = Directory(tmpDir);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    _activeId = activeId;
    for (final d in Directory(pluginsDir).listSync().whereType<Directory>()) {
      final name = d.path.split('/').last;
      if (name.startsWith('.')) {
        d.deleteSync(recursive: true);
        continue;
      }
      await _load(d.path);
    }
    plugins.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  Map<String, String> _readLocales(String dir) {
    if (_language == 'en') return {};
    final f = File('$dir/locales/$_language.json');
    if (!f.existsSync()) return {};
    try {
      final m = jsonDecode(f.readAsStringSync());
      return m is Map ? m.map((k, v) => MapEntry('$k', '$v')) : {};
    } catch (_) {
      return {};
    }
  }

  Future<InstalledPlugin?> _load(String dir) async {
    Manifest m;
    try {
      m = Manifest.load(dir);
    } catch (e) {
      debugPrint('plugin $dir: $e');
      return null;
    }
    final p = InstalledPlugin(dir, m, Origin.read(dir), _readLocales(dir));
    plugins.removeWhere((x) => x.id == m.id);
    plugins.add(p);
    await _startWorker(p);
    return p;
  }

  Future<void> _startWorker(InstalledPlugin p) async {
    p.worker?.close();
    p.worker = null;
    p.error = null;
    try {
      final w = await PluginWorker.spawn(
          dir: p.dir, dataRoot: dataRoot, language: _language, platform: platform, arch: arch, prelude: prelude);
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
    }
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    for (final p in plugins) {
      p.locales = _readLocales(p.dir);
      await p.worker?.setLanguage(lang);
    }
    notifyListeners();
  }

  Future<void> commit(PendingInstall pending) async {
    final old = byId(pending.manifest.id);
    old?.worker?.close();
    await pending.commit(pluginsDir);
    final p = await _load('$pluginsDir/${pending.manifest.id}');
    plugins.sort((a, b) => a.name.compareTo(b.name));
    if (p != null && (_activeId == null || plugins.length == 1)) _activeId = p.id;
    notifyListeners();
  }

  Future<void> remove(InstalledPlugin p) async {
    p.worker?.close();
    final dir = Directory(p.dir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    final data = Directory('$dataRoot/${p.id}');
    if (data.existsSync()) data.deleteSync(recursive: true);
    plugins.remove(p);
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
