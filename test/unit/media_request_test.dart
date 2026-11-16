// {size} in picture URLs (MyGo Music 0.1.20) and plugin.json requestHeaders
// (0.1.19): core/plugin/media_request.dart and the manifest's checks.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/core/plugin/media_request.dart';

Manifest _m(Map<String, Object?> extra, {List<String> network = const ['api.example.com', '*.example.com']}) =>
    Manifest.parse(jsonEncode({'id': 'x', 'permissions': {'network': network}, ...extra}));

void main() {
  group('{size}', () {
    test('is filled in with the pixels shown', () {
      expect(MediaRequests.sizedImageUrl('https://img.example.com/c.jpg?param={size}y{size}', 120), 'https://img.example.com/c.jpg?param=120y120');
      expect(MediaRequests.sizedImageUrl('https://img.example.com/{size}/c.jpg', 40), 'https://img.example.com/40/c.jpg');
    });
    test('escaped as JavaScript URL writes it counts too', () {
      expect(MediaRequests.sizedImageUrl('https://img.example.com/c.jpg?s=%7Bsize%7D&t=%7bsize%7d', 300), 'https://img.example.com/c.jpg?s=300&t=300');
    });
    test('without a size asked for, 600', () {
      expect(MediaRequests.sizedImageUrl('https://img.example.com/{size}.jpg'), 'https://img.example.com/600.jpg');
      expect(MediaRequests.sizedImageUrl('https://img.example.com/{size}.jpg', 0), 'https://img.example.com/600.jpg');
    });
    test('a URL without it is left alone', () {
      const u = 'https://imge.kugou.com/stdmusic/400/a.jpg?size=big';
      expect(MediaRequests.sizedImageUrl(u, 120), u);
    });
    test('image() fills it in with no plugin too', () {
      expect(MediaRequests.image(null, 'https://a.example.com/{size}.jpg', px: 96), const MediaRequest('https://a.example.com/96.jpg'));
    });
  });

  group('requestHeaders', () {
    final m = _m({
      'settings': [{'key': 'server', 'label': 'Server'}],
      'requestHeaders': [
        {'hosts': ['{setting:server}'], 'kinds': ['image', 'audio'], 'headers': {'cookie': 'music-token={storage:token}'}},
        {'hosts': ['img.example.com'], 'kinds': ['image'], 'headers': {'referer': 'https://example.com/', 'cookie': 'ignored'}},
        {'hosts': ['*.example.com'], 'headers': {'x-app': 'mygo'}},
      ],
    }, network: ['*.example.com', 'nas.local']);
    final values = PluginValues(
      setting: (k) => {'server': 'https://nas.local:5666'}[k],
      storage: (k) => {'token': 't0k'}[k],
    );

    test('go to their hosts, placeholders filled in', () {
      expect(MediaRequests.headersFor(m, 'https://nas.local:5666/cover/1.jpg', MediaKind.image, values), {'cookie': 'music-token=t0k'});
      expect(MediaRequests.headersFor(m, 'https://img.example.com/a.jpg', MediaKind.image, values), {'referer': 'https://example.com/', 'cookie': 'ignored', 'x-app': 'mygo'});
    });
    test('kinds: a rule for images says nothing for audio', () {
      expect(MediaRequests.headersFor(m, 'https://img.example.com/a.m4a', MediaKind.audio, values), {'x-app': 'mygo'});
    });
    test('nothing for a host of none of them', () {
      expect(MediaRequests.headersFor(m, 'https://other.net/a.jpg', MediaKind.image, values), isEmpty);
      expect(MediaRequests.headersFor(m, 'file:///a.jpg', MediaKind.image, values), isEmpty);
    });
    test('a header whose value is not there yet is left out', () {
      final none = PluginValues(setting: (k) => 'nas.local:5666', storage: (_) => null);
      expect(MediaRequests.headersFor(m, 'http://nas.local:5666/a.jpg', MediaKind.image, none), isEmpty);
    });
    test('a stored number or object goes as its JSON; a line break never goes', () {
      final mm = _m({
        'requestHeaders': [
          {'hosts': ['api.example.com'], 'headers': {'a': '{storage:n}', 'b': '{storage:o}', 'c': '{storage:bad}'}},
        ],
      });
      final v = PluginValues(storage: (k) => {'n': 42, 'o': {'u': 1}, 'bad': 'x\r\nEvil: 1'}[k]);
      expect(MediaRequests.headersFor(mm, 'https://api.example.com/', MediaKind.audio, v), {'a': '42', 'b': '{"u":1}'});
    });
    test('a setting host counts only while the network permission reaches it', () {
      final v = PluginValues(setting: (_) => 'http://elsewhere.org', storage: (_) => 't');
      expect(MediaRequests.headersFor(m, 'http://elsewhere.org/a.jpg', MediaKind.image, v), isEmpty);
    });
    test('audio: the stream answer\'s headers come first, whatever their case', () {
      final r = MediaRequests.audio(m, 'https://nas.local:5666/s.flac', streamHeaders: {'Cookie': 'mine'}, values: values);
      expect(r.headers, {'Cookie': 'mine'});
      final r2 = MediaRequests.audio(m, 'https://cdn.example.com/s.flac', streamHeaders: {'User-Agent': 'kg'}, values: values);
      expect(r2.headers, {'User-Agent': 'kg', 'x-app': 'mygo'});
    });
    test('the storage keys a runtime keeps the app told of', () {
      expect(MediaRequests.storageKeys(m), {'token'});
    });
    test('survive the manifest\'s trip through JSON (runtimes pass it so)', () {
      final again = Manifest.parse(jsonEncode(m.toJson()));
      expect(MediaRequests.headersFor(again, 'https://nas.local:5666/c.jpg', MediaKind.image, values), {'cookie': 'music-token=t0k'});
    });
  });

  group('redirects', () {
    test('headers go on to the same host and those below it, nowhere else', () {
      const h = {'cookie': 'a'};
      expect(MediaRequests.headersAfterRedirect('media.example.com', Uri.parse('https://media.example.com/b'), h), h);
      expect(MediaRequests.headersAfterRedirect('media.example.com', Uri.parse('https://cdn.media.example.com/b'), h), h);
      expect(MediaRequests.headersAfterRedirect('media.example.com', Uri.parse('https://example.com/b'), h), isEmpty);
      expect(MediaRequests.headersAfterRedirect('media.example.com', Uri.parse('https://evilmedia.example.com/b'), h), isEmpty);
    });
  });

  group('manifest checks', () {
    void bad(Map<String, Object?> extra, String why) => expect(() => _m(extra), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(why))));
    test('requestHeaders as the desktop checks them', () {
      bad({'requestHeaders': [{'hosts': ['api.example.com']}]}, 'needs hosts and headers');
      bad({'requestHeaders': [{'hosts': ['*'], 'headers': {'a': 'b'}}]}, 'isn\'t a host');
      bad({'requestHeaders': [{'hosts': ['evil.net'], 'headers': {'a': 'b'}}]}, 'outside the network permission');
      bad({'requestHeaders': [{'hosts': ['api.example.com'], 'kinds': ['video'], 'headers': {'a': 'b'}}]}, 'isn\'t image or audio');
      bad({'requestHeaders': [{'hosts': ['api.example.com'], 'headers': {'Host': 'b'}}]}, 'can set');
      bad({'requestHeaders': [{'hosts': ['{setting:}'], 'headers': {'a': 'b'}}]}, 'neither a host');
      expect(_m({'requestHeaders': [{'hosts': ['*.a.example.com', '{setting:s}'], 'headers': {'a': 'b'}}]}).requestHeaders, hasLength(1));
    });
    test('id and main stay inside the plugin\'s folders', () {
      for (final id in ['..', '../x', 'a/b', '.hidden', '']) {
        expect(() => Manifest.parse(jsonEncode({'id': id})), throwsFormatException, reason: id);
      }
      for (final main in ['../x.js', '/etc/x.js', 'a/../../x.js', 'C:\\x.js']) {
        expect(() => Manifest.parse(jsonEncode({'id': 'x', 'main': main})), throwsFormatException, reason: main);
      }
      expect(Manifest.parse(jsonEncode({'id': 'kugou-lite', 'main': 'dist/index.js'})).main, 'dist/index.js');
    });
  });
}
