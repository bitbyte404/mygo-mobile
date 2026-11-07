// Store as a folder on disk (Android, iOS, desktop, tests).
import 'dart:io';
import 'dart:typed_data';

import 'store.dart';

class FileStore implements Store {
  FileStore(this.root);
  final String root;

  String _p(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty && s != '.').toList();
    if (parts.contains('..')) throw ArgumentError('path escapes the store: $path');
    return parts.isEmpty ? root : '$root/${parts.join('/')}';
  }

  @override
  String? localPath(String path) => _p(path);

  @override
  Future<Uint8List?> read(String path) async {
    final f = File(_p(path));
    if (!f.existsSync()) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> write(String path, List<int> bytes) async {
    final p = _p(path);
    final part = File('$p.part');
    part.parent.createSync(recursive: true);
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(p);
  }

  @override
  Future<void> delete(String path) async {
    final p = _p(path);
    final t = FileSystemEntity.typeSync(p, followLinks: false);
    if (t == FileSystemEntityType.notFound) return;
    if (t == FileSystemEntityType.directory) {
      Directory(p).deleteSync(recursive: true);
    } else {
      File(p).deleteSync();
    }
  }

  @override
  Future<List<String>> list(String dir) async {
    final d = Directory(_p(dir));
    if (!d.existsSync()) return const [];
    return [for (final e in d.listSync()) e.path.split('/').last];
  }

  @override
  Future<void> move(String from, String to) async {
    await delete(to);
    final src = _p(from), dst = _p(to);
    Directory(dst).parent.createSync(recursive: true);
    if (FileSystemEntity.isDirectorySync(src)) {
      Directory(src).renameSync(dst);
    } else if (File(src).existsSync()) {
      File(src).renameSync(dst);
    }
  }
}
