// The runtime this platform runs plugins on, chosen at compile time: QuickJS
// over dart:ffi on Android, iOS and desktop; the browser's own JS engine in a
// Web Worker on the web.
import 'package:mygo_mobile/core/runtime/plugin_runtime.dart';

import 'runtime_factory_ffi.dart' if (dart.library.js_interop) 'runtime_factory_web.dart' as impl;

PluginRuntime defaultPluginRuntime() => impl.defaultPluginRuntime();
