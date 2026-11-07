// Store in IndexedDB (the web build), through web/mygo/idb.js, the same
// module the plugin workers use, so both see one layout.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'store.dart';

extension type _Idb._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> open(JSString db);
  external JSPromise<JSUint8Array?> get(JSString db, JSString path);
  external JSPromise<JSAny?> put(JSString db, JSString path, JSUint8Array bytes);
  external JSPromise<JSAny?> del(JSString db, JSString path);
  external JSPromise<JSArray<JSString>> list(JSString db, JSString dir);
  external JSPromise<JSAny?> move(JSString db, JSString from, JSString to);
}

/// The URL of a file in web/mygo/, resolved against the page (honours `<base href>`).
String mygoWebAsset(String name) => Uri.parse(web.document.baseURI).resolve('mygo/$name').toString();

class IdbStore implements Store {
  IdbStore._(this._idb, this.db);
  final _Idb _idb;

  /// The IndexedDB database name.
  final String db;

  static Future<IdbStore> open(String db) async {
    final mod = await importModule(mygoWebAsset('idb.js').toJS).toDart;
    final idb = mod as _Idb;
    await idb.open(db.toJS).toDart;
    return IdbStore._(idb, db);
  }

  @override
  String? localPath(String path) => null;

  @override
  Future<Uint8List?> read(String path) async => (await _idb.get(db.toJS, path.toJS).toDart)?.toDart;

  @override
  Future<void> write(String path, List<int> bytes) async {
    final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    await _idb.put(db.toJS, path.toJS, b.toJS).toDart;
  }

  @override
  Future<void> delete(String path) async => _idb.del(db.toJS, path.toJS).toDart;

  @override
  Future<List<String>> list(String dir) async => [for (final s in (await _idb.list(db.toJS, dir.toJS).toDart).toDart) s.toDart];

  @override
  Future<void> move(String from, String to) async => _idb.move(db.toJS, from.toJS, to.toJS).toDart;
}
