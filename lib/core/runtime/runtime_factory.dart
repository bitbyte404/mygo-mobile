// The runtime this platform runs plugins on, chosen at compile time: the
// QuickJS/FFI one wherever dart:ffi exists, a placeholder on the web.
import 'package:mygo_mobile/core/runtime/plugin_runtime.dart';

import 'runtime_factory_stub.dart' if (dart.library.ffi) 'runtime_factory_ffi.dart' as impl;

PluginRuntime defaultPluginRuntime() => impl.defaultPluginRuntime();
