// Every way into an install ends in a message the listener sees. These go in
// the way a mygo-music://install-plugin link and the web app's ?install= do
// (installFromLink / installFromQuery, what main.dart calls), through the
// one InstallFlow and its NavigatorInstallPresenter, with the network faked:
// a too-new plugin, a network failure, a broken plugin.json, a bad link, and
// a plugin that installs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mygo_mobile/app/app.dart' show navigatorKey;
import 'package:mygo_mobile/core/storage/store.dart';
import 'package:mygo_mobile/data/plugins/installer.dart';
import 'package:mygo_mobile/features/plugins/install_flow.dart';
import 'package:mygo_mobile/l10n/strings.dart';
import 'package:mygo_mobile/ui/ui.dart';

class _MemStore implements Store {
  final files = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String path) async => files[path];
  @override
  Future<void> write(String path, List<int> bytes) async => files[path] = Uint8List.fromList(bytes);
  @override
  Future<void> delete(String path) async => files.removeWhere((k, _) => k == path || k.startsWith('$path/'));
  @override
  Future<List<String>> list(String dir) async => {
        for (final k in files.keys)
          if (k.startsWith('$dir/')) k.substring(dir.length + 1).split('/').first,
      }.toList();
  @override
  Future<void> move(String from, String to) async {
    await delete(to);
    for (final k in files.keys.where((k) => k.startsWith('$from/')).toList()) {
      files['$to/${k.substring(from.length + 1)}'] = files.remove(k)!;
    }
  }

  @override
  String? localPath(String path) => null;
}

Uint8List _zip(Map<String, String> files, {String folder = 'repo-main'}) {
  final a = Archive();
  files.forEach((name, text) => a.addFile(ArchiveFile.string('$folder/$name', text)));
  return ZipEncoder().encodeBytes(a);
}

final _s = S('zh-CN');

/// Serves [zip] as every repository's main branch (or fails as [fail] says).
void _useFlow(_MemStore store, {Uint8List? zip, Object? fail, List<String>? committed}) {
  final client = MockClient((req) async {
    if (fail != null) throw fail;
    if (zip != null && req.url.path.endsWith('/main')) return http.Response.bytes(zip, 200);
    return http.Response('not found', 404);
  });
  final installer = Installer(store: store, pluginsDir: 'plugins', client: client);
  installFlowFactory = () => InstallFlow(
        prepare: (src) => switch (src) {
          GitHubSource(:final repo) => installer.prepareGitHub(repo),
          ZipSource(:final bytes) => bytes().then(installer.prepareZipBytes),
        },
        commit: (pending, onStep) async {
          await pending.commit(store, 'plugins');
          committed?.add(pending.manifest.id);
          return null;
        },
        presenter: NavigatorInstallPresenter(navigatorKey, () => _s),
        strings: () => _s,
      );
}

Widget _app() => MaterialApp(
      navigatorKey: navigatorKey,
      theme: mgTheme(MgPalette.lightPalette),
      home: const Scaffold(body: SizedBox.expand()),
    );

/// Lets the install run: its futures, its dialogs' animations.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _manifest(Map<String, Object?> m) => jsonEncode({'id': 'demo', 'name': 'Demo', 'version': '1.0.0', ...m});

void main() {
  tearDown(() => installFlowFactory = () => throw StateError('no flow'));

  testWidgets('a link to a plugin that needs a newer app says so', (tester) async {
    await tester.pumpWidget(_app());
    _useFlow(_MemStore(), zip: _zip({'plugin.json': _manifest({'minAppVersion': '0.1.99'}), 'index.js': ''}));
    final done = installFromLink(Uri.parse('mygo-music://install-plugin?repo=someone/demo'));
    expect(done, isNotNull);
    await _settle(tester);
    expect(await done, InstallOutcome.failed);
    expect(find.textContaining('安装失败'), findsOneWidget);
    expect(find.textContaining('需要更新版本的 MyGo Music'), findsOneWidget);
    expect(find.textContaining('0.1.99'), findsOneWidget);
    expect(find.textContaining('0.1.25'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8)); // the toast goes
    expect(find.textContaining('安装失败'), findsNothing);
  });

  testWidgets('?install= when the download fails says it was the network', (tester) async {
    await tester.pumpWidget(_app());
    _useFlow(_MemStore(), fail: const SocketException('connection refused'));
    final done = installFromQuery({'install': 'someone/demo'});
    await _settle(tester);
    expect(await done, InstallOutcome.failed);
    expect(find.textContaining('下载失败，请检查网络'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('a link to a broken plugin.json says the plugin is invalid', (tester) async {
    await tester.pumpWidget(_app());
    _useFlow(_MemStore(), zip: _zip({'plugin.json': '{"name": "no id"}'}));
    final done = installFromLink(Uri.parse('mygo-music://install-plugin?repo=someone/demo'));
    await _settle(tester);
    expect(await done, InstallOutcome.failed);
    expect(find.textContaining('这不是有效的 MyGo Music 插件'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('a link without a repository, and a missing one, say so', (tester) async {
    await tester.pumpWidget(_app());
    _useFlow(_MemStore(), zip: _zip({'plugin.json': _manifest({}), 'index.js': ''}), );
    var done = installFromLink(Uri.parse('mygo-music://install-plugin'));
    await _settle(tester);
    expect(await done, InstallOutcome.failed);
    expect(find.textContaining('这不是 GitHub 仓库地址'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));

    _useFlow(_MemStore(), zip: null); // every branch 404s
    done = installFromQuery({'repo': 'someone/gone'});
    await _settle(tester);
    expect(await done, InstallOutcome.failed);
    expect(find.textContaining('找不到这个仓库'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('?install= that works asks first, then says it is installed', (tester) async {
    await tester.pumpWidget(_app());
    final committed = <String>[];
    _useFlow(_MemStore(), zip: _zip({'plugin.json': _manifest({'minAppVersion': '0.1.20'}), 'index.js': 'export function home() {}'}), committed: committed);
    final done = installFromQuery({'install': 'someone/demo'});
    await _settle(tester);
    expect(find.text('安装这个插件？'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    await tester.tap(find.text('安装').last);
    await _settle(tester);
    expect(await done, InstallOutcome.installed);
    expect(committed, ['demo']);
    expect(find.textContaining('已安装: Demo 1.0.0'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
  });

  test('links and addresses that ask for nothing install nothing', () {
    expect(installFromLink(Uri.parse('https://example.com/?repo=a/b')), isNull);
    expect(installFromLink(Uri.parse('mygo-music://other?repo=a/b')), isNull);
    expect(installFromQuery(const {}), isNull);
    expect(installSourceFromQuery({'install': 'a/b'}), isA<GitHubSource>().having((s) => s.repo, 'repo', 'a/b'));
  });

  test('every failure kind has its own words', () {
    for (final k in InstallErrorKind.values) {
      final text = installErrorText(InstallError('detail', kind: k, detail: '9.9.9'), _s);
      expect(text, startsWith('安装失败: '));
      expect(text, isNot(contains('needsNewerApp')));
    }
  });

  test('kugou-lite 1.5.1 (minAppVersion 0.1.20) passes the install check', () async {
    final dir = Directory('/workspace/work/mygo-music-kugou-lite');
    if (!dir.existsSync()) return markTestSkipped('kugou-lite checkout not here');
    final files = <String, String>{};
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final rel = f.path.substring(dir.path.length + 1);
      if (rel.startsWith('.git/') || rel.startsWith('node_modules/')) continue;
      if (rel == 'plugin.json' || rel == 'index.js' || rel.startsWith('locales/')) files[rel] = f.readAsStringSync();
    }
    final pending = await Installer(store: _MemStore(), pluginsDir: 'plugins').prepareZipBytes(_zip(files));
    expect(pending.manifest.id, 'kugou-lite');
    expect(pending.manifest.version, '1.5.1');
    expect(pending.manifest.minAppVersion, '0.1.20');
  });
}
