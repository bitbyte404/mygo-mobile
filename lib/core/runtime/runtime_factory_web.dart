import 'package:mygo_mobile/core/runtime/plugin_runtime.dart';
import 'package:mygo_mobile/core/runtime/web/web_runtime.dart';

PluginRuntime defaultPluginRuntime() => const WebWorkerRuntime();
