// Plugins in the browser: each runs in its own module Worker
// (web/mygo/plugin_worker.js) on the browser's JavaScript engine, with the
// host API written in JS, storage in IndexedDB (the same Store layout as on
// the phone) and fetch through the relay. This side mirrors PluginWorker
// (the QuickJS isolate): plain JSON messages, calls answered by id, events.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/core/runtime/plugin_runtime.dart';
import 'package:mygo_mobile/core/storage/idb_store.dart';

class WebWorkerRuntime implements PluginRuntime {
  const WebWorkerRuntime({this.db = 'mygo', this.relay = 'relay'});

  /// The IndexedDB database the Store uses.
  final String db;

  /// Where the relay's fetch endpoint is, relative to the page.
  final String relay;

  @override
  String get name => 'Web Worker';

  @override
  Future<PluginConnection> start(PluginSpec spec) => WebPluginConnection.spawn(spec, db: db, relay: Uri.parse(web.document.baseURI).resolve(relay).toString());
}

class WebPluginConnection implements PluginConnection {
  WebPluginConnection._(this._spec, this._db, this._relay);

  final PluginSpec _spec;
  final String _db, _relay;
  late web.Worker _worker;
  @override
  late Manifest manifest;
  @override
  late Set<String> exports;
  @override
  late Map<String, String> settings;
  final _events = StreamController<WorkerEvent>.broadcast();
  final Map<int, Completer<Object?>> _pending = {};
  final Map<int, Completer<void>> _pongs = {};
  int _next = 1;
  bool _closed = false;
  Completer<Map<String, dynamic>>? _ready;

  static const callTimeout = Duration(seconds: 30);
  static const signInTimeout = Duration(minutes: 5);

  @override
  Stream<WorkerEvent> get events => _events.stream;
  @override
  bool can(String method) => exports.contains(method);

  static Future<WebPluginConnection> spawn(PluginSpec spec, {required String db, required String relay}) async {
    final c = WebPluginConnection._(spec, db, relay);
    final ready = await c._boot();
    c.manifest = Manifest.parse(ready['manifest'] as String);
    c.exports = (ready['exports'] as List).cast<String>().toSet();
    c.settings = (ready['settings'] as Map).map((k, v) => MapEntry('$k', '$v'));
    return c;
  }

  Future<Map<String, dynamic>> _boot() async {
    _ready = Completer();
    _worker = web.Worker(mygoWebAsset('plugin_worker.js').toJS, web.WorkerOptions(type: 'module', name: 'plugin:${_spec.dir}'));
    _worker.onmessage = ((web.MessageEvent e) => _onMessage((e.data as JSString).toDart)).toJS;
    _worker.onerror = ((web.Event e) {
      final msg = e.isA<web.ErrorEvent>() ? (e as web.ErrorEvent).message : 'the plugin worker failed to load';
      if (!(_ready?.isCompleted ?? true)) _ready!.completeError(PluginError('', msg));
    }).toJS;
    _post({
      'op': 'init',
      'db': _db,
      'dir': _spec.dir,
      'dataRoot': _spec.dataRoot,
      'language': _spec.language,
      'platform': _spec.platform,
      'arch': _spec.arch,
      'relay': _relay,
    });
    final r = await _ready!.future.timeout(const Duration(seconds: 30), onTimeout: () => throw PluginError('', 'the plugin didn\'t start in time'));
    return r;
  }

  void _post(Map<String, Object?> m) => _worker.postMessage(jsonEncode(m).toJS);

  void _onMessage(String data) {
    final m = jsonDecode(data) as Map<String, dynamic>;
    switch (m['type']) {
      case 'ready':
        _ready?.complete(m);
      case 'failed':
        _ready?.completeError(PluginError('${m['code'] ?? ''}', '${m['message']}'));
      case 'result':
        final c = _pending.remove(m['id']);
        if (c == null || c.isCompleted) return;
        if (m['ok'] == true) {
          c.complete(m['value']);
        } else {
          c.completeError(PluginError('${m['code'] ?? ''}', '${m['message'] ?? ''}'));
        }
      case 'pong':
        _pongs.remove(m['id'])?.complete();
      case 'event':
        if (!_events.isClosed) _events.add(WorkerEvent('${m['event']}', (m['data'] as Map).cast<String, dynamic>()));
    }
  }

  Future<Object?> _ask(Map<String, Object?> msg, Duration limit, String what) {
    if (_closed) return Future.error(PluginError('', 'the plugin stopped'));
    final id = _next++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _post({...msg, 'id': id});
    return c.future.timeout(limit, onTimeout: () {
      _pending.remove(id);
      _checkAlive();
      throw PluginError('', 'the plugin didn\'t answer $what in time');
    });
  }

  /// After a timeout: a worker stuck in a loop can't answer a ping; replace
  /// it (the QuickJS runtime interrupts and restarts in the same case).
  Future<void> _checkAlive() async {
    if (_closed) return;
    final id = _next++;
    final pong = Completer<void>();
    _pongs[id] = pong;
    _post({'op': 'ping', 'id': id});
    try {
      await pong.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _pongs.remove(id);
      _events.add(WorkerEvent('log', {'level': 'warn', 'msg': 'stuck; restarting it', 'plugin': manifest.id}));
      _worker.terminate();
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError(PluginError('', 'the plugin stopped'));
      }
      _pending.clear();
      try {
        await _boot();
      } catch (e) {
        _events.add(WorkerEvent('log', {'level': 'error', 'msg': 'restart failed: $e', 'plugin': manifest.id}));
      }
    }
  }

  @override
  Future<Object?> call(String method, [Object? params, Duration? timeout]) {
    if (!exports.contains(method)) return Future.error(PluginError(PluginError.unsupported, ''));
    return _ask({'op': 'call', 'method': method, 'params': params}, timeout ?? (method == 'signIn' ? signInTimeout : callTimeout), method);
  }

  @override
  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
    await _ask({'op': 'setSetting', 'key': key, 'value': value}, callTimeout, 'setSetting');
  }

  @override
  Future<void> setLanguage(String lang) => _ask({'op': 'language', 'language': lang}, callTimeout, 'language');

  /// Waits until the plugin's storage writes have reached IndexedDB.
  Future<void> flush() => _ask({'op': 'flush'}, callTimeout, 'flush');

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(PluginError('', 'the plugin stopped'));
    }
    _pending.clear();
    // Let queued storage writes land before the worker goes.
    final id = _next++;
    _pending[id] = Completer<Object?>();
    _post({'op': 'flush', 'id': id});
    Future.any([_pending[id]!.future, Future.delayed(const Duration(seconds: 2))]).whenComplete(() => _worker.terminate());
    _events.close();
  }
}
