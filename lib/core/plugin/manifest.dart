// A plugin's plugin.json, as the desktop app reads it (internal/plugin.Manifest).
import 'dart:convert';

import 'plugin_api.dart';

export 'plugin_api.dart';

/// How a setting is edited (plugin.json settings[].type, MyGo Music 0.1.23).
/// Values stay strings whatever the type: a boolean saves "true"/"false", a
/// select the chosen option's value.
enum SettingType { text, password, boolean, select }

/// One choice of a select: [value] is saved, [label] shown (translated).
class SettingOption {
  const SettingOption(this.value, this.label);
  final String value, label;
  Map<String, dynamic> toJson() => {'value': value, 'label': label};
}

/// A setting as plugin.json declares it (desktop music.Setting).
class SettingDef {
  SettingDef(this.key, this.label, this.help, this.link, {this.rawType = '', this.options = const []});
  final String key, label, help, link;

  /// The type as plugin.json gives it ('' when it gives none), kept as is so
  /// the manifest round-trips; [type] is what the app makes of it.
  final String rawType;
  final List<SettingOption> options;

  factory SettingDef.fromJson(Map m) => SettingDef(
        '${m['key'] ?? ''}',
        '${m['label'] ?? m['key'] ?? ''}',
        '${m['help'] ?? ''}',
        '${m['link'] ?? ''}',
        rawType: m['type'] is String ? m['type'] as String : '',
        options: m['options'] is List
            ? [
                for (final o in (m['options'] as List).whereType<Map>()) SettingOption('${o['value'] ?? ''}', '${o['label'] ?? ''}'),
              ]
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'help': help,
        'link': link,
        if (rawType.isNotEmpty) 'type': rawType,
        if (options.isNotEmpty) 'options': [for (final o in options) o.toJson()],
      };

  /// The control plugin.json asks for, as the desktop reads it: no type,
  /// "text" and unknown types are text; a select whose options are missing,
  /// unlabeled or ambiguous (a repeated value or label) is text too.
  SettingType get type => switch (rawType) {
        'password' => SettingType.password,
        'boolean' => SettingType.boolean,
        'select' => validOptions(options) ? SettingType.select : SettingType.text,
        _ => SettingType.text,
      };

  /// The control to show for [saved], the value saved now: a boolean whose
  /// saved value is neither "true" nor "false" (nor unset) stays a text
  /// field, so the app never rewrites a value it doesn't understand.
  SettingType typeFor(String saved) {
    final t = type;
    if (t == SettingType.boolean && saved.isNotEmpty && saved != 'true' && saved != 'false') return SettingType.text;
    return t;
  }

  /// Whether a change saves at once (switches, selects) rather than with an
  /// explicit Save (text, passwords).
  static bool savesOnChange(SettingType t) => t == SettingType.boolean || t == SettingType.select;

  static bool validOptions(List<SettingOption> options) {
    if (options.isEmpty) return false;
    final values = <String>{}, labels = <String>{};
    for (final o in options) {
      if (o.label.isEmpty || !values.add(o.value) || !labels.add(o.label)) return false;
    }
    return true;
  }
}

/// Kinds of what the app fetches itself for a plugin (requestHeaders kinds).
enum MediaKind { image, audio }

/// One entry of plugin.json's requestHeaders (MyGo Music 0.1.19): headers
/// the app sends with the plugin's pictures and audio on [hosts]. Hosts are
/// names, *.domain, or {setting:key}; header values may hold {setting:key}
/// and {storage:key}. How they apply is core/plugin/media_request.dart.
class RequestHeaderRule {
  const RequestHeaderRule({required this.hosts, required this.kinds, required this.headers});
  final List<String> hosts;

  /// Empty: both kinds.
  final List<MediaKind> kinds;
  final Map<String, String> headers;

  bool appliesTo(MediaKind kind) => kinds.isEmpty || kinds.contains(kind);

  Map<String, dynamic> toJson() => {
        'hosts': hosts,
        if (kinds.isNotEmpty) 'kinds': [for (final k in kinds) k.name],
        'headers': headers,
      };

  /// Reads and checks plugin.json's requestHeaders as the desktop's
  /// checkRequestHeaders does: each needs hosts and headers; kinds are image
  /// or audio; a host is {setting:key} or a name or *.domain the network
  /// permission covers (never *); Host and Content-Length can't be set.
  static List<RequestHeaderRule> parseAll(Object? raw, List<String> network) {
    if (raw == null) return const [];
    if (raw is! List) throw const FormatException('requestHeaders must be a list');
    final out = <RequestHeaderRule>[];
    for (var i = 0; i < raw.length; i++) {
      final r = raw[i];
      if (r is! Map) throw FormatException('requestHeaders[$i] must be an object');
      final hosts = r['hosts'] is List ? (r['hosts'] as List).map((e) => '$e').toList() : <String>[];
      final headers = r['headers'] is Map ? (r['headers'] as Map).map((k, v) => MapEntry('$k', '$v')) : <String, String>{};
      if (hosts.isEmpty || headers.isEmpty) throw FormatException('requestHeaders[$i] needs hosts and headers');
      final kinds = <MediaKind>[];
      for (final k in r['kinds'] is List ? r['kinds'] as List : const []) {
        final kind = MediaKind.values.where((m) => m.name == '$k');
        if (kind.isEmpty) throw FormatException('requestHeaders[$i]: kind "$k" isn\'t image or audio');
        kinds.add(kind.first);
      }
      for (final h in hosts) {
        if (h.startsWith('{setting:')) {
          final key = h.substring('{setting:'.length);
          if (!key.endsWith('}') || key.length < 2 || key.substring(0, key.length - 1).contains(RegExp(r'[{}]'))) {
            throw FormatException('requestHeaders[$i]: host "$h" is neither a host nor {setting:key}');
          }
          continue;
        }
        if (h == '*' || h.contains(RegExp(r'[{}/:]'))) throw FormatException('requestHeaders[$i]: host "$h" isn\'t a host or *.domain');
        if (!networkCoversPattern(network, h)) throw FormatException('requestHeaders[$i]: host "$h" is outside the network permission');
      }
      for (final name in headers.keys) {
        final l = name.toLowerCase();
        if (l == 'host' || l == 'content-length') throw FormatException('requestHeaders[$i]: $name isn\'t a header it can set');
      }
      out.add(RequestHeaderRule(hosts: hosts, kinds: kinds, headers: headers));
    }
    return out;
  }
}

class NavItem {
  NavItem({required this.title, this.page = '', this.builtin = '', this.icon = ''});
  final String title, page, builtin, icon;
  factory NavItem.fromJson(Map m) => NavItem(
      title: '${m['title'] ?? ''}', page: '${m['page'] ?? ''}', builtin: '${m['builtin'] ?? ''}', icon: '${m['icon'] ?? ''}');
  Map<String, dynamic> toJson() => {'title': title, 'page': page, 'builtin': builtin, 'icon': icon};
}

class Manifest {
  Manifest({
    required this.id,
    required this.name,
    required this.version,
    required this.minAppVersion,
    required this.main,
    required this.playback,
    required this.network,
    required this.process,
    required this.settings,
    required this.navigation,
    this.requestHeaders = const [],
  });

  final String id, name, version, minAppVersion, main, playback;
  final List<String> network;
  final List<String> process;
  final List<SettingDef> settings;
  final List<NavItem> navigation;
  final List<RequestHeaderRule> requestHeaders;

  static Manifest parse(String text, {String where = 'plugin.json'}) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } catch (e) {
      throw FormatException('$where: $e');
    }
    if (raw is! Map) throw FormatException('$where: not an object');
    final id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) throw FormatException('$where: plugin.json needs an id');
    // The id names the plugin's folders, so it may not lead out of them.
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(id)) throw FormatException('$where: a plugin can\'t be called "$id"');
    final perms = raw['permissions'] is Map ? raw['permissions'] as Map : const {};
    final net = perms['network'] is List ? (perms['network'] as List).map((e) => '$e').toList() : <String>[];
    final proc = perms['process'];
    final process = proc == true
        ? ['*']
        : proc is List
            ? proc.map((e) => '$e').toList()
            : <String>[];
    final minApp = '${raw['minAppVersion'] ?? ''}';
    if (minApp.isNotEmpty && versionNumbers(minApp) == null) {
      throw FormatException('$where: minAppVersion isn\'t a version such as 0.1.8: "$minApp"');
    }
    final main = '${raw['main'] ?? ''}'.isEmpty ? 'index.js' : '${raw['main']}';
    if (!isLocalPath(main)) throw FormatException('$where: main must be a file in the plugin\'s folder: "$main"');
    final List<RequestHeaderRule> requestHeaders;
    try {
      requestHeaders = RequestHeaderRule.parseAll(raw['requestHeaders'], net);
    } on FormatException catch (e) {
      throw FormatException('$where: ${e.message}');
    }
    return Manifest(
      id: id,
      name: '${raw['name'] ?? ''}'.isEmpty ? id : '${raw['name']}',
      version: '${raw['version'] ?? ''}',
      minAppVersion: minApp,
      main: main,
      playback: '${raw['playback'] ?? ''}'.isEmpty ? 'stream' : '${raw['playback']}',
      network: net,
      process: process,
      settings: raw['settings'] is List ? (raw['settings'] as List).whereType<Map>().map(SettingDef.fromJson).toList() : [],
      navigation:
          raw['navigation'] is List ? (raw['navigation'] as List).whereType<Map>().map(NavItem.fromJson).toList() : [],
      requestHeaders: requestHeaders,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'minAppVersion': minAppVersion,
        'main': main,
        'playback': playback,
        'permissions': {'network': network, 'process': process},
        'settings': settings.map((s) => s.toJson()).toList(),
        'navigation': navigation.map((n) => n.toJson()).toList(),
        if (requestHeaders.isNotEmpty) 'requestHeaders': [for (final r in requestHeaders) r.toJson()],
      };
}

/// Whether a host is one the network permission lets fetch reach, as the
/// desktop's webapi.AllowHosts decides it: exact names, *.suffix, or *.
bool hostAllowed(List<String> allow, String host) {
  final h = host.toLowerCase();
  for (var a in allow) {
    a = a.toLowerCase();
    if (a == '*') return true;
    if (a.startsWith('*.')) {
      if (h.endsWith(a.substring(1))) return true;
    } else if (a == h) {
      return true;
    }
  }
  return false;
}

/// Whether the network permission reaches every host [pattern] does (a host
/// or *.domain), as the desktop's coversPattern: *.example.com covers
/// a.example.com and *.a.example.com.
bool networkCoversPattern(List<String> allow, String pattern) {
  final p = pattern.toLowerCase();
  for (var a in allow) {
    a = a.toLowerCase();
    if (a == '*' || a == p) return true;
    if (a.startsWith('*.') && (p.startsWith('*') ? p.substring(1) : p).endsWith(a.substring(1))) return true;
  }
  return false;
}

/// Whether [path] is relative and stays inside its folder (Go's
/// filepath.IsLocal, for plugin.json's main).
bool isLocalPath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.startsWith('\\') || path.contains(':') || path.contains('\\')) return false;
  var depth = 0;
  for (final part in path.split('/')) {
    if (part == '..') {
      if (--depth < 0) return false;
    } else if (part.isNotEmpty && part != '.') {
      depth++;
    }
  }
  return depth > 0;
}
