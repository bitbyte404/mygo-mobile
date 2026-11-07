// Stress test for the "Maximum call stack size exceeded" failures: plugin
// calls through PluginWorker (one background isolate per plugin, as the app
// runs them), several workers at once, with idle gaps between calls so the
// isolates resume on other threads of the Dart VM's pool. Before the fix in
// native/mygojs.c (JS_UpdateStackTop at every entry), QuickJS checked the
// stack against the thread it was created on.
//   MYGOJS_LIB=native/build/host/libmygojs.so flutter test test/stack_stress_test.dart
// Needs the kugou-lite checkout and the signed-in fixture (as kugou_live_test).
@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/core/runtime/quickjs/plugin_worker.dart';

const pluginDir = String.fromEnvironment('KUGOU_DIR', defaultValue: '/workspace/work/mygo-music-kugou-lite');
const workers = int.fromEnvironment('WORKERS', defaultValue: 4);
const callsEach = int.fromEnvironment('CALLS', defaultValue: 120);

void main() {
  test('plugin calls across isolates and threads', () async {
    final root = Directory.systemTemp.createTempSync('mygo-stress-');
    final ws = <PluginWorker>[];
    for (var i = 0; i < workers; i++) {
      final data = Directory('${root.path}/w$i/kugou-lite')..createSync(recursive: true);
      File('test/fixtures/kugou-data/kugou-lite/storage.json').copySync('${data.path}/storage.json');
      ws.add(await PluginWorker.spawn(
        dir: pluginDir,
        dataRoot: '${root.path}/w$i',
        language: 'zh-CN',
        platform: 'android',
        arch: 'arm64',
        prelude: File('assets/js/prelude.js').readAsStringSync(),
      ));
    }
    final rnd = Random(7);
    var ok = 0;
    final failures = <String>[];
    Future<void> run(PluginWorker w) async {
      for (var k = 0; k < callsEach; k++) {
        try {
          await w.call('account');
          ok++;
        } catch (e) {
          failures.add('$e'.split('\n').first);
        }
        if (k % 3 == 0) await Future<void>.delayed(Duration(milliseconds: rnd.nextInt(40)));
      }
    }

    await Future.wait(ws.map(run));
    for (final w in ws) {
      w.close();
    }
    root.deleteSync(recursive: true);
    final stack = failures.where((f) => f.contains('stack')).length;
    // ignore: avoid_print
    print('STRESS ok=$ok failed=${failures.length} stackOverflow=$stack ${failures.take(3).join(' | ')}');
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
