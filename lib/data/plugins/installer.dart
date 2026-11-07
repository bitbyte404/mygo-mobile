// Installing plugins: from a GitHub repository (the default branch's zip,
// plugin.json at the root or in one folder), or from a zip file. Each install
// is two steps: [Installer.prepareGitHub] / [Installer.prepareZipBytes]
// unpack in memory and read plugin.json so the app can show the permissions,
// then [PendingInstall.commit] writes it into the Store. Updates are checked
// against the repository's plugin.json.
//
// Where GitHub is reached is a [GitHubEndpoints]: codeload.github.com and
// raw.githubusercontent.com directly on the phone; through the relay in the
// browser (codeload sends no CORS headers a page could use).
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/core/storage/store.dart';

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

  static const fileName = '.mygo-origin.json';

  Map<String, dynamic> toJson() => {'kind': kind, 'repo': repo, 'branch': branch, 'installedAt': installedAt};
  factory Origin.fromJson(Map m) => Origin(
      kind: '${m['kind'] ?? 'zip'}', repo: '${m['repo'] ?? ''}', branch: '${m['branch'] ?? ''}', installedAt: (m['installedAt'] as num?)?.toInt() ?? 0);

  static Future<Origin?> read(Store store, String pluginDir) async {
    final m = await store.readJson('$pluginDir/$fileName');
    return m is Map ? Origin.fromJson(m) : null;
  }
}

class InstallError implements Exception {
  InstallError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where to download a repository's zip and plugin.json.
class GitHubEndpoints {
  const GitHubEndpoints({required this.zip, required this.manifest, this.headers = const {}});
  final Uri Function(String repo, String branch) zip;
  final Uri Function(String repo, String branch) manifest;
  final Map<String, String> headers;

  static final direct = GitHubEndpoints(
    zip: (repo, branch) => Uri.parse('https://codeload.github.com/$repo/zip/refs/heads/$branch'),
    manifest: (repo, branch) => Uri.parse('https://raw.githubusercontent.com/$repo/$branch/plugin.json'),
    headers: const {'user-agent': 'mygo-mobile'},
  );

  /// Through the relay that serves the web app ([base] is the page's URL).
  static GitHubEndpoints relay(Uri base) => GitHubEndpoints(
        zip: (repo, branch) => base.resolve('api/github/zip').replace(queryParameters: {'repo': repo, 'branch': branch}),
        manifest: (repo, branch) => base.resolve('api/github/manifest').replace(queryParameters: {'repo': repo, 'branch': branch}),
      );
}

/// A plugin unpacked and read, not installed yet.
class PendingInstall {
  PendingInstall._(this.manifest, this.files, this.origin, this.previous);
  final Manifest manifest;

  /// The plugin's files, by path relative to the folder holding plugin.json.
  final Map<String, Uint8List> files;
  final Origin origin;

  /// The installed version's manifest, when this replaces one.
  final Manifest? previous;

  /// Hosts the new version reaches that the installed one didn't.
  List<String> get newHosts => previous == null ? const [] : manifest.network.where((h) => !previous!.network.contains(h)).toList();

  /// Writes the plugin to `plugins/<id>`, replacing what was there: first into
  /// a staging folder (which [PluginManager.init] clears if the app stops
  /// halfway), then moved into place.
  Future<void> commit(Store store, String pluginsDir) async {
    final staging = '$pluginsDir/.incoming-${manifest.id}';
    await store.delete(staging);
    for (final e in files.entries) {
      await store.write('$staging/${e.key}', e.value);
    }
    await store.writeJson('$staging/${Origin.fileName}', origin.toJson());
    await store.move(staging, '$pluginsDir/${manifest.id}');
    discard();
  }

  void discard() => files.clear();
}

class Installer {
  Installer({required this.store, required this.pluginsDir, GitHubEndpoints? github, http.Client? client})
      : github = github ?? GitHubEndpoints.direct,
        _http = client ?? http.Client();
  final Store store;
  final String pluginsDir;
  final GitHubEndpoints github;
  final http.Client _http;

  static const maxZip = 64 << 20;
  static const maxUnpacked = 256 << 20;

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
    final res = await _http.send(http.Request('GET', url)..headers.addAll(github.headers));
    if (res.statusCode != 200) {
      var detail = '';
      try {
        final body = await res.stream.bytesToString();
        final j = jsonDecode(body);
        if (j is Map && j['error'] != null) detail = ' (${j['error']})';
      } catch (_) {}
      throw InstallError('HTTP ${res.statusCode}: $url$detail');
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
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
        final zip = await _get(github.zip(repo, branch));
        return await _prepareZip(zip, Origin(kind: 'github', repo: repo, branch: branch, installedAt: DateTime.now().millisecondsSinceEpoch));
      } on InstallError catch (e) {
        last = e;
        if (!e.message.startsWith('HTTP 404')) rethrow;
      }
    }
    throw last ?? InstallError('could not download $repo');
  }

  Future<PendingInstall> prepareZipBytes(Uint8List bytes) async {
    if (bytes.length > maxZip) throw InstallError('the zip is too big');
    return _prepareZip(bytes, Origin(kind: 'zip', installedAt: DateTime.now().millisecondsSinceEpoch));
  }

  Future<PendingInstall> _prepareZip(Uint8List bytes, Origin origin) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw InstallError('not a zip file');
    }
    final names = <String, ArchiveFile>{};
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.split('/').contains('..')) throw InstallError('unsafe path in zip: $name');
      if (entry.isSymbolicLink || !entry.isFile) continue;
      names[name] = entry;
    }
    final root = pluginRoot(names.keys);
    final files = <String, Uint8List>{};
    var total = 0;
    for (final e in names.entries) {
      if (!e.key.startsWith(root)) continue;
      final rel = e.key.substring(root.length);
      if (rel.isEmpty || rel.split('/').any((p) => p == '.git' || p.startsWith('__MACOSX')) || rel == Origin.fileName) continue;
      total += e.value.size;
      if (total > maxUnpacked) throw InstallError('the plugin is too big');
      files[rel] = e.value.readBytes() ?? Uint8List(0);
    }
    final mj = files['plugin.json'];
    if (mj == null) throw InstallError('no plugin.json at the top of the zip');
    final Manifest manifest;
    try {
      manifest = Manifest.parse(utf8.decode(mj), where: 'plugin.json');
    } on FormatException catch (e) {
      throw InstallError(e.message);
    }
    if (manifest.minAppVersion.isNotEmpty && isNewerVersion(manifest.minAppVersion, kPluginApiVersion)) {
      throw InstallError('needsNewerApp:${manifest.minAppVersion}');
    }
    if (!files.containsKey(manifest.main)) throw InstallError('${manifest.main} is missing');
    Manifest? previous;
    final prev = await store.readString('$pluginsDir/${manifest.id}/plugin.json');
    if (prev != null) {
      try {
        previous = Manifest.parse(prev);
      } catch (_) {}
    }
    return PendingInstall._(manifest, files, origin, previous);
  }

  /// The prefix ('' or 'folder/') of the shallowest plugin.json: the zip's
  /// root, or the one folder GitHub wraps a repository in.
  static String pluginRoot(Iterable<String> names) {
    if (names.contains('plugin.json')) return '';
    for (final n in names) {
      final parts = n.split('/');
      if (parts.length == 2 && parts[1] == 'plugin.json' && !parts[0].startsWith('__MACOSX')) return '${parts[0]}/';
    }
    throw InstallError('no plugin.json at the top of the zip');
  }

  /// The version in the repository's plugin.json now, or null if unknown.
  Future<String?> latestVersion(Origin origin) async {
    if (origin.kind != 'github' || origin.repo.isEmpty) return null;
    final branch = origin.branch.isEmpty ? 'main' : origin.branch;
    try {
      final b = await _get(github.manifest(origin.repo, branch), limit: 1 << 20);
      return Manifest.parse(utf8.decode(b)).version;
    } catch (_) {
      return null;
    }
  }
}
