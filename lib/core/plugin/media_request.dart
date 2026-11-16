// What the app asks for when it fetches a plugin's pictures and audio itself
// (not through the plugin's own fetch), as MyGo Music 0.1.19-0.1.20 do it:
//
//   - {size} in a picture's URL becomes the pixels across it is shown at
//     (music.SizedImage); a URL without it is fetched as it is.
//   - plugin.json's requestHeaders add headers, such as a session cookie,
//     for the hosts they name (plugin.HeadersFor), their {setting:key} and
//     {storage:key} filled in as the values are at the time of the request.
//   - Audio keeps the headers the plugin's stream answer gives first.
//   - On a redirect to another host none of these headers go on
//     (music.HeadersStay): [headersAfterRedirect] is the rule, which the
//     phone's player (data/player/stream_redirects.dart) and the web relay
//     (relay/relay.go, the same rule in Go) apply.
//
// Pure functions over a Manifest and the plugin's current values: the cover
// component, the player and the relay client all go through here.
import 'dart:convert';

import 'manifest.dart';

/// A request ready to send: the URL to fetch and the headers to fetch it with.
class MediaRequest {
  const MediaRequest(this.url, [this.headers = const {}]);
  final String url;
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) => other is MediaRequest && other.url == url && _sameHeaders(other.headers, headers);
  @override
  int get hashCode => Object.hash(url, Object.hashAllUnordered(headers.entries.map((e) => '${e.key}\u0000${e.value}')));
  @override
  String toString() => 'MediaRequest($url, $headers)';

  static bool _sameHeaders(Map<String, String> a, Map<String, String> b) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}

/// The values a plugin's requestHeaders can name: its settings, and what it
/// keeps with host.storage (any JSON value; a string goes as it is).
class PluginValues {
  const PluginValues({this.setting = _none, this.storage = _none});
  final Object? Function(String key) setting;
  final Object? Function(String key) storage;
  static Object? _none(String _) => null;
}

abstract final class MediaRequests {
  /// The size a picture whose URL says where its size goes is fetched at
  /// when nothing asks for one: the most the app shows one at.
  static const placeholderSize = 600;

  static final _sizePlaceholder = RegExp(r'\{size\}|%7[Bb]size%7[Dd]');
  static final _valuePlaceholder = RegExp(r'\{(setting|storage):([^{}]+)\}');

  /// [url] with its {size} (or %7Bsize%7D, as a URL written again by JS's
  /// URL has it) filled in with [px], or [placeholderSize] for none.
  static String sizedImageUrl(String url, [int? px]) {
    if (!url.contains('size')) return url;
    final n = px == null || px <= 0 ? placeholderSize : px;
    return url.replaceAll(_sizePlaceholder, '$n');
  }

  /// The storage keys [m]'s requestHeaders name: the values a runtime keeps
  /// in step for the app (PluginConnection.storageValue).
  static Set<String> storageKeys(Manifest m) => {
        for (final r in m.requestHeaders)
          for (final v in r.headers.values)
            for (final x in _valuePlaceholder.allMatches(v))
              if (x.group(1) == 'storage') x.group(2)!,
      };

  /// The headers [m]'s requestHeaders give for fetching [url] as [kind],
  /// placeholders filled in from [values]. A header whose placeholder is of
  /// nothing (before signing in) is left out; the first rule to give a
  /// header wins. Empty for a URL on none of the plugin's hosts.
  static Map<String, String> headersFor(Manifest m, String url, MediaKind kind, PluginValues values) {
    if (m.requestHeaders.isEmpty) return const {};
    final u = Uri.tryParse(url);
    if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) return const {};
    final host = u.host.toLowerCase();
    final out = <String, String>{};
    for (final r in m.requestHeaders) {
      if (!r.appliesTo(kind) || !_ruleReaches(m, r, host, values)) continue;
      r.headers.forEach((name, value) {
        final v = _fill(value, values);
        if (v != null) out.putIfAbsent(name, () => v);
      });
    }
    return out;
  }

  /// A picture of [m]'s to show [px] pixels across.
  static MediaRequest image(Manifest? m, String url, {int? px, PluginValues values = const PluginValues()}) {
    final sized = sizedImageUrl(url, px);
    return MediaRequest(sized, m == null ? const {} : headersFor(m, sized, MediaKind.image, values));
  }

  /// A song's audio: the headers [streamHeaders] the plugin's stream answer
  /// gave, then requestHeaders' for audio under names it didn't give.
  static MediaRequest audio(Manifest m, String url, {Map<String, String> streamHeaders = const {}, PluginValues values = const PluginValues()}) {
    final out = Map<String, String>.of(streamHeaders);
    headersFor(m, url, MediaKind.audio, values).forEach((k, v) {
      if (!out.keys.any((x) => x.toLowerCase() == k.toLowerCase())) out[k] = v;
    });
    return MediaRequest(url, out);
  }

  /// The headers to follow a redirect from [fromHost] (the host first asked)
  /// to [to] with: all of them to that host or one below it, none elsewhere,
  /// so what a plugin asks with reaches no one else (music.HeadersStay).
  static Map<String, String> headersAfterRedirect(String fromHost, Uri to, Map<String, String> headers) =>
      headersMayFollow(fromHost, to.host) ? headers : const {};

  static bool headersMayFollow(String fromHost, String toHost) {
    final from = fromHost.toLowerCase(), to = toHost.toLowerCase();
    return to == from || to.endsWith('.$from');
  }

  // A host of a setting counts only while the network permission reaches it.
  static bool _ruleReaches(Manifest m, RequestHeaderRule r, String host, PluginValues values) {
    for (var h in r.hosts) {
      if (h.startsWith('{setting:')) {
        final key = h.substring('{setting:'.length, h.length - 1);
        if (_serverHost('${values.setting(key) ?? ''}') == host && hostAllowed(m.network, host)) return true;
        continue;
      }
      h = h.toLowerCase();
      if (h == host || (h.startsWith('*.') && host.endsWith(h.substring(1)))) return true;
    }
    return false;
  }

  /// The host of a server as a setting names it: https://nas.local:5666, or
  /// a host with or without its port.
  static String _serverHost(String s) {
    s = s.trim();
    if (s.isEmpty) return '';
    if (!s.contains('://')) s = 'http://$s';
    return (Uri.tryParse(s)?.host ?? '').toLowerCase();
  }

  /// [value] with its placeholders filled in, or null when one is of nothing
  /// or the result would break the header's line.
  static String? _fill(String value, PluginValues values) {
    var ok = true;
    final filled = value.replaceAllMapped(_valuePlaceholder, (x) {
      final raw = x.group(1) == 'setting' ? values.setting(x.group(2)!) : values.storage(x.group(2)!);
      final v = _asText(raw);
      if (v.isEmpty) ok = false;
      return v;
    });
    if (!ok || filled.contains('\r') || filled.contains('\n')) return null;
    return filled;
  }

  static String _asText(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num || v is bool) return '$v';
    return jsonEncode(v); // a stored object goes as its JSON, as on desktop
  }
}
