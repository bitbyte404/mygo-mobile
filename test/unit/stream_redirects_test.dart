// A stream's headers don't follow a redirect to another host on the phone
// either (data/player/stream_redirects.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mygo_mobile/core/plugin/media_request.dart';
import 'package:mygo_mobile/data/player/stream_redirects.dart';

void main() {
  final seen = <String, String?>{};
  StreamRedirects redirects(Map<String, String> hops) => StreamRedirects(
        client: () => MockClient((req) async {
          seen[req.url.toString()] = req.headers['cookie'];
          final to = hops[req.url.toString()];
          if (to != null) return http.Response('', 302, headers: {'location': to});
          return http.Response('x', 206);
        }),
      );

  setUp(seen.clear);

  test('without headers there is nothing to walk', () async {
    final r = await redirects({}).resolve(const MediaRequest('https://a.example.com/s.flac'));
    expect(r.url, 'https://a.example.com/s.flac');
    expect(seen, isEmpty);
  });

  test('to a host below: the headers go on', () async {
    final r = await redirects({'https://media.example.com/s': 'https://cdn.media.example.com/s?sig=1'})
        .resolve(const MediaRequest('https://media.example.com/s', {'cookie': 't'}));
    expect(r, const MediaRequest('https://cdn.media.example.com/s?sig=1', {'cookie': 't'}));
    expect(seen['https://cdn.media.example.com/s?sig=1'], 't');
  });

  test('to another host: the player gets it without them, and that host never sees them', () async {
    final r = await redirects({
      'https://media.example.com/s': '/t',
      'https://media.example.com/t': 'https://other.net/s.m4a',
    }).resolve(const MediaRequest('https://media.example.com/s', {'cookie': 't'}));
    expect(r, const MediaRequest('https://other.net/s.m4a'));
    expect(seen.containsKey('https://other.net/s.m4a'), isFalse);
    expect(seen['https://media.example.com/t'], 't');
  });

  test('a loop ends', () async {
    expect(
      redirects({'https://a.example.com/1': 'https://a.example.com/2', 'https://a.example.com/2': 'https://a.example.com/1'})
          .resolve(const MediaRequest('https://a.example.com/1', {'cookie': 't'})),
      throwsA(isA<http.ClientException>()),
    );
  });
}
