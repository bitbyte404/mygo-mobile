// Installing plugins: from a GitHub repository (the default branch's zip from
// codeload.github.com, plugin.json at the root or in one folder), or from a
// zip on the device. Each install is two steps: [prepare] unpacks and reads
// plugin.json so the app can show the permissions, then [PendingInstall.commit]
// moves it into place. Updates are checked against the repository's
// plugin.json on raw.githubusercontent.com: no GitHub API, so no rate limit.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../runtime/manifest.dart';

/// The MyGo Music version whose plugin API this app implements; a plugin's
/// minAppVersion is compared with it.
const kPluginApiVersion = '0.1.18';

/// Where a plugin came from, kept next to it as .mygo-origin.json.
class Origin {
  Origin({required this.kind, this.repo = '', this.branch = '', this.installedAt = 0});
  final String kind; // github | zip
  final String repo; // owner/repo
  final String branch;
  final int installedAt;

  Map<String, dynamic> toJson() => {'kind': kind, 'repo': repo, 'branch': branch, 'installedAt': installedAt};
  factory Origin.fromJson(Map m) => Origin(
      kind: '${m['kind'] ?? 'zip'}', repo: '${m['repo'] ?? ''}', branch: '${m['branch'] ?? ''}', installedAt: (m['installedAt'] as num?)?.toInt() ?? 0);

  static Origin? read(String pluginDir) {
    final f = File('$pluginDir/.mygo-origin.json');
    if (!f.existsSync()) return null;
    try {
      return Origin.fromJson(jsonDecode(f.readAsStringSync()) as Map);
    } catch (_) {
      return null;
    }
  }
}

class InstallError implements Exception {
  InstallError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A plugin unpacked and read, not installed yet.
class PendingInstall {
  PendingInstall._(this.manifest, this._root, this._tmp, this.origin, this.previous);
  final Manifest manifest;
  final Directory _root; // the folder with plugin.json, inside _tmp
  final Directory _tmp;
  final Origin origin;

  /// The installed version's manifest, when this replaces one.
  final Manifest? previous;

  /// Hosts the new version reaches that the installed one didn't.
  List<String> get newHosts => previous == null ? const [] : manifest.network.where((h) => !previous!.network.contains(h)).toList();

  Future<void> commit(String pluginsDir) async {
    final dest = Directory('$pluginsDir/${manifest.id}');
    final staging = Directory('$pluginsDir/.incoming-${manifest.id}');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    await _copyDir(_root, staging);
    File('${staging.path}/.mygo-origin.json').writeAsStringSync(jsonEncode(origin.toJson()));
    if (dest.existsSync()) dest.deleteSync(recursive: true);
    staging.renameSync(dest.path);
    discard();
  }

  void discard() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  }
}

class Installer {
  Installer({required this.pluginsDir, required this.tmpDir, HttpClient? http}) : _http = http ?? HttpClient();
  final String pluginsDir;
  final String tmpDir;
  final HttpClient _http;

  static const maxZip = 64 << 20;

  /// owner/repo from what the listener typed: owner/repo, a github.com
  /// address (with .git, /tree/..., or a trailing slash), or a deep link's repo.
  static String parseRepo(String input) {
    var s = input.trim();
    s = s.replaceFirst(RegExp(r'^(https?://)?(www\.)?github\.com/', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'^git@github\.com:', caseSensitive: false), '');
    final parts = s.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) throw InstallError('not a GitHub repository: $input');
    final owner = parts[0];
    final repo = parts[1].replaceFirst(RegExp(r'\.git$'), '');
    final ok = RegExp(r'^[A-Za-z0-9_.-]+$');
    if (!ok.hasMatch(owner) || !ok.hasMatch(repo)) throw InstallError('not a GitHub repository: $input');
    return '$owner/$repo';
  }

  Future<Uint8List> _get(Uri url, {int limit = maxZip}) async {
    final req = await _http.getUrl(url);
    req.headers.set('user-agent', 'mygo-mobile');
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw InstallError('HTTP ${res.statusCode}: $url');
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in res) {
      b.add(chunk);
      if (b.length > limit) throw InstallError('too big: $url');
    }
    return b.takeBytes();
  }

  /// Downloads the repository's default branch (main, else master).
  Future<PendingInstall> prepareGitHub(String repoInput) async {
    final repo = parseRepo(repoInput);
    InstallError? last;
    for (final branch in const ['main', 'master']) {
      try {
        final zip = await _get(Uri.parse('https://codeload.github.com/$repo/zip/refs/heads/$branch'));
        return await _prepareZip(zip, Origin(kind: 'github', repo: repo, branch: branch, installedAt: DateTime.now().millisecondsSinceEpoch));
      } on InstallError catch (e) {
        last = e;
        if (!e.message.startsWith('HTTP 404')) rethrow;
      }
    }
    throw last ?? InstallError('could not download $repo');
  }

  Future<PendingInstall> prepareZipFile(String path) async {
    final f = File(path);
    if (f.lengthSync() > maxZip) throw InstallError('the zip is too big');
    return _prepareZip(await f.readAsBytes(), Origin(kind: 'zip', installedAt: DateTime.now().millisecondsSinceEpoch));
  }

  Future<PendingInstall> prepareZipBytes(Uint8List bytes) async {
    if (bytes.length > maxZip) throw InstallError('the zip is too big');
    return _prepareZip(bytes, Origin(kind: 'zip', installedAt: DateTime.now().millisecondsSinceEpoch));
  }

  Future<PendingInstall> _prepareZip(Uint8List bytes, Origin origin) async {
    final tmp = Directory('$tmpDir/install-${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        throw InstallError('not a zip file');
      }
      var total = 0;
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        if (name.startsWith('/') || name.split('/').contains('..')) throw InstallError('unsafe path in zip: $name');
        if (entry.isSymbolicLink) continue;
        final out = '${tmp.path}/$name';
        if (entry.isFile) {
          total += entry.size;
          if (total > 256 << 20) throw InstallError('the plugin is too big');
          File(out)
            ..createSync(recursive: true)
            ..writeAsBytesSync(entry.content as List<int>);
        } else {
          Directory(out).createSync(recursive: true);
        }
      }
      final root = _pluginRoot(tmp);
      final manifest = Manifest.load(root.path);
      if (manifest.minAppVersion.isNotEmpty && isNewerVersion(manifest.minAppVersion, kPluginApiVersion)) {
        throw InstallError('needsNewerApp:${manifest.minAppVersion}');
      }
      if (!File('${root.path}/${manifest.main}').existsSync()) throw InstallError('${manifest.main} is missing');
      final prevDir = '$pluginsDir/${manifest.id}';
      Manifest? previous;
      if (File('$prevDir/plugin.json').existsSync()) {
        try {
          previous = Manifest.load(prevDir);
        } catch (_) {}
      }
      return PendingInstall._(manifest, root, tmp, origin, previous);
    } catch (e) {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      if (e is InstallError || e is FormatException) rethrow;
      throw InstallError('$e');
    }
  }

  /// The shallowest folder with a plugin.json: the zip's root, or the one
  /// folder GitHub wraps a repository in.
  static Directory _pluginRoot(Directory dir) {
    if (File('${dir.path}/plugin.json').existsSync()) return dir;
    final subs = dir.listSync().whereType<Directory>().where((d) => !d.path.split('/').last.startsWith('__MACOSX')).toList();
    for (final d in subs) {
      if (File('${d.path}/plugin.json').existsSync()) return d;
    }
    throw InstallError('no plugin.json at the top of the zip');
  }

  /// The version in the repository's plugin.json now, or null if unknown.
  Future<String?> latestVersion(Origin origin) async {
    if (origin.kind != 'github' || origin.repo.isEmpty) return null;
    final branch = origin.branch.isEmpty ? 'main' : origin.branch;
    try {
      final b = await _get(Uri.parse('https://raw.githubusercontent.com/${origin.repo}/$branch/plugin.json'), limit: 1 << 20);
      final m = Manifest.parse(utf8.decode(b));
      return m.version;
    } catch (_) {
      return null;
    }
  }
}

Future<void> _copyDir(Directory from, Directory to) async {
  to.createSync(recursive: true);
  for (final e in from.listSync(recursive: false)) {
    final name = e.path.split('/').last;
    if (e is Directory) {
      if (name == '.git') continue;
      await _copyDir(e, Directory('${to.path}/$name'));
    } else if (e is File) {
      e.copySync('${to.path}/$name');
    }
  }
}
