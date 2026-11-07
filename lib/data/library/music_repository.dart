// The app's one door to plugins: every catalogue, account and playback
// question goes through here, typed in and out (lib/core/models). Features
// never call a plugin's exports by name; this maps the desktop app's plugin
// API (internal/music/music.go) onto Dart methods. Errors are PluginError.
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/core/runtime/plugin_runtime.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';

class MusicRepository {
  MusicRepository(this._plugins);
  final PluginManager _plugins;

  InstalledPlugin _p(String pluginId) {
    final p = _plugins.byId(pluginId);
    if (p == null) throw PluginError('', 'no plugin "$pluginId"');
    return p;
  }

  Future<Object?> _call(String pluginId, String method, [Object? params]) async => _p(pluginId).call(method, params);

  static Map _map(Object? r) => (r as Map?) ?? const {};
  static List<Map> _list(Object? r) => ((r as List?) ?? const []).whereType<Map>().toList();

  /// Whether the plugin exports [method] (what the UI offers depends on it).
  bool can(String pluginId, String method) => _plugins.byId(pluginId)?.can(method) ?? false;

  // ----- catalogue
  Future<Browse> home(String pid) async => Browse.fromJson(_map(await _call(pid, 'home')), pid);
  Future<Browse> browse(String pid, String page) async => Browse.fromJson(_map(await _call(pid, 'browse', {'page': page})), pid);
  Future<SearchResult> search(String pid, {required String query, required String kind, int offset = 0}) async =>
      SearchResult.fromJson(_map(await _call(pid, 'search', {'query': query, 'kind': kind, 'offset': offset})), pid);
  Future<List<String>> suggest(String pid, String query) async =>
      ((await _call(pid, 'suggest', {'query': query}) as List?) ?? const []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
  Future<AlbumPage> album(String pid, String id) async => AlbumPage.fromJson(_map(await _call(pid, 'album', {'id': id})), pid);
  Future<ArtistPage> artist(String pid, String id) async => ArtistPage.fromJson(_map(await _call(pid, 'artist', {'id': id})), pid);
  Future<Playlist> playlist(String pid, String id) async => Playlist.fromJson(_map(await _call(pid, 'playlist', {'id': id})), pid);
  Future<List<Station>> stations(String pid) async => _list(await _call(pid, 'stations')).map(Station.fromJson).toList();
  Future<List<Track>> stationNext(String pid, String id) async => _list(await _call(pid, 'stationNext', {'id': id})).map((m) => Track.fromJson(m, pid)).toList();

  // ----- the listener's library
  Future<Account?> account(String pid) async {
    if (!can(pid, 'account')) return null;
    final r = await _call(pid, 'account');
    return r is Map ? Account.fromJson(r) : null;
  }

  Future<void> signIn(String pid) => _call(pid, 'signIn');
  Future<void> signOut(String pid) => _call(pid, 'signOut');
  Future<TrackPage> liked(String pid, {int offset = 0}) async => TrackPage.fromJson(_map(await _call(pid, 'liked', {'offset': offset})), pid);
  Future<Map<String, bool>> isLiked(String pid, List<String> ids) async =>
      _map(await _call(pid, 'isLiked', {'ids': ids})).map((k, v) => MapEntry('$k', v == true));
  Future<void> like(String pid, Track t, bool on) => _call(pid, t.showId.isNotEmpty && can(pid, 'likeEpisode') ? 'likeEpisode' : 'like', {'id': t.id, 'on': on});
  Future<List<Track>> recent(String pid) async => _list(await _call(pid, 'recent')).map((m) => Track.fromJson(m, pid)).toList();
  Future<List<Playlist>> playlists(String pid) async => _list(await _call(pid, 'playlists')).map((m) => Playlist.fromJson(m, pid)).toList();
  Future<List<Album>> savedAlbums(String pid, {int offset = 0}) async =>
      ((_map(await _call(pid, 'savedAlbums', {'offset': offset}))['albums'] as List?) ?? const []).whereType<Map>().map(Album.fromJson).toList();
  Future<void> played(String pid, String id) => _call(pid, 'played', {'id': id});

  // ----- playback
  Future<StreamInfo> stream(Track t, String quality) async {
    final s = StreamInfo.fromJson(_map(await _call(t.source, 'stream', {'id': t.id, 'quality': quality})));
    if (s.url.isEmpty) throw PluginError(PluginError.unavailable, '');
    return s;
  }

  Future<List<LyricLine>> lyrics(Track t) async {
    if (!can(t.source, 'lyrics')) return const [];
    final r = await _call(t.source, 'lyrics', {'id': t.id});
    return r is Map ? parseLyrics(r) : const [];
  }

  Future<CommentPage> comments(Track t, {int offset = 0}) async {
    final r = _map(await _call(t.source, 'comments', {'trackId': t.id, 'offset': offset}));
    final list = ((r['comments'] as List?) ?? const []).whereType<Map>().map(Comment.fromJson).toList();
    return CommentPage(list, (r['total'] as num?)?.toInt() ?? 0, r['more'] == true && list.isNotEmpty);
  }
}

class CommentPage {
  CommentPage(this.comments, this.total, this.more);
  final List<Comment> comments;
  final int total;
  final bool more;
}
