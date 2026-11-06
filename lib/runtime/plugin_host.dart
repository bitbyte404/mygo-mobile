// Runs one MyGo Music plugin: its module in a JsEngine, and the host API the
// desktop app gives it (internal/plugin/host.go), done in Dart: storage,
// settings, locales, md5/AES, fetch limited to the network permission,
// timers, the sign-in prompt.
//
// A PluginHost belongs to the isolate that made it. The app runs each in a
// background isolate (plugin_worker.dart); tests may use it directly.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;

import 'js_engine.dart';
import 'manifest.dart';

/// An error a plugin threw: [code] is signIn, setup, unavailable, unsupported
/// or empty, as the desktop's music.Err* are.
class PluginError implements Exception {
  PluginError(this.code, this.message);
  final String code;
  final String message;

  static const signIn = 'signIn', setup = 'setup', unavailable = 'unavailable', unsupported = 'unsupported';

  @override
  String toString() {
    switch (code) {
      case signIn:
        return message.isEmpty ? 'sign in first' : message;
      case setup:
        return message.isEmpty ? 'the plugin needs setting up' : message;
      case unavailable:
        return message.isEmpty ? 'not available' : message;
      case unsupported:
        return message.isEmpty ? 'not supported by this source' : message;
    }
    return message.isEmpty ? 'the plugin failed' : message;
  }

  Map<String, dynamic> toJson() => {'code': code, 'message': message};
}

/// Something the plugin wants the app to do or show.
typedef HostEvent = void Function(String type, Map<String, dynamic> data);

class PluginHost {
  PluginHost({
    required this.dir,
    required this.dataRoot,
    this.language = 'zh-CN',
    this.platform = '',
    this.arch = '',
    this.onEvent,
    HttpClient? httpClient,
  }) : _http = httpClient ?? _defaultClient();

  /// The plugin's folder (where plugin.json is), and the folder that holds
  /// every plugin's data: this one's is `dataRoot/<id>`, as on desktop.
  final String dir;
  final String dataRoot;
  String language;
  final String platform;
  final String arch;
  final HostEvent? onEvent;
  final HttpClient _http;

  static const callTimeout = Duration(seconds: 30);
  static const signInTimeout = Duration(minutes: 5);

  late Manifest manifest;
  late String dataDir;
  JsEngine? _engine;
  Set<String> exports = {};
  Map<String, String> _locales = {};
  Map<String, dynamic> _storage = {};
  Map<String, String> _settings = {};
  final Map<int, Timer> _timers = {};
  final Map<int, Completer<Object?>> _calls = {};
  int _nextCall = 1;
  final _rand = Random.secure();

  static HttpClient _defaultClient() {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 15);
    // Tests behind a proxy set MYGO_HTTP_PROXY=host:port.
    final proxy = Platform.environment['MYGO_HTTP_PROXY'];
    if (proxy != null && proxy.isNotEmpty) c.findProxy = (_) => 'PROXY $proxy';
    return c;
  }

  bool get running => _engine != null && !_engine!.closed;

  /// Reads the plugin and runs its module.
  void start() {
    manifest = Manifest.load(dir);
    dataDir = '$dataRoot/${manifest.id}';
    Directory(dataDir).createSync(recursive: true);
    _storage = _readJson('storage.json') as Map<String, dynamic>? ?? {};
    _settings = ((_readJson('settings.json') as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v'));
    _loadLocales();
    final source = File('$dir/${manifest.main}').readAsStringSync();
    if (manifest.main.endsWith('.ts')) {
      throw PluginError('', 'TypeScript plugins (${manifest.main}) are not supported on mobile yet');
    }
    final engine = JsEngine(onSend: _onSend);
    _engine = engine;
    try {
      engine.evalScript('prelude.js', preludeSource);
      engine.evalModule(manifest.main, source);
      exports = engine.exportNames().toSet();
    } catch (e) {
      close();
      rethrow;
    }
  }

  /// The prelude's text; the app loads it from its assets, tests from disk.
  static String preludeSource = '';

  void _loadLocales() {
    _locales = {};
    if (language == 'en') return;
    final f = File('$dir/locales/$language.json');
    if (!f.existsSync()) return;
    try {
      final m = jsonDecode(f.readAsStringSync());
      if (m is Map) _locales = m.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {}
  }

  void setLanguage(String lang) {
    language = lang;
    _loadLocales();
  }

  String t(String text) {
    final tr = _locales[text];
    return tr == null || tr.isEmpty ? text : tr;
  }

  Object? _readJson(String name) {
    final f = File('$dataDir/$name');
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(f.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  void _writeJson(String name, Object value) {
    final path = '$dataDir/$name';
    final part = File('$path.part');
    part.writeAsStringSync(jsonEncode(value), flush: true);
    part.renameSync(path);
  }

  String setting(String key) => _settings[key] ?? '';
  Map<String, String> get settings => Map.unmodifiable(_settings);

  /// Keeps the setting, and tells a running plugin through setSetting if it
  /// exports that, as the desktop does.
  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
    Directory(dataDir).createSync(recursive: true);
    _writeJson('settings.json', _settings);
    if (running && exports.contains('setSetting')) {
      await call('setSetting', {'key': key, 'value': value});
    }
  }

  /// Calls an export with one object of parameters (or none) and answers
  /// what it returned, decoded from JSON. Throws a [PluginError].
  Future<Object?> call(String method, [Object? params, Duration? timeout]) {
    final engine = _engine;
    if (engine == null || engine.closed) return Future.error(PluginError('', 'the plugin stopped; try again'));
    if (!exports.contains(method)) return Future.error(PluginError(PluginError.unsupported, ''));
    final id = _nextCall++;
    final c = Completer<Object?>();
    _calls[id] = c;
    try {
      engine.callGlobal('__mg_call', jsonEncode({'id': id, 'method': method, 'params': params}));
    } on JsError catch (e) {
      // An interrupt: the plugin ran too long without letting go.
      _calls.remove(id);
      _log('error', '$method: $e');
      if (e.message.contains('interrupted')) _restart();
      return Future.error(PluginError('', e.message));
    }
    final limit = timeout ?? (method == 'signIn' ? signInTimeout : callTimeout);
    return c.future.timeout(limit, onTimeout: () {
      _calls.remove(id);
      throw PluginError('', 'the plugin didn\'t answer $method in time');
    });
  }

  void _restart() {
    _log('warn', 'stuck; restarting it');
    close();
    try {
      start();
    } catch (e) {
      _log('error', 'restart failed: $e');
    }
  }

  void close() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    for (final c in _calls.values) {
      if (!c.isCompleted) c.completeError(PluginError('', 'the plugin stopped'));
    }
    _calls.clear();
    _engine?.close();
    _engine = null;
  }

  void _log(String level, String msg) {
    onEvent?.call('log', {'level': level, 'msg': msg, 'plugin': _idOrDir});
  }

  String get _idOrDir {
    try {
      return manifest.id;
    } catch (_) {
      return dir;
    }
  }

  // Runs JS from an event (a timer, a fetch's answer), reporting what it throws.
  void _enter(String fn, Map<String, dynamic> msg, [Uint8List? bytes]) {
    final engine = _engine;
    if (engine == null || engine.closed) return;
    try {
      engine.callGlobal(fn, jsonEncode(msg), bytes);
    } on JsError catch (e) {
      _log('error', e.message);
      if (e.message.contains('interrupted')) _restart();
    }
  }

  Object? _onSend(String op, String json, Uint8List? bytes) {
    final Map<String, dynamic> a = json.isEmpty ? const {} : (jsonDecode(json) as Map).cast<String, dynamic>();
    switch (op) {
      case 'result':
        final c = _calls.remove(a['id']);
        if (c != null && !c.isCompleted) {
          if (a['ok'] == true) {
            c.complete(a['value']);
          } else {
            c.completeError(PluginError('${a['code'] ?? ''}', '${a['message'] ?? ''}'));
          }
        }
        return jsUndefined;
      case 'info':
        return {
          'platform': platform.isNotEmpty ? platform : Platform.operatingSystem,
          'arch': arch.isNotEmpty ? arch : _arch(),
          'dir': dir,
          'dataDir': dataDir,
        };
      case 'log':
        _log('${a['level']}', '${a['msg']}');
        return jsUndefined;
      case 'storage.get':
        final k = '${a['key']}';
        return _storage.containsKey(k) ? _storage[k] : jsUndefined;
      case 'storage.set':
        _storage['${a['key']}'] = a['value'];
        _writeJson('storage.json', _storage);
        return jsUndefined;
      case 'storage.remove':
        _storage.remove('${a['key']}');
        _writeJson('storage.json', _storage);
        return jsUndefined;
      case 'setting':
        return setting('${a['key']}');
      case 't':
        return t('${a['text']}');
      case 'language':
        return language;
      case 'md5':
        return crypto.md5.convert(utf8.encode('${a['text']}')).toString();
      case 'aesEcbEncrypt':
        return _hex(aesEcbPkcs7(utf8.encode('${a['key']}'), utf8.encode('${a['text']}')));
      case 'random':
        final n = (a['n'] as num).toInt();
        if (n > 65536) throw JsError('getRandomValues: at most 65536 bytes');
        return List<int>.generate(n, (_) => _rand.nextInt(256));
      case 'removeDataDir':
        final name = '${a['name']}';
        final norm = Uri.file(name).normalizePath().toFilePath();
        if (name.isEmpty || norm == '.' || norm.startsWith('..') || norm.startsWith('/') || name.contains('..')) {
          throw JsError('not a folder of the plugin\'s data: $name');
        }
        final d = Directory('$dataDir/$norm');
        if (d.existsSync()) d.deleteSync(recursive: true);
        return jsUndefined;
      case 'openURL':
        final u = Uri.tryParse('${a['url']}');
        if (u == null || (u.scheme != 'http' && u.scheme != 'https')) throw JsError('not a web address: ${a['url']}');
        onEvent?.call('openURL', {'url': '${a['url']}', 'plugin': manifest.id});
        return jsUndefined;
      case 'signInPrompt':
        onEvent?.call('signInPrompt', {'qr': '${a['qr'] ?? ''}', 'text': '${a['text'] ?? ''}', 'plugin': manifest.id});
        return jsUndefined;
      case 'timer':
        final id = (a['id'] as num).toInt();
        final ms = Duration(milliseconds: (a['ms'] as num).toInt());
        _timers[id]?.cancel();
        if (a['repeat'] == true) {
          _timers[id] = Timer.periodic(ms.inMilliseconds < 1 ? const Duration(milliseconds: 1) : ms,
              (_) => _enter('__mg_timer', {'id': id}));
        } else {
          _timers[id] = Timer(ms, () {
            _timers.remove(id);
            _enter('__mg_timer', {'id': id});
          });
        }
        return jsUndefined;
      case 'clearTimer':
        _timers.remove((a['id'] as num).toInt())?.cancel();
        return jsUndefined;
      case 'fetch':
        if (manifest.network.isEmpty) throw JsError('fetch: the plugin has no network permission');
        final u = Uri.tryParse('${a['url']}');
        if (u == null || (u.scheme != 'http' && u.scheme != 'https')) throw JsError('fetch: not a web address: ${a['url']}');
        if (!hostAllowed(manifest.network, u.host)) throw JsError('webapi: host ${u.host.toLowerCase()} is not allowed');
        _fetch((a['id'] as num).toInt(), a, bytes);
        return jsUndefined;
      case 'waitForRedirect':
        _waitForRedirect((a['id'] as num).toInt(), (a['opts'] as Map?)?.cast<String, dynamic>() ?? {});
        return jsUndefined;
      case 'webSignIn':
        final id = (a['id'] as num).toInt();
        scheduleMicrotask(() => _settle(id, false, null, error: 'host.webSignIn isn\'t available in the mobile app yet'));
        return jsUndefined;
    }
    throw JsError('unknown host call: $op');
  }

  static String _arch() {
    final v = Platform.version.toLowerCase();
    if (v.contains('arm64')) return 'arm64';
    if (v.contains('x64')) return 'amd64';
    if (v.contains('arm')) return 'arm';
    return 'unknown';
  }

  void _settle(int id, bool ok, Object? value, {String? error, Uint8List? bytes}) {
    _enter('__mg_settle', {'id': id, 'ok': ok, 'value': value, 'error': error}, bytes);
  }

  Future<void> _fetch(int id, Map<String, dynamic> req, Uint8List? body) async {
    try {
      var uri = Uri.parse('${req['url']}');
      var method = '${req['method'] ?? 'GET'}';
      final redirect = '${req['redirect'] ?? 'follow'}';
      final headers = ((req['headers'] as List?) ?? []).map((e) => [(e as List)[0].toString(), e[1].toString()]).toList();
      var redirected = false;
      for (var hop = 0;; hop++) {
        if (!hostAllowed(manifest.network, uri.host)) {
          throw Exception('webapi: host ${uri.host.toLowerCase()} is not allowed');
        }
        final r = await _http.openUrl(method, uri);
        r.followRedirects = false;
        for (final h in headers) {
          if (h[0] == 'content-length' || h[0] == 'host') continue;
          r.headers.add(h[0], h[1], preserveHeaderCase: true);
        }
        if (body != null) {
          r.contentLength = body.length;
          r.add(body);
        }
        final res = await r.close().timeout(const Duration(minutes: 10));
        final loc = res.headers.value('location');
        if (redirect != 'manual' && const [301, 302, 303, 307, 308].contains(res.statusCode) && loc != null) {
          await res.drain<void>();
          if (redirect == 'error') throw Exception('fetch: redirect not allowed');
          if (hop >= 20) throw Exception('fetch: too many redirects');
          uri = uri.resolve(loc);
          redirected = true;
          if (res.statusCode == 303 || ((res.statusCode == 301 || res.statusCode == 302) && method == 'POST')) {
            method = 'GET';
            body = null;
            headers.removeWhere((h) => h[0] == 'content-type');
          }
          continue;
        }
        final bb = BytesBuilder(copy: false);
        await for (final chunk in res) {
          bb.add(chunk);
        }
        final out = <List<String>>[];
        res.headers.forEach((name, values) {
          for (final v in values) {
            out.add([name, v]);
          }
        });
        _settle(id, true, {
          'status': res.statusCode,
          'statusText': res.reasonPhrase,
          'headers': out,
          'url': uri.toString(),
          'redirected': redirected,
        }, bytes: bb.takeBytes());
        return;
      }
    } catch (e) {
      _settle(id, false, null, error: 'fetch failed: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _waitForRedirect(int id, Map<String, dynamic> o) async {
    if (manifest.network.isEmpty) {
      _settle(id, false, null, error: 'waitForRedirect needs the network permission');
      return;
    }
    HttpServer? srv;
    try {
      final port = (o['port'] as num?)?.toInt() ?? 0;
      final path = '${o['path'] ?? ''}';
      final page = '${o['page'] ?? ''}'.isEmpty ? "You're signed in. You can close this page." : '${o['page']}';
      final wait = Duration(milliseconds: (o['timeout'] as num?)?.toInt() ?? signInTimeout.inMilliseconds);
      srv = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      final got = Completer<Map<String, String>>();
      srv.listen((req) {
        if (path.isNotEmpty && req.uri.path != path) {
          req.response.statusCode = 404;
          req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
        req.response.write(page);
        req.response.close();
        if (!got.isCompleted) got.complete(req.uri.queryParameters);
      });
      final q = await got.future.timeout(wait);
      _settle(id, true, q);
    } on TimeoutException {
      _settle(id, false, null, error: 'timed out waiting for the sign-in to come back');
    } catch (e) {
      _settle(id, false, null, error: '$e');
    } finally {
      await srv?.close(force: true);
    }
  }
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// AES-ECB with PKCS#7 padding, as host.crypto.aesEcbEncrypt does on desktop.
Uint8List aesEcbPkcs7(List<int> key, List<int> text) {
  if (key.length != 16 && key.length != 24 && key.length != 32) {
    throw JsError('crypto/aes: invalid key size ${key.length}');
  }
  final pad = 16 - text.length % 16;
  final input = Uint8List(text.length + pad)
    ..setAll(0, text)
    ..fillRange(text.length, text.length + pad, pad);
  final aes = pc.AESEngine()..init(true, pc.KeyParameter(Uint8List.fromList(key)));
  final out = Uint8List(input.length);
  for (var i = 0; i < input.length; i += 16) {
    aes.processBlock(input, i, out, i);
  }
  return out;
}
