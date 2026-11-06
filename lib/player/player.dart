// Playback: just_audio for the sound, audio_service for background play and
// the lock screen / notification controls. The queue is ours: each track's
// stream is asked of its plugin when it starts (stream URLs expire), with the
// quality the listener chose and the headers the plugin gives.
import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';

enum Repeat { off, all, one }

/// Resolves a track to what to play; throws a PluginError when it can't.
typedef StreamResolver = Future<StreamInfo> Function(Track track);

class Player extends BaseAudioHandler with SeekHandler {
  Player() {
    _player.playbackEventStream.listen(_broadcast, onError: (Object e, StackTrace st) {
      debugPrint('player: $e');
      error.value = '$e';
      _broadcast(_player.playbackEvent);
    });
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
    _player.playingStream.listen((_) => _broadcast(_player.playbackEvent));
    _player.durationStream.listen((d) {
      final item = mediaItem.value;
      if (item != null && d != null && item.duration != d) mediaItem.add(item.copyWith(duration: d));
    });
    _initSession();
  }

  final _player = AudioPlayer();
  StreamResolver? resolver;
  void Function(Track track)? onStarted;
  Future<List<Track>> Function(String source, String stationId)? stationNext;

  final current = ValueNotifier<Track?>(null);
  final tracks = ValueNotifier<List<Track>>(const []);
  final shuffle = ValueNotifier<bool>(false);
  final repeat = ValueNotifier<Repeat>(Repeat.off);
  final loading = ValueNotifier<bool>(false);
  final error = ValueNotifier<String?>(null);
  final streamInfo = ValueNotifier<StreamInfo?>(null);

  int _index = -1;
  List<int> _order = const []; // play order over [tracks]
  int _token = 0;
  int _failures = 0;
  String? _stationSource, _stationId;

  AudioPlayer get audio => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<bool> get playingStream => _player.playingStream;
  bool get playing => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  int get index => _index;
  bool get isStation => _stationId != null;

  Future<void> _initSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}
  }

  // ---------- queue ----------

  Future<void> playTracks(List<Track> list, {int start = 0, bool shuffled = false}) async {
    final playable = list.where((t) => !t.unavailable).toList();
    if (playable.isEmpty) return;
    var startTrack = start >= 0 && start < list.length ? list[start] : playable.first;
    if (startTrack.unavailable) startTrack = playable.first;
    _stationId = null;
    _stationSource = null;
    tracks.value = List.unmodifiable(playable);
    shuffle.value = shuffled;
    final i = shuffled && start < 0 ? Random().nextInt(playable.length) : playable.indexOf(startTrack);
    _makeOrder(i);
    _publishQueue();
    await _playAt(i);
  }

  Future<void> playStation(String source, String stationId, List<Track> first) async {
    _stationSource = source;
    _stationId = stationId;
    shuffle.value = false;
    tracks.value = List.unmodifiable(first);
    _makeOrder(0);
    _publishQueue();
    await _playAt(0);
  }

  void addNext(Track t) {
    if (tracks.value.isEmpty) {
      playTracks([t]);
      return;
    }
    final l = [...tracks.value, t];
    tracks.value = List.unmodifiable(l);
    final newIdx = l.length - 1;
    final pos = _order.indexOf(_index);
    final o = [..._order]..insert(pos + 1, newIdx);
    _order = o;
    _publishQueue();
  }

  void addToQueue(Track t) {
    if (tracks.value.isEmpty) {
      playTracks([t]);
      return;
    }
    final l = [...tracks.value, t];
    tracks.value = List.unmodifiable(l);
    _order = [..._order, l.length - 1];
    _publishQueue();
  }

  void removeAt(int i) {
    if (i == _index) return;
    final l = [...tracks.value]..removeAt(i);
    tracks.value = List.unmodifiable(l);
    _order = _order.where((x) => x != i).map((x) => x > i ? x - 1 : x).toList();
    if (_index > i) _index--;
    _publishQueue();
  }

  void _makeOrder(int first) {
    final n = tracks.value.length;
    if (shuffle.value) {
      final rest = [for (var i = 0; i < n; i++) if (i != first) i]..shuffle();
      _order = [first, ...rest];
    } else {
      _order = [for (var i = 0; i < n; i++) i];
    }
  }

  /// The queue in play order, as the UI lists it.
  List<int> get order => _order;

  void _publishQueue() {
    queue.add([for (final t in tracks.value) _item(t)]);
  }

  MediaItem _item(Track t) => MediaItem(
        id: t.key,
        title: t.name,
        artist: t.artistNames,
        album: t.album.name,
        duration: t.duration > 0 ? Duration(milliseconds: t.duration) : null,
        artUri: t.album.imageUrl.isNotEmpty ? Uri.tryParse(t.album.imageUrl) : null,
      );

  Future<void> _playAt(int i) async {
    if (i < 0 || i >= tracks.value.length) return;
    final token = ++_token;
    _index = i;
    final t = tracks.value[i];
    current.value = t;
    mediaItem.add(_item(t));
    error.value = null;
    loading.value = true;
    streamInfo.value = null;
    try {
      await _player.stop();
      final r = resolver;
      if (r == null) throw StateError('no stream resolver');
      final s = await r(t);
      if (token != _token) return;
      streamInfo.value = s;
      final uri = Uri.parse(s.url);
      await _player.setAudioSource(
        AudioSource.uri(uri, headers: s.headers.isEmpty ? null : s.headers, tag: t.key),
        preload: true,
      );
      if (token != _token) return;
      _failures = 0;
      loading.value = false;
      _player.play();
      onStarted?.call(t);
      _maybeExtendStation();
    } catch (e) {
      if (token != _token) return;
      loading.value = false;
      error.value = '$e';
      debugPrint('player: ${t.name}: $e');
      // Skip what can't play, but don't spin through a whole queue of failures.
      if (++_failures < 3 && _hasNext()) {
        await skipToNext();
      } else {
        _failures = 0;
        _broadcast(_player.playbackEvent);
      }
    }
  }

  bool _hasNext() {
    final pos = _order.indexOf(_index);
    return pos + 1 < _order.length || repeat.value == Repeat.all || isStation;
  }

  Future<void> _maybeExtendStation() async {
    final source = _stationSource, id = _stationId, next = stationNext;
    if (source == null || id == null || next == null) return;
    final pos = _order.indexOf(_index);
    if (pos < _order.length - 2) return;
    try {
      final more = await next(source, id);
      if (_stationId != id || more.isEmpty) return;
      final start = tracks.value.length;
      tracks.value = List.unmodifiable([...tracks.value, ...more]);
      _order = [..._order, for (var i = 0; i < more.length; i++) start + i];
      _publishQueue();
    } catch (e) {
      debugPrint('station: $e');
    }
  }

  Future<void> _onCompleted() async {
    if (repeat.value == Repeat.one) {
      await _player.seek(Duration.zero);
      _player.play();
      return;
    }
    if (_hasNext()) {
      await skipToNext();
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
    }
  }

  // ---------- AudioHandler ----------

  @override
  Future<void> play() async {
    if (_player.audioSource == null && _index >= 0) {
      await _playAt(_index);
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_order.isEmpty) return;
    var pos = _order.indexOf(_index) + 1;
    if (pos >= _order.length) {
      if (isStation) {
        await _maybeExtendStation();
        if (pos >= _order.length) return;
      } else if (repeat.value == Repeat.all) {
        pos = 0;
      } else {
        return;
      }
    }
    await _playAt(_order[pos]);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3) || _order.isEmpty) {
      await _player.seek(Duration.zero);
      return;
    }
    var pos = _order.indexOf(_index) - 1;
    if (pos < 0) pos = repeat.value == Repeat.all ? _order.length - 1 : 0;
    await _playAt(_order[pos]);
  }

  @override
  Future<void> skipToQueueItem(int index) => _playAt(index);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    shuffle.value = shuffleMode != AudioServiceShuffleMode.none;
    if (_index >= 0) _makeOrder(_index);
    _broadcast(_player.playbackEvent);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    repeat.value = switch (repeatMode) {
      AudioServiceRepeatMode.none => Repeat.off,
      AudioServiceRepeatMode.one => Repeat.one,
      _ => Repeat.all,
    };
    _broadcast(_player.playbackEvent);
  }

  void toggleShuffle() => setShuffleMode(shuffle.value ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);

  void cycleRepeat() => setRepeatMode(switch (repeat.value) {
        Repeat.off => AudioServiceRepeatMode.all,
        Repeat.all => AudioServiceRepeatMode.one,
        Repeat.one => AudioServiceRepeatMode.none,
      });

  void _broadcast(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: loading.value
          ? AudioProcessingState.loading
          : const {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index < 0 ? null : _index,
      shuffleMode: shuffle.value ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: switch (repeat.value) {
        Repeat.off => AudioServiceRepeatMode.none,
        Repeat.all => AudioServiceRepeatMode.all,
        Repeat.one => AudioServiceRepeatMode.one,
      },
    ));
  }
}
