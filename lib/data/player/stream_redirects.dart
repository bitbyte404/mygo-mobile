// A stream with headers, followed through its redirects before the player
// gets it, so the headers never reach another host (MyGo Music 0.1.19,
// music.HeadersStay). The player can't be trusted with that itself: on the
// phone just_audio sends headers through a local proxy whose HttpClient
// keeps them on every hop. So the redirects are walked here, one request at
// a time, with MediaRequests.headersAfterRedirect deciding what goes on; the
// player is handed where they end, with what headers are left. (On the web
// the relay walks them, with the same rule: relay/relay.go.)
import 'package:http/http.dart' as http;

import 'package:mygo_mobile/core/plugin/media_request.dart';

class StreamRedirects {
  StreamRedirects({http.Client Function()? client}) : _client = client ?? http.Client.new;
  final http.Client Function() _client;

  static const maxHops = 10;
  static const timeout = Duration(seconds: 20);

  /// Where [r] ends up, and the headers to ask there with. A request without
  /// headers is answered as it is: there is nothing to keep from anyone.
  Future<MediaRequest> resolve(MediaRequest r) async {
    if (r.headers.isEmpty) return r;
    final start = Uri.parse(r.url);
    final client = _client();
    try {
      var at = start;
      var headers = r.headers;
      for (var hop = 0; hop <= maxHops; hop++) {
        final req = http.Request('GET', at)
          ..followRedirects = false
          ..headers.addAll(headers)
          ..headers['range'] = 'bytes=0-0';
        final res = await client.send(req).timeout(timeout);
        // Only the status line and headers are wanted.
        res.stream.listen(null).cancel();
        final loc = res.headers['location'];
        if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400 && loc != null)) {
          if (loc == null) break;
          at = at.resolve(loc);
          headers = MediaRequests.headersAfterRedirect(start.host, at, headers);
          if (headers.isEmpty) return MediaRequest(at.toString());
          continue;
        }
        return MediaRequest(at.toString(), headers);
      }
      throw http.ClientException('too many redirects', start);
    } finally {
      client.close();
    }
  }
}
