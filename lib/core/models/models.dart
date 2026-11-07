// The shapes plugins answer, by their JSON names (desktop internal/music/music.go).
// Times are in milliseconds. Unknown fields are ignored; missing ones default.

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
bool _b(Object? v) => v == true;
List<T> _list<T>(Object? v, T Function(Map) f) => v is List ? v.whereType<Map>().map(f).toList() : <T>[];

class Artist {
  Artist({required this.id, required this.name, this.imageUrl = '', this.following = false});
  final String id, name, imageUrl;
  bool following;
  factory Artist.fromJson(Map m) =>
      Artist(id: _s(m['id']), name: _s(m['name']), imageUrl: _s(m['imageUrl']), following: _b(m['following']));
  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (imageUrl.isNotEmpty) 'imageUrl': imageUrl};
}

class Album {
  Album({required this.id, required this.name, this.imageUrl = '', this.artists = const [], this.released = '', this.saved = false});
  final String id, name, imageUrl, released;
  final List<Artist> artists;
  bool saved;
  factory Album.fromJson(Map m) => Album(
      id: _s(m['id']),
      name: _s(m['name']),
      imageUrl: _s(m['imageUrl']),
      artists: _list(m['artists'], Artist.fromJson),
      released: _s(m['released']),
      saved: _b(m['saved']));
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (artists.isNotEmpty) 'artists': artists.map((a) => a.toJson()).toList(),
        if (released.isNotEmpty) 'released': released,
      };
  String get artistNames => artists.map((a) => a.name).join(', ');
}

class Track {
  Track({
    required this.id,
    required this.source,
    required this.name,
    this.artists = const [],
    Album? album,
    this.duration = 0,
    this.url = '',
    this.unavailable = false,
    this.showId = '',
    this.description = '',
    this.published = '',
  }) : album = album ?? Album(id: '', name: '');
  final String id;
  String source; // the plugin's id, stamped by the app as on desktop
  final String name;
  final List<Artist> artists;
  final Album album;
  final int duration;
  final String url, showId, description, published;
  final bool unavailable;

  factory Track.fromJson(Map m, [String source = '']) => Track(
        id: _s(m['id']),
        source: _s(m['source']).isNotEmpty ? _s(m['source']) : source,
        name: _s(m['name']),
        artists: _list(m['artists'], Artist.fromJson),
        album: m['album'] is Map ? Album.fromJson(m['album'] as Map) : null,
        duration: _i(m['duration']),
        url: _s(m['url']),
        unavailable: _b(m['unavailable']),
        showId: _s(m['showId']),
        description: _s(m['description']),
        published: _s(m['published']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'name': name,
        if (artists.isNotEmpty) 'artists': artists.map((a) => a.toJson()).toList(),
        'album': album.toJson(),
        'duration': duration,
        if (url.isNotEmpty) 'url': url,
        if (unavailable) 'unavailable': true,
        if (showId.isNotEmpty) 'showId': showId,
      };

  String get artistNames => artists.map((a) => a.name).join(', ');
  String get key => '$source:$id';
}

class Playlist {
  Playlist({
    required this.id,
    required this.name,
    this.imageUrl = '',
    this.description = '',
    this.owner = '',
    this.trackCount = 0,
    this.mine = false,
    this.saved = false,
    this.fixed = false,
    this.tracks = const [],
  });
  final String id, name, imageUrl, description, owner;
  final int trackCount;
  final bool mine, fixed;
  bool saved;
  final List<Track> tracks;
  factory Playlist.fromJson(Map m, [String source = '']) => Playlist(
        id: _s(m['id']),
        name: _s(m['name']),
        imageUrl: _s(m['imageUrl']),
        description: _s(m['description']),
        owner: _s(m['owner']),
        trackCount: _i(m['trackCount']),
        mine: _b(m['mine']),
        saved: _b(m['saved']),
        fixed: _b(m['fixed']),
        tracks: _list(m['tracks'], (t) => Track.fromJson(t, source)),
      );
}

class Station {
  Station({required this.id, required this.name, this.description = '', this.imageUrl = ''});
  final String id, name, description, imageUrl;
  factory Station.fromJson(Map m) =>
      Station(id: _s(m['id']), name: _s(m['name']), description: _s(m['description']), imageUrl: _s(m['imageUrl']));
}

class Show {
  Show({required this.id, required this.name, this.imageUrl = '', this.description = '', this.publisher = '', this.episodeCount = 0});
  final String id, name, imageUrl, description, publisher;
  final int episodeCount;
  factory Show.fromJson(Map m) => Show(
      id: _s(m['id']),
      name: _s(m['name']),
      imageUrl: _s(m['imageUrl']),
      description: _s(m['description']),
      publisher: _s(m['publisher']),
      episodeCount: _i(m['episodeCount']));
}

class Link {
  Link({required this.title, this.subtitle = '', this.imageUrl = '', required this.page});
  final String title, subtitle, imageUrl, page;
  factory Link.fromJson(Map m) =>
      Link(title: _s(m['title']), subtitle: _s(m['subtitle']), imageUrl: _s(m['imageUrl']), page: _s(m['page']));
}

class Section {
  Section({
    this.title = '',
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.shows = const [],
    this.stations = const [],
    this.links = const [],
    this.morePage = '',
    this.empty = '',
    this.pageTitle = '',
    this.subtitle = '',
  });
  final String title, morePage, empty, pageTitle, subtitle;
  final List<Track> tracks;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Playlist> playlists;
  final List<Show> shows;
  final List<Station> stations;
  final List<Link> links;

  bool get isEmpty =>
      tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty && shows.isEmpty && stations.isEmpty && links.isEmpty;

  factory Section.fromJson(Map m, String source) => Section(
        title: _s(m['title']),
        tracks: _list(m['tracks'], (t) => Track.fromJson(t, source)),
        albums: _list(m['albums'], Album.fromJson),
        artists: _list(m['artists'], Artist.fromJson),
        playlists: _list(m['playlists'], (p) => Playlist.fromJson(p, source)),
        shows: _list(m['shows'], Show.fromJson),
        stations: _list(m['stations'], Station.fromJson),
        links: _list(m['links'], Link.fromJson),
        morePage: _s(m['morePage']),
        empty: _s(m['empty']),
        pageTitle: _s(m['pageTitle']),
        subtitle: _s(m['subtitle']),
      );
}

class Browse {
  Browse({this.title = '', this.subtitle = '', this.imageUrl = '', this.description = '', this.sections = const []});
  final String title, subtitle, imageUrl, description;
  final List<Section> sections;
  factory Browse.fromJson(Map m, String source) => Browse(
        title: _s(m['title']),
        subtitle: _s(m['subtitle']),
        imageUrl: _s(m['imageUrl']),
        description: _s(m['description']),
        sections: _list(m['sections'], (s) => Section.fromJson(s, source)),
      );
}

class Account {
  Account({required this.id, required this.name, this.imageUrl = '', this.page = ''});
  final String id, name, imageUrl, page;
  factory Account.fromJson(Map m) => Account(id: _s(m['id']), name: _s(m['name']), imageUrl: _s(m['imageUrl']), page: _s(m['page']));
}

class SearchResult {
  SearchResult({this.tracks = const [], this.albums = const [], this.artists = const [], this.playlists = const [], this.more = false});
  final List<Track> tracks;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Playlist> playlists;
  final bool more;
  factory SearchResult.fromJson(Map m, String source) => SearchResult(
        tracks: _list(m['tracks'], (t) => Track.fromJson(t, source)),
        albums: _list(m['albums'], Album.fromJson),
        artists: _list(m['artists'], Artist.fromJson),
        playlists: _list(m['playlists'], (p) => Playlist.fromJson(p, source)),
        more: _b(m['more']),
      );
  int get length => tracks.length + albums.length + artists.length + playlists.length;
}

class TrackPage {
  TrackPage({this.tracks = const [], this.more = false});
  final List<Track> tracks;
  final bool more;
  factory TrackPage.fromJson(Map m, String source) =>
      TrackPage(tracks: _list(m['tracks'], (t) => Track.fromJson(t, source)), more: _b(m['more']));
}

class AlbumPage {
  AlbumPage({required this.album, this.tracks = const []});
  final Album album;
  final List<Track> tracks;
  factory AlbumPage.fromJson(Map m, String source) => AlbumPage(
      album: m['album'] is Map ? Album.fromJson(m['album'] as Map) : Album(id: '', name: ''),
      tracks: _list(m['tracks'], (t) => Track.fromJson(t, source)));
}

class ArtistPage {
  ArtistPage({required this.artist, this.tracks = const [], this.albums = const []});
  final Artist artist;
  final List<Track> tracks;
  final List<Album> albums;
  factory ArtistPage.fromJson(Map m, String source) => ArtistPage(
      artist: m['artist'] is Map ? Artist.fromJson(m['artist'] as Map) : Artist(id: '', name: ''),
      tracks: _list(m['tracks'], (t) => Track.fromJson(t, source)),
      albums: _list(m['albums'], Album.fromJson));
}

class StreamInfo {
  StreamInfo({required this.url, this.type = '', this.quality = '', this.bitRate = 0, this.size = 0, this.headers = const {}});
  final String url, type, quality;
  final int bitRate, size;
  final Map<String, String> headers;
  factory StreamInfo.fromJson(Map m) => StreamInfo(
      url: _s(m['url']),
      type: _s(m['type']),
      quality: _s(m['quality']),
      bitRate: _i(m['bitRate']),
      size: _i(m['size']),
      headers: m['headers'] is Map ? (m['headers'] as Map).map((k, v) => MapEntry('$k', '$v')) : const {});
}

class LyricWord {
  LyricWord(this.start, this.end, this.text);
  final int start, end;
  final String text;
}

class LyricLine {
  LyricLine({required this.start, this.end = 0, required this.text, this.translation = '', this.words = const []});
  final int start, end;
  final String text, translation;
  final List<LyricWord> words;
}

class Comment {
  Comment({required this.id, required this.author, this.avatarUrl = '', required this.text, this.time = 0, this.likes = 0, this.liked = false});
  final String id, author, avatarUrl, text;
  final int time, likes;
  final bool liked;
  factory Comment.fromJson(Map m) => Comment(
      id: _s(m['id']),
      author: _s(m['author']),
      avatarUrl: _s(m['avatarUrl']),
      text: _s(m['text']),
      time: _i(m['time']),
      likes: _i(m['likes']),
      liked: _b(m['liked']));
}

/// Lyrics as lines, from {lines} or parsed from {lrc, translation}. An
/// `offset` (ms, LRC's [offset:] sense: positive shows the words sooner)
/// moves every time.
List<LyricLine> parseLyrics(Map m) => _shift(_parseLyrics(m), _i(m['offset']));

List<LyricLine> _shift(List<LyricLine> lines, int offset) {
  if (offset == 0) return lines;
  int t(int v) => v - offset < 0 ? 0 : v - offset;
  return [
    for (final l in lines)
      LyricLine(
        start: t(l.start),
        end: l.end == 0 ? 0 : t(l.end),
        text: l.text,
        translation: l.translation,
        words: [for (final w in l.words) LyricWord(t(w.start), t(w.end), w.text)],
      ),
  ];
}

List<LyricLine> _parseLyrics(Map m) {
  if (m['lines'] is List && (m['lines'] as List).isNotEmpty) {
    return (m['lines'] as List).whereType<Map>().map((l) {
      final words = l['words'] is List
          ? (l['words'] as List).whereType<Map>().map((w) => LyricWord(_i(w['start']), _i(w['end']), _s(w['text']))).toList()
          : <LyricWord>[];
      final text = _s(l['text']).isNotEmpty ? _s(l['text']) : words.map((w) => w.text).join();
      return LyricLine(start: _i(l['start']), end: _i(l['end']), text: text, translation: _s(l['translation']), words: words);
    }).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }
  final main = parseLrc(_s(m['lrc']));
  final tr = parseLrc(_s(m['translation']));
  if (tr.isEmpty) return main;
  final byTime = {for (final l in tr) l.start: l.text};
  return [for (final l in main) LyricLine(start: l.start, text: l.text, translation: byTime[l.start] ?? '')];
}

final _lrcTime = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');
final _lrcOffset = RegExp(r'^\s*\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false, multiLine: true);

/// LRC lines, with the file's [offset:ms] applied (positive: sooner).
List<LyricLine> parseLrc(String lrc) {
  final off = _lrcOffset.firstMatch(lrc);
  return _shift(_parseLrc(lrc), off == null ? 0 : int.parse(off.group(1)!));
}

List<LyricLine> _parseLrc(String lrc) {
  final out = <LyricLine>[];
  for (final raw in lrc.split(RegExp(r'\r?\n'))) {
    final times = _lrcTime.allMatches(raw).toList();
    if (times.isEmpty) continue;
    final text = raw.substring(times.last.end).trim();
    for (final t in times) {
      final frac = t.group(3) ?? '0';
      final ms = int.parse(t.group(1)!) * 60000 +
          int.parse(t.group(2)!) * 1000 +
          (frac.length == 1 ? int.parse(frac) * 100 : frac.length == 2 ? int.parse(frac) * 10 : int.parse(frac.substring(0, 3)));
      out.add(LyricLine(start: ms, text: text));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
