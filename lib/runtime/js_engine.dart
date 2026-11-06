// dart:ffi bindings to libmygojs (QuickJS-ng + native/mygojs.c).
//
// One JsEngine is one JS runtime. All of its calls must happen on the isolate
// that made it; JS calls back into Dart synchronously through [onSend].
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _SendNative = Pointer<Utf8> Function(
    Int64 engine, Pointer<Utf8> op, Pointer<Utf8> json, Pointer<Uint8> bytes, Int64 nbytes, Pointer<Int32> err);

typedef _NewC = Pointer<Void> Function(Int64 id, Pointer<NativeFunction<_SendNative>> send, Int64 memLimit);
typedef _NewD = Pointer<Void> Function(int id, Pointer<NativeFunction<_SendNative>> send, int memLimit);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeD = void Function(Pointer<Void>);
typedef _FreeStrC = Void Function(Pointer<Utf8>);
typedef _FreeStrD = void Function(Pointer<Utf8>);
typedef _DeadlineC = Void Function(Pointer<Void>, Int64);
typedef _DeadlineD = void Function(Pointer<Void>, int);
typedef _EvalC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _JobsC = Pointer<Utf8> Function(Pointer<Void>);
typedef _CallC = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, Int64);
typedef _CallD = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, int);
typedef _MemC = Int64 Function(Pointer<Void>);
typedef _MemD = int Function(Pointer<Void>);

/// What JS sent: an op name, its JSON text and, for some, bytes.
typedef HostSend = Object? Function(String op, String json, Uint8List? bytes);

class JsError implements Exception {
  JsError(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Lib {
  _Lib(DynamicLibrary lib)
      : mgNew = lib.lookupFunction<_NewC, _NewD>('mg_new'),
        mgFree = lib.lookupFunction<_FreeC, _FreeD>('mg_free'),
        mgFreeString = lib.lookupFunction<_FreeStrC, _FreeStrD>('mg_free_string'),
        mgSetDeadline = lib.lookupFunction<_DeadlineC, _DeadlineD>('mg_set_deadline'),
        mgEvalScript = lib.lookupFunction<_EvalC, _EvalC>('mg_eval_script'),
        mgEvalModule = lib.lookupFunction<_EvalC, _EvalC>('mg_eval_module'),
        mgRunJobs = lib.lookupFunction<_JobsC, _JobsC>('mg_run_jobs'),
        mgCallGlobal = lib.lookupFunction<_CallC, _CallD>('mg_call_global'),
        mgExportNames = lib.lookupFunction<_JobsC, _JobsC>('mg_export_names'),
        mgMemoryUsed = lib.lookupFunction<_MemC, _MemD>('mg_memory_used');

  final _NewD mgNew;
  final _FreeD mgFree;
  final _FreeStrD mgFreeString;
  final _DeadlineD mgSetDeadline;
  final _EvalC mgEvalScript;
  final _EvalC mgEvalModule;
  final _JobsC mgRunJobs;
  final _CallD mgCallGlobal;
  final _JobsC mgExportNames;
  final _MemD mgMemoryUsed;

  static _Lib? _instance;

  /// Where the library is: bundled with the app on Android (jniLibs) and
  /// linked into the app on iOS. Tests set MYGOJS_LIB to the host build.
  static _Lib get instance => _instance ??= _Lib(_open());

  static DynamicLibrary _open() {
    final override = Platform.environment['MYGOJS_LIB'];
    if (override != null && override.isNotEmpty) return DynamicLibrary.open(override);
    if (Platform.isAndroid) return DynamicLibrary.open('libmygojs.so');
    if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
    if (Platform.isLinux) {
      for (final p in [
        'libmygojs.so',
        '${File(Platform.resolvedExecutable).parent.path}/lib/libmygojs.so',
        'native/build/host/libmygojs.so',
      ]) {
        try {
          return DynamicLibrary.open(p);
        } catch (_) {}
      }
    }
    throw UnsupportedError('libmygojs is not available on ${Platform.operatingSystem}');
  }
}

/// Registry so the static FFI callback can find its engine by id.
final Map<int, JsEngine> _engines = {};
int _nextEngineId = 1;

Pointer<Utf8> _onSend(int id, Pointer<Utf8> op, Pointer<Utf8> json, Pointer<Uint8> bytes, int nbytes, Pointer<Int32> err) {
  final engine = _engines[id];
  if (engine == null) {
    err.value = 1;
    return 'engine is gone'.toNativeUtf8(allocator: malloc);
  }
  try {
    final b = bytes == nullptr ? null : Uint8List.fromList(bytes.asTypedList(nbytes));
    final answer = engine.onSend(op.toDartString(), json.toDartString(), b);
    if (identical(answer, jsUndefined)) return nullptr;
    return jsonEncode(answer).toNativeUtf8(allocator: malloc);
  } catch (e) {
    err.value = 1;
    final msg = e is JsError ? e.message : e.toString().replaceFirst(RegExp(r'^(Exception|Bad state|Invalid argument\(s\)): '), '');
    return msg.toNativeUtf8(allocator: malloc);
  }
}

/// Marks an answer of [JsEngine.onSend] that is undefined in JS, as opposed to null.
const Object jsUndefined = _Undefined();

class _Undefined {
  const _Undefined();
}


class JsEngine {
  JsEngine({required HostSend onSend, int memoryLimit = 256 << 20}) : _onSendFn = onSend {
    _lib = _Lib.instance;
    id = _nextEngineId++;
    _engines[id] = this;
    _ptr = _lib.mgNew(id, Pointer.fromFunction<_SendNative>(_onSend), memoryLimit);
  }

  late final _Lib _lib;
  late final int id;
  late final Pointer<Void> _ptr;
  final HostSend _onSendFn;
  bool _closed = false;

  /// How long one synchronous run of JS may take before it's interrupted.
  int sliceTimeoutMs = 15000;

  bool get closed => _closed;

  /// The host's answer; [jsUndefined] for undefined, anything else as JSON.
  Object? onSend(String op, String json, Uint8List? bytes) => _onSendFn(op, json, bytes);

  String? _take(Pointer<Utf8> p) {
    if (p == nullptr) return null;
    final s = p.toDartString();
    _lib.mgFreeString(p);
    return s;
  }

  void _check() {
    if (_closed) throw JsError('the plugin stopped');
  }

  T _withDeadline<T>(T Function() f) {
    _lib.mgSetDeadline(_ptr, sliceTimeoutMs);
    try {
      return f();
    } finally {
      _lib.mgSetDeadline(_ptr, 0);
    }
  }

  void evalScript(String name, String source) {
    _check();
    final n = name.toNativeUtf8(allocator: malloc);
    final s = source.toNativeUtf8(allocator: malloc);
    try {
      final err = _take(_withDeadline(() => _lib.mgEvalScript(_ptr, n, s)));
      if (err != null) throw JsError(err);
    } finally {
      malloc.free(n);
      malloc.free(s);
    }
  }

  void evalModule(String name, String source) {
    _check();
    final n = name.toNativeUtf8(allocator: malloc);
    final s = source.toNativeUtf8(allocator: malloc);
    try {
      final err = _take(_withDeadline(() => _lib.mgEvalModule(_ptr, n, s)));
      if (err != null) throw JsError(err);
    } finally {
      malloc.free(n);
      malloc.free(s);
    }
  }

  List<String> exportNames() {
    _check();
    final s = _take(_lib.mgExportNames(_ptr)) ?? '[]';
    return (jsonDecode(s) as List).cast<String>();
  }

  /// Calls a global JS function with (json, ArrayBuffer?), then runs the jobs
  /// it queued. An error a job throws comes back as a [JsError] too.
  void callGlobal(String fn, String json, [Uint8List? bytes]) {
    _check();
    final f = fn.toNativeUtf8(allocator: malloc);
    final j = json.toNativeUtf8(allocator: malloc);
    Pointer<Uint8> b = nullptr;
    if (bytes != null) {
      b = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      b.asTypedList(bytes.length).setAll(0, bytes);
    }
    try {
      final err = _take(_withDeadline(() => _lib.mgCallGlobal(_ptr, f, j, b, bytes?.length ?? 0)));
      if (err != null) throw JsError(err);
    } finally {
      malloc.free(f);
      malloc.free(j);
      if (b != nullptr) malloc.free(b);
    }
  }

  void runJobs() {
    _check();
    final err = _take(_withDeadline(() => _lib.mgRunJobs(_ptr)));
    if (err != null) throw JsError(err);
  }

  int get memoryUsed => _closed ? 0 : _lib.mgMemoryUsed(_ptr);

  void close() {
    if (_closed) return;
    _closed = true;
    _engines.remove(id);
    _lib.mgFree(_ptr);
  }
}
