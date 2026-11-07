import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:mygo_mobile/core/runtime/runtime_factory.dart';
import 'package:mygo_mobile/core/storage/file_store.dart';
import 'package:path_provider/path_provider.dart';

import 'platform_bits.dart';

String _arch() {
  final a = Abi.current().toString();
  if (a.contains('arm64')) return 'arm64';
  if (a.contains('x64')) return 'amd64';
  if (a.contains('arm')) return 'arm';
  return a;
}

Future<PlatformBits> platformBits() async {
  final dir = await getApplicationSupportDirectory();
  return PlatformBits(store: FileStore(dir.path), platform: Platform.operatingSystem, arch: _arch(), runtime: defaultPluginRuntime());
}

Future<void> loadAppFonts() async {}
