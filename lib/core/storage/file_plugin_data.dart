import 'dart:convert';
import 'dart:io';

import 'plugin_data.dart';

/// PluginDataStore in a folder on disk: `<dataRoot>/<id>/`.
class FilePluginData implements PluginDataStore {
  FilePluginData(this.dir) {
    Directory(dir).createSync(recursive: true);
  }
  final String dir;

  Object? _read(String name) {
    final f = File('$dir/$name');
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(f.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  void _write(String name, Object value) {
    Directory(dir).createSync(recursive: true);
    final part = File('$dir/$name.part');
    part.writeAsStringSync(jsonEncode(value), flush: true);
    part.renameSync('$dir/$name');
  }

  @override
  Map<String, dynamic> loadStorage() => (_read('storage.json') as Map?)?.cast<String, dynamic>() ?? {};
  @override
  void saveStorage(Map<String, dynamic> storage) => _write('storage.json', storage);
  @override
  Map<String, String> loadSettings() => ((_read('settings.json') as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v'));
  @override
  void saveSettings(Map<String, String> settings) => _write('settings.json', settings);
  @override
  void removeDir(String name) {
    final d = Directory('$dir/$name');
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
