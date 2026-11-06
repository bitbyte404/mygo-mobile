// Live, headless test: loads the real kugou-lite plugin through this app's
// runtime (QuickJS via libmygojs, host API in Dart) as the signed-in test user,
// and calls the exports the app uses. Needs the network, the host build of
// libmygojs (native/build.sh host) and the fixture copied from the desktop
// harness:
//   test/fixtures/kugou-data/kugou-lite/storage.json   (gitignored: it holds a sign-in)
// Run: MYGOJS_LIB=native/build/host/libmygojs.so flutter test test/kugou_live_test.dart
// Results are written to build/kugou_live_results.json.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/runtime/plugin_host.dart';

const pluginDir = String.fromEnvironment('KUGOU_DIR', defaultValue: '/workspace/work/mygo-music-kugou-lite');

void main() {
  late PluginHost host;
  late Directory dataRoot;
  final results = <String, Object?>{};
  final logs = <String>[];

  setUpAll(() {
    final fixture = File('test/fixtures/kugou-data/kugou-lite/storage.json');
    if (!fixture.existsSync()) fail('missing ${fixture.path}');
    dataRoot = Directory.systemTemp.createTempSync('mygo-data-');
    Directory('${dataRoot.path}/kugou-lite').createSync();
    fixture.copySync('${dataRoot.path}/kugou-lite/storage.json');
    PluginHost.preludeSource = File('assets/js/prelude.js').readAsStringSync();
    host = PluginHost(
      dir: pluginDir,
      dataRoot: dataRoot.path,
      language: 'zh-CN',
      platform: 'android',
      arch: 'arm64',
      onEvent: (type, data) => logs.add('$type ${jsonEncode(data)}'),
    );
    host.start();
  });

  tearDownAll(() {
    host.close();
    File('build/kugou_live_results.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'results': results, 'logs': logs}));
    dataRoot.deleteSync(recursive: true);
  });

  test('exports', () {
    results['exports'] = host.exports.toList()..sort();
    expect(host.exports, containsAll(['home', 'browse', 'search', 'liked', 'stream', 'lyrics', 'signIn', 'account']));
  });

  test('account (signed in)', () async {
    final a = await host.call('account') as Map?;
    results['account'] = a == null ? null : {'id': a['id'], 'name': a['name'], 'page': a['page']};
    expect(a, isNotNull);
    expect(a!['id'], isNotEmpty);
  });

  test('home', () async {
    final b = await host.call('home') as Map;
    final sections = (b['sections'] as List).cast<Map>();
    results['home'] = {
      'title': b['title'],
      'sections': [
        for (final s in sections)
          {
            'title': s['title'],
            for (final k in ['tracks', 'albums', 'artists', 'playlists', 'stations', 'links'])
              if (s[k] is List) k: (s[k] as List).length,
            if (s['morePage'] != null) 'morePage': s['morePage'],
          }
      ],
    };
    expect(sections, isNotEmpty);
  });

  test("browse('recent')", () async {
    final b = await host.call('browse', {'page': 'recent'}) as Map;
    final sections = (b['sections'] as List).cast<Map>();
    final tracks = sections.expand((s) => (s['tracks'] as List?) ?? const []).cast<Map>().toList();
    results['browse_recent'] = {
      'title': b['title'],
      'tracks': tracks.length,
      'first': tracks.take(3).map((t) => '${t['name']} - ${(t['artists'] as List?)?.map((a) => a['name']).join('/')}').toList(),
    };
    expect(tracks, isNotEmpty);
  });

  late String trackId;
  test('search tracks', () async {
    final r = await host.call('search', {'query': '周杰伦 晴天', 'kind': 'tracks', 'offset': 0}) as Map;
    final tracks = (r['tracks'] as List).cast<Map>();
    results['search_tracks'] = {
      'count': tracks.length,
      'more': r['more'],
      'first': tracks.take(3).map((t) => {'id': t['id'], 'name': t['name'], 'artists': (t['artists'] as List?)?.map((a) => a['name']).toList(), 'duration': t['duration']}).toList(),
    };
    expect(tracks, isNotEmpty);
    trackId = '${tracks.first['id']}';
  });

  test('search albums/artists/playlists', () async {
    for (final kind in ['albums', 'artists', 'playlists']) {
      final r = await host.call('search', {'query': '周杰伦', 'kind': kind, 'offset': 0}) as Map;
      results['search_$kind'] = (r[kind] as List?)?.length ?? 0;
    }
    expect(results['search_albums'], greaterThan(0));
  });

  test('liked', () async {
    final r = await host.call('liked', {'offset': 0}) as Map;
    final tracks = (r['tracks'] as List).cast<Map>();
    results['liked'] = {'count': tracks.length, 'more': r['more'], 'first': tracks.take(3).map((t) => t['name']).toList()};
    expect(tracks, isNotEmpty);
  });

  test('stream lossless is FLAC', () async {
    final s = await host.call('stream', {'id': trackId, 'quality': 'lossless'}) as Map;
    final url = '${s['url']}';
    if (Platform.environment['MYGO_DUMP_URL'] != null) File(Platform.environment['MYGO_DUMP_URL']!).writeAsStringSync(url);
    results['stream_lossless'] = {
      'type': s['type'],
      'quality': s['quality'],
      'bitRate': s['bitRate'],
      'size': s['size'],
      'headers': s['headers'],
      'urlHost': Uri.tryParse(url)?.host,
      'urlPathEnd': url.split('?').first.split('/').last,
    };
    expect(s['type'], 'flac');
    expect(url, startsWith('http'));
    // And the URL really serves FLAC: read its first bytes.
    final c = HttpClient();
    final proxy = Platform.environment['MYGO_HTTP_PROXY'];
    if (proxy != null) c.findProxy = (_) => 'PROXY $proxy';
    final req = await c.getUrl(Uri.parse(url));
    (s['headers'] as Map?)?.forEach((k, v) => req.headers.set('$k', '$v'));
    req.headers.set('range', 'bytes=0-3');
    final res = await req.close();
    final head = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    c.close(force: true);
    results['stream_lossless']!;
    (results['stream_lossless'] as Map)['httpStatus'] = res.statusCode;
    (results['stream_lossless'] as Map)['magic'] = ascii.decode(head.take(4).toList(), allowInvalid: true);
    expect(ascii.decode(head.take(4).toList(), allowInvalid: true), 'fLaC');
  });

  test('stream standard', () async {
    final s = await host.call('stream', {'id': trackId, 'quality': 'standard'}) as Map;
    results['stream_standard'] = {'type': s['type'], 'bitRate': s['bitRate']};
    expect(s['url'], startsWith('http'));
  });

  test('lyrics', () async {
    final l = await host.call('lyrics', {'id': trackId}) as Map;
    final lines = (l['lines'] as List?) ?? const [];
    results['lyrics'] = {
      'lines': lines.length,
      'lrcChars': (l['lrc'] as String?)?.length ?? 0,
      'sample': lines.skip(2).take(3).map((x) => {'start': x['start'], 'text': x['text'] ?? (x['words'] as List?)?.map((w) => w['text']).join(), 'words': (x['words'] as List?)?.length}).toList(),
    };
    expect(lines.isNotEmpty || (l['lrc'] as String? ?? '').isNotEmpty, isTrue);
  });

  test('comments', () async {
    if (!host.exports.contains('comments')) return;
    final c = await host.call('comments', {'trackId': trackId, 'offset': 0}) as Map;
    results['comments'] = {'count': (c['comments'] as List?)?.length, 'total': c['total']};
  });

  test('unsupported export throws unsupported', () async {
    await expectLater(host.call('remoteState'), throwsA(isA<PluginError>().having((e) => e.code, 'code', 'unsupported')));
  });
}
