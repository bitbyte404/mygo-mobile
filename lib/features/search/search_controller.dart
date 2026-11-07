import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mygo_mobile/core/models/models.dart';

/// Search: the query, its kind, results a page at a time, and suggestions
/// while typing. A search cancels any suggestion pending or on its way, so
/// a late suggestion list never covers the results.
class SearchController extends ChangeNotifier {
  SearchController({required this.searchFn, this.suggestFn, this.debounce = const Duration(milliseconds: 350)});

  final Future<SearchResult> Function(String query, String kind, int offset) searchFn;
  final Future<List<String>> Function(String query)? suggestFn;
  final Duration debounce;

  String kind = 'tracks';
  String query = '';
  SearchResult? result;
  Object? error;
  bool loading = false, loadingMore = false;
  List<String> suggestions = const [];

  Timer? _timer;
  int _seq = 0; // the search on its way
  int _suggestSeq = 0; // bumped by every search and keystroke
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The text changed: ask for suggestions once typing pauses.
  void typed(String text) {
    _timer?.cancel();
    final ticket = ++_suggestSeq;
    final q = text.trim();
    if (suggestFn == null || q.isEmpty) {
      if (suggestions.isNotEmpty) {
        suggestions = const [];
        _notify();
      }
      return;
    }
    _timer = Timer(debounce, () async {
      try {
        final r = await suggestFn!(q);
        if (_disposed || ticket != _suggestSeq) return;
        suggestions = r.take(8).toList();
        _notify();
      } catch (_) {}
    });
  }

  void clearSuggestions() {
    _timer?.cancel();
    _suggestSeq++;
    suggestions = const [];
    _notify();
  }

  void setKind(String k) {
    kind = k;
    _notify();
    if (query.isNotEmpty) search(query);
  }

  /// Searches [text] (or, with [more], the next page of the last search).
  Future<void> search(String text, {bool more = false}) async {
    _timer?.cancel();
    _timer = null;
    _suggestSeq++;
    final q = more ? query : text.trim();
    if (q.isEmpty) return;
    final seq = ++_seq;
    query = q;
    suggestions = const [];
    if (more) {
      loadingMore = true;
    } else {
      loading = true;
      error = null;
    }
    _notify();
    try {
      final offset = more ? (result?.length ?? 0) : 0;
      final r = await searchFn(q, kind, offset);
      if (seq != _seq || _disposed) return;
      final old = result;
      if (more && old != null) {
        result = SearchResult(
          tracks: [...old.tracks, ...r.tracks],
          albums: [...old.albums, ...r.albums],
          artists: [...old.artists, ...r.artists],
          playlists: [...old.playlists, ...r.playlists],
          more: r.more && r.length > 0,
        );
      } else {
        result = r;
      }
    } catch (e) {
      if (seq != _seq || _disposed) return;
      if (more) rethrow;
      error = e;
    } finally {
      if (seq == _seq && !_disposed) {
        loading = false;
        loadingMore = false;
        _notify();
      }
    }
  }

  bool get suggestionPending => _timer?.isActive ?? false;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
