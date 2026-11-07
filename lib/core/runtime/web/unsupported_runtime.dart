import 'package:mygo_mobile/core/runtime/plugin_runtime.dart';

/// The browser has no dart:ffi; a web runtime (a Worker running the plugin with
/// a JS host API and a fetch relay) is future work. Until then plugins fail to
/// start on the web with a clear error instead of a missing-library crash.
class UnsupportedRuntime implements PluginRuntime {
  const UnsupportedRuntime();

  @override
  String get name => 'none';

  @override
  Future<PluginConnection> start(PluginSpec spec) =>
      Future.error(PluginError('', 'plugins cannot run in this build yet (no JavaScript runtime for this platform)'));
}
