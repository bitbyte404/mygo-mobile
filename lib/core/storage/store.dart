// Where the app keeps its files: installed plugins, the plugins' data, the
// app's settings and history. One small interface over paths ("plugins/
// kugou-lite/plugin.json"), so the same code runs on a phone (a folder on
// disk, FileStore) and in a browser (IndexedDB, IdbStore), and the plugin
// runtimes on both read and write the same layout:
//
//   plugins/<id>/...                    an installed plugin (plugin.json, main, locales/)
//   plugins/<id>/.mygo-origin.json      where it came from (GitHub repo or zip)
//   plugin-data/<id>/storage.json       host.storage (owned by the running plugin)
//   plugin-data/<id>/settings.json      the plugin's settings
//   app-settings.json, history.json     the app's own
import 'dart:convert';
import 'dart:typed_data';

import 'store_factory_io.dart' if (dart.library.js_interop) 'store_factory_web.dart' as impl;

abstract interface class Store {
  /// A file's bytes, or null when there is none.
  Future<Uint8List?> read(String path);

  /// Writes a file (creating its folders), replacing what was there.
  Future<void> write(String path, List<int> bytes);

  /// Removes a file or a folder and everything under it; nothing if absent.
  Future<void> delete(String path);

  /// The names of the files and folders directly inside [dir].
  Future<List<String>> list(String dir);

  /// Moves a file or folder, replacing [to] if it exists.
  Future<void> move(String from, String to);

  /// The real filesystem path of [path] when the store is a folder on disk
  /// (the QuickJS runtime reads plugins from there); null in a browser.
  String? localPath(String path);
}

extension StoreJson on Store {
  Future<String?> readString(String path) async {
    final b = await read(path);
    return b == null ? null : utf8.decode(b, allowMalformed: true);
  }

  Future<Object?> readJson(String path) async {
    final s = await readString(path);
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String path, Object? value) => write(path, utf8.encode(jsonEncode(value)));
}

/// The platform's store: a folder on disk under [root], or IndexedDB in a
/// browser (where [root] names the database).
Future<Store> openStore(String root) => impl.openStore(root);
