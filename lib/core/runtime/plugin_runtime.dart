// The platform interface for running plugins. The app (lib/data) talks only
// to these types; how a plugin's JavaScript actually runs is the
// implementation's business:
//   - QuickJsRuntime (lib/core/runtime/quickjs): QuickJS-ng through dart:ffi,
//     one background isolate per plugin. Android, iOS, desktop, tests.
//   - web (lib/core/runtime/web): not implemented yet; a browser build would run
//     the plugin in a Worker with the host API in JS, and relay fetch through a
//     proxy for CORS. See docs/ARCHITECTURE.md.
import 'package:mygo_mobile/core/plugin/manifest.dart';

export 'package:mygo_mobile/core/errors.dart';

/// Something a running plugin wants the app to do or show: 'log',
/// 'signInPrompt' {qr, text}, 'openURL' {url}.
class WorkerEvent {
  WorkerEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

/// What a runtime needs to start a plugin.
class PluginSpec {
  const PluginSpec({required this.dir, required this.dataRoot, required this.language, required this.platform, required this.arch, required this.prelude});
  final String dir; // the plugin's folder (plugin.json + main)
  final String dataRoot; // where plugins keep their storage, one folder each
  final String language; // the listener's, 'zh-CN' or 'en'
  final String platform, arch; // what host.platform / host.arch say
  final String prelude; // assets/js/prelude.js: the JS side of the host API
}

/// A running plugin. Every method is asynchronous and fails with a
/// [PluginError]; nothing about the engine leaks through.
abstract interface class PluginConnection {
  Manifest get manifest;
  Set<String> get exports;
  Map<String, String> get settings;
  Stream<WorkerEvent> get events;
  bool can(String method);

  /// Calls an export with JSON-like params; answers its JSON-like result.
  Future<Object?> call(String method, [Object? params, Duration? timeout]);
  Future<void> setSetting(String key, String value);
  Future<void> setLanguage(String lang);
  void close();
}

/// Starts plugins.
abstract interface class PluginRuntime {
  /// A short name for logs and the about box ('QuickJS-ng').
  String get name;
  Future<PluginConnection> start(PluginSpec spec);
}
