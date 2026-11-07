// The app's own settings and play history, kept as JSON in the Store
// (app-settings.json, history.json).
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/core/storage/store.dart';
import 'package:mygo_mobile/l10n/strings.dart';

class AppState extends ChangeNotifier {
  AppState(this.store);
  final Store store;

  String language = 'zh-CN';
  ThemeMode themeMode = ThemeMode.system;
  String quality = 'lossless'; // standard | high | lossless
  String? activePlugin;
  final List<Track> history = []; // newest first
  static const historyMax = 300;

  S get s => S(language);

  static const _settingsFile = 'app-settings.json';
  static const _historyFile = 'history.json';

  Future<void> load({required String deviceLanguage}) async {
    language = deviceLanguage.startsWith('zh') ? 'zh-CN' : 'en';
    try {
      final m = await store.readJson(_settingsFile);
      if (m is Map) {
        language = '${m['language'] ?? language}';
        themeMode = ThemeMode.values.firstWhere((t) => t.name == m['theme'], orElse: () => ThemeMode.system);
        quality = '${m['quality'] ?? quality}';
        activePlugin = m['activePlugin'] as String?;
      }
    } catch (_) {}
    try {
      final l = await store.readJson(_historyFile);
      if (l is List) history.addAll(l.whereType<Map>().map((m) => Track.fromJson(m)));
    } catch (_) {}
  }

  // Writes are chained so they land in order; the UI never waits for them.
  Future<void> _writes = Future.value();
  void _write(String path, Object? Function() value) {
    _writes = _writes.then((_) => store.writeJson(path, value())).catchError((Object e) => debugPrint('save $path: $e'));
  }

  /// Completes when every change so far is saved.
  Future<void> flush() => _writes;

  void _save() => _write(_settingsFile, () => {
        'language': language,
        'theme': themeMode.name,
        'quality': quality,
        'activePlugin': activePlugin,
      });

  void setLanguage(String l) {
    language = l;
    _save();
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _save();
    notifyListeners();
  }

  void setQuality(String q) {
    quality = q;
    _save();
    notifyListeners();
  }

  void setActivePlugin(String? id) {
    activePlugin = id;
    _save();
  }

  void addHistory(Track t) {
    history.removeWhere((x) => x.key == t.key);
    history.insert(0, t);
    if (history.length > historyMax) history.removeRange(historyMax, history.length);
    final snapshot = history.map((t) => t.toJson()).toList();
    _write(_historyFile, () => snapshot);
    notifyListeners();
  }

  void clearHistory() {
    history.clear();
    _writes = _writes.then((_) => store.delete(_historyFile)).catchError((Object e) => debugPrint('clear history: $e'));
    notifyListeners();
  }
}
