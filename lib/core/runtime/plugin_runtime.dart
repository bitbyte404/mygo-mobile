// The platform interface for running plugins. The app (lib/data) talks only
// to these types; how a plugin's JavaScript actually runs is the
// implementation's business:
//   - QuickJsRuntime (lib/core/runtime/quickjs): QuickJS-ng through dart:ffi,
//     one background isolate per plugin. Android, iOS, desktop, tests.
//   - WebWorkerRuntime (lib/core/runtime/web): the browser's JS engine, one
//     module Worker per plugin (web/mygo/plugin_worker.js), storage in
//     IndexedDB, fetch through the relay. See docs/WEB.md.
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
  // The plugin's folder (plugin.json + main) and the folder holding every
  // plugin's data (this one's is dataRoot/<id>): real paths for QuickJS,
  // Store paths ('plugins/<id>', 'plugin-data') in the browser.
  final String dir;
  final String dataRoot;
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
