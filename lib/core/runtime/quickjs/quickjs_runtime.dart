import 'package:mygo_mobile/core/runtime/plugin_runtime.dart';

import 'plugin_worker.dart';

/// Plugins on QuickJS-ng (libmygojs via dart:ffi), each on its own isolate.
class QuickJsRuntime implements PluginRuntime {
  const QuickJsRuntime();

  @override
  String get name => 'QuickJS-ng';

  @override
  Future<PluginConnection> start(PluginSpec spec) => PluginWorker.spawn(
        dir: spec.dir,
        dataRoot: spec.dataRoot,
        language: spec.language,
        platform: spec.platform,
        arch: spec.arch,
        prelude: spec.prelude,
      );
}
