// Runs a PluginHost on a background isolate, so a plugin's work (signing,
// RSA, inflating lyrics) never janks the UI. The UI talks to it through
// [PluginWorker]; what the plugin wants shown comes back as [events].
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'manifest.dart';
import 'plugin_host.dart';

class WorkerEvent {
  WorkerEvent(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

class PluginWorker {
  PluginWorker._(this._isolate, this._send, this._receive, this.manifest, this.exports, this.settings);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _receive;
  final Manifest manifest;
  final Set<String> exports;
  final Map<String, String> settings;
  final _events = StreamController<WorkerEvent>.broadcast();
  final Map<int, Completer<Object?>> _pending = {};
  int _next = 1;
  bool _closed = false;

  Stream<WorkerEvent> get events => _events.stream;
  bool can(String method) => exports.contains(method);

  static Future<PluginWorker> spawn({
    required String dir,
    required String dataRoot,
    required String language,
    required String platform,
    required String arch,
    required String prelude,
  }) async {
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_main, {
      'port': receive.sendPort,
      'dir': dir,
      'dataRoot': dataRoot,
      'language': language,
      'platform': platform,
      'arch': arch,
      'prelude': prelude,
    }, debugName: 'plugin:$dir');
    final first = Completer<Map>();
    final early = <Map>[];
    late final StreamSubscription sub;
    PluginWorker? worker;
    sub = receive.listen((msg) {
      final m = msg as Map;
      if (worker != null) {
        worker._onMessage(m);
      } else if (m['type'] == 'ready' || m['type'] == 'failed') {
        first.complete(m);
      } else {
        early.add(m);
      }
    });
    final ready = await first.future;
    if (ready['type'] == 'failed') {
      await sub.cancel();
      receive.close();
      isolate.kill(priority: Isolate.immediate);
      throw PluginError('${ready['code'] ?? ''}', '${ready['message']}');
    }
    worker = PluginWorker._(
      isolate,
      ready['send'] as SendPort,
      receive,
      Manifest.parse(ready['manifest'] as String),
      (ready['exports'] as List).cast<String>().toSet(),
      (ready['settings'] as Map).cast<String, String>(),
    );
    for (final m in early) {
      worker._onMessage(m);
    }
    return worker;
  }

  void _onMessage(Map m) {
    switch (m['type']) {
      case 'result':
        final c = _pending.remove(m['id']);
        if (c == null) return;
        if (m['ok'] == true) {
          c.complete(m['value']);
        } else {
          c.completeError(PluginError('${m['code'] ?? ''}', '${m['message'] ?? ''}'));
        }
      case 'event':
        _events.add(WorkerEvent('${m['event']}', (m['data'] as Map).cast<String, dynamic>()));
    }
  }

  Future<Object?> _ask(Map<String, Object?> msg) {
    if (_closed) return Future.error(PluginError('', 'the plugin stopped'));
    final id = _next++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _send.send({...msg, 'id': id});
    return c.future;
  }

  /// Calls an export; throws a [PluginError].
  Future<Object?> call(String method, [Object? params, Duration? timeout]) {
    if (!exports.contains(method)) return Future.error(PluginError(PluginError.unsupported, ''));
    return _ask({'op': 'call', 'method': method, 'params': params, 'timeout': timeout?.inMilliseconds});
  }

  Future<void> setSetting(String key, String value) async {
    settings[key] = value;
    await _ask({'op': 'setSetting', 'key': key, 'value': value});
  }

  Future<void> setLanguage(String lang) => _ask({'op': 'language', 'language': lang});

  void close() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      c.completeError(PluginError('', 'the plugin stopped'));
    }
    _pending.clear();
    _send.send({'op': 'close'});
    Future.delayed(const Duration(milliseconds: 300), () {
      _isolate.kill(priority: Isolate.immediate);
      _receive.close();
    });
    _events.close();
  }
}

void _main(Map init) {
  final out = init['port'] as SendPort;
  final inbox = ReceivePort();
  PluginHost.preludeSource = init['prelude'] as String;
  final host = PluginHost(
    dir: init['dir'] as String,
    dataRoot: init['dataRoot'] as String,
    language: init['language'] as String,
    platform: init['platform'] as String,
    arch: init['arch'] as String,
    onEvent: (type, data) => out.send({'type': 'event', 'event': type, 'data': data}),
  );
  try {
    host.start();
  } catch (e) {
    out.send({
      'type': 'failed',
      'code': e is PluginError ? e.code : '',
      'message': e is PluginError ? e.message : '$e',
    });
    inbox.close();
    return;
  }
  out.send({
    'type': 'ready',
    'send': inbox.sendPort,
    'manifest': _manifestJson(host.manifest),
    'exports': host.exports.toList(),
    'settings': host.settings,
  });
  inbox.listen((msg) async {
    final m = msg as Map;
    final id = m['id'];
    void reply(bool ok, [Object? value, Object? err]) {
      out.send({
        'type': 'result',
        'id': id,
        'ok': ok,
        'value': value,
        'code': err is PluginError ? err.code : '',
        'message': err is PluginError ? err.message : (err == null ? '' : '$err'),
      });
    }

    try {
      switch (m['op']) {
        case 'call':
          final t = m['timeout'] as int?;
          final v = await host.call(m['method'] as String, m['params'], t == null ? null : Duration(milliseconds: t));
          reply(true, v);
        case 'setSetting':
          await host.setSetting(m['key'] as String, m['value'] as String);
          reply(true);
        case 'language':
          host.setLanguage(m['language'] as String);
          reply(true);
        case 'close':
          host.close();
          inbox.close();
      }
    } catch (e) {
      reply(false, null, e);
    }
  });
}

String _manifestJson(Manifest m) => jsonEncode(m.toJson());
