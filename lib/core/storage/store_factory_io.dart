import 'file_store.dart';
import 'store.dart';

Future<Store> openStore(String root) async => FileStore(root);
