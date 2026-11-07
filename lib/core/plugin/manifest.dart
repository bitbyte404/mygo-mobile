// A plugin's plugin.json, as the desktop app reads it (internal/plugin.Manifest).
import 'dart:convert';

class SettingDef {
  SettingDef(this.key, this.label, this.help, this.link);
  final String key, label, help, link;
  factory SettingDef.fromJson(Map m) => SettingDef(
      '${m['key'] ?? ''}', '${m['label'] ?? m['key'] ?? ''}', '${m['help'] ?? ''}', '${m['link'] ?? ''}');
  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'help': help, 'link': link};
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
  });

  final String id, name, version, minAppVersion, main, playback;
  final List<String> network;
  final List<String> process;
  final List<SettingDef> settings;
  final List<NavItem> navigation;

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
    if (id.contains('/') || id.contains('\\') || id.startsWith('.')) throw FormatException('$where: bad id "$id"');
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
    return Manifest(
      id: id,
      name: '${raw['name'] ?? ''}'.isEmpty ? id : '${raw['name']}',
      version: '${raw['version'] ?? ''}',
      minAppVersion: minApp,
      main: '${raw['main'] ?? ''}'.isEmpty ? 'index.js' : '${raw['main']}',
      playback: '${raw['playback'] ?? ''}'.isEmpty ? 'stream' : '${raw['playback']}',
      network: net,
      process: process,
      settings: raw['settings'] is List ? (raw['settings'] as List).whereType<Map>().map(SettingDef.fromJson).toList() : [],
      navigation:
          raw['navigation'] is List ? (raw['navigation'] as List).whereType<Map>().map(NavItem.fromJson).toList() : [],
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
      };
}

/// The numbers of a version such as v1.2.3, or null when it isn't one.
List<int>? versionNumbers(String tag) {
  var t = tag.trim();
  if (t.startsWith('v') || t.startsWith('V')) t = t.substring(1);
  final core = t.split(RegExp(r'[-+]')).first;
  if (core.isEmpty) return null;
  final out = <int>[];
  for (final p in core.split('.')) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    out.add(n);
  }
  return out;
}

/// Whether [latest] is a newer version than [installed]. Both must be versions.
bool isNewerVersion(String latest, String installed) {
  final a = versionNumbers(latest), b = versionNumbers(installed);
  if (a == null || b == null) return false;
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
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
