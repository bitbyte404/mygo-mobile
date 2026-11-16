// The web build's side of the relay (relay/, docs/WEB.md): the access token,
// registering installed plugins (the relay's allowlist is their declared
// network permissions), and turning stream and artwork URLs into relay URLs
// so an https page can play kugou's plain-http CDN and draw its covers.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/core/plugin/media_request.dart';
import 'package:mygo_mobile/data/plugins/installer.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';

class RelayStatus {
  RelayStatus({required this.version, required this.tokenRequired, required this.authenticated, required this.plugins, required this.manifestUpload});
  final String version;
  final bool tokenRequired, authenticated, manifestUpload;
  final List<String> plugins;
}

class RelayError implements Exception {
  RelayError(this.status, this.code, this.message);
  final int status;
  final String code, message;
  @override
  String toString() => message;
}

class RelayClient implements PluginRegistrar {
  RelayClient(this.base, {http.Client? client}) : _http = client ?? http.Client();

  /// The page's URL; the relay answers on the same origin.
  final Uri base;
  final http.Client _http;

  Uri _u(String path, [Map<String, String>? q]) => base.resolve(path).replace(queryParameters: q);

  Future<Map<String, dynamic>> _json(http.Response r) async {
    Object? j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (r.statusCode >= 400) {
      final m = j is Map ? j : const {};
      throw RelayError(r.statusCode, '${m['code'] ?? ''}', '${m['error'] ?? 'relay answered ${r.statusCode}'}');
    }
    return j is Map<String, dynamic> ? j : {'list': j};
  }

  Future<RelayStatus> status() async {
    final j = await _json(await _http.get(_u('api/status')));
    return RelayStatus(
      version: '${j['version'] ?? ''}',
      tokenRequired: j['tokenRequired'] == true,
      authenticated: j['authenticated'] == true,
      manifestUpload: j['manifestUpload'] == true,
      plugins: ((j['plugins'] as List?) ?? const []).map((e) => '$e').toList(),
    );
  }

  /// Exchanges the token for the relay's session cookie (HttpOnly; the page
  /// never keeps the token itself). False when the token is wrong.
  Future<bool> signIn(String token) async {
    final r = await _http.post(_u('api/session'), headers: {'content-type': 'application/json'}, body: jsonEncode({'token': token.trim()}));
    if (r.statusCode == 401) return false;
    await _json(r);
    return true;
  }

  Future<void> signOut() async => _http.delete(_u('api/session'));

  @override
  Future<void> register(Manifest manifest, Origin origin) async {
    final body = origin.kind == 'github' && origin.repo.isNotEmpty
        ? {'kind': 'github', 'repo': origin.repo, 'branch': origin.branch}
        : {'kind': 'manifest', 'manifest': manifest.toJson()};
    final r = await _http
        .post(_u('api/plugins'), headers: {'content-type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60), onTimeout: () => throw RelayError(504, 'timeout', 'the relay did not answer the registration in time'));
    final j = await _json(r);
    if (j['id'] != manifest.id) {
      throw RelayError(409, 'manifest', 'the relay read plugin "${j['id']}" from ${origin.repo}, not "${manifest.id}"');
    }
  }

  @override
  Future<void> unregister(String id) async => _json(await _http.delete(_u('api/plugins/${Uri.encodeComponent(id)}')));

  @override
  Future<void> sync(List<InstalledPlugin> installed) async {
    final j = await _json(await _http.get(_u('api/plugins')));
    final have = <String, List<String>>{
      for (final e in (j['list'] as List? ?? const []).whereType<Map>()) '${e['id']}': ((e['network'] as List?) ?? const []).map((h) => '$h').toList(),
    };
    for (final p in installed) {
      final net = have[p.id];
      if (net != null && p.manifest.network.every(net.contains)) continue;
      try {
        await register(p.manifest, p.origin ?? Origin(kind: 'zip'));
      } catch (e) {
        debugPrint('relay: registering ${p.id}: $e');
      }
    }
  }

  /// Where the browser plays [r] (a plugin's stream, its headers decided by
  /// MediaRequests) from: the relay's /stream, Range passed through, the
  /// headers sent upstream and dropped on a redirect to another host.
  String streamUrl(String pluginId, MediaRequest r) => _u('stream', {'plugin': pluginId, 'url': r.url, ..._headerParam(r.headers)}).toString();

  /// Artwork through the relay's /img (http CDNs on an https page, and the
  /// pixels CanvasKit needs without CORS headers from the CDN), with the
  /// headers MediaRequests gave it.
  String imageUrl(MediaRequest r) {
    if (!(r.url.startsWith('http://') || r.url.startsWith('https://'))) return r.url;
    return _u('img', {'url': r.url, ..._headerParam(r.headers)}).toString();
  }

  static Map<String, String> _headerParam(Map<String, String> headers) => headers.isEmpty
      ? const {}
      : {'h': base64.encode(utf8.encode(jsonEncode([for (final e in headers.entries) [e.key, e.value]])))};
}
