import 'idb_store.dart';
import 'store.dart';

Future<Store> openStore(String root) => IdbStore.open(root);
