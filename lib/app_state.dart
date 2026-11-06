// The app's own settings and play history, kept as JSON in the app's folder.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'i18n.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  AppState(this.root);
  final String root;

  String language = 'zh-CN';
  ThemeMode themeMode = ThemeMode.system;
  String quality = 'lossless'; // standard | high | lossless
  String? activePlugin;
  final List<Track> history = []; // newest first
  static const historyMax = 300;

  S get s => S(language);

  File get _settingsFile => File('$root/app-settings.json');
  File get _historyFile => File('$root/history.json');

  void load({required String deviceLanguage}) {
    language = deviceLanguage.startsWith('zh') ? 'zh-CN' : 'en';
    try {
      if (_settingsFile.existsSync()) {
        final m = jsonDecode(_settingsFile.readAsStringSync()) as Map;
        language = '${m['language'] ?? language}';
        themeMode = ThemeMode.values.firstWhere((t) => t.name == m['theme'], orElse: () => ThemeMode.system);
        quality = '${m['quality'] ?? quality}';
        activePlugin = m['activePlugin'] as String?;
      }
    } catch (_) {}
    try {
      if (_historyFile.existsSync()) {
        final l = jsonDecode(_historyFile.readAsStringSync()) as List;
        history.addAll(l.whereType<Map>().map((m) => Track.fromJson(m)));
      }
    } catch (_) {}
  }

  void _save() {
    _settingsFile.writeAsStringSync(jsonEncode({
      'language': language,
      'theme': themeMode.name,
      'quality': quality,
      'activePlugin': activePlugin,
    }));
  }

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
    _historyFile.writeAsStringSync(jsonEncode(history.map((t) => t.toJson()).toList()));
    notifyListeners();
  }

  void clearHistory() {
    history.clear();
    if (_historyFile.existsSync()) _historyFile.deleteSync();
    notifyListeners();
  }
}
