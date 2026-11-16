// The plugin API this app implements, and how versions compare. This is the
// only place the version lives: the installer's minAppVersion check and the
// About text both read it from here.

/// The MyGo Music version whose plugin API this app implements; a plugin's
/// minAppVersion is compared with it.
const kPluginApiVersion = '0.1.25';

/// Whether a plugin that asks for [minAppVersion] needs a newer app than
/// this one. An empty or unreadable minAppVersion never does.
bool needsNewerApp(String minAppVersion) => minAppVersion.isNotEmpty && isNewerVersion(minAppVersion, kPluginApiVersion);

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
