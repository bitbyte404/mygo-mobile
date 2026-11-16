// The plugin settings page with every kind of field (MyGo Music 0.1.23):
// kugou-lite's own selects (its plugin.json settings, unchanged) plus a
// password and a switch, run in the app's real plugin runtime (QuickJS), as
// the listener uses it: rendered to screenshots/plugin-settings*.png, then
// a select chosen, the switch flipped and a password typed and saved, each
// checked in the plugin's settings.json.
//
//   MYGOJS_LIB=native/build/host/libmygojs.so flutter test test/plugin_settings_screenshot_test.dart
@Tags(['screenshots'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/runtime/quickjs/quickjs_runtime.dart';
import 'package:mygo_mobile/core/storage/file_store.dart';
import 'package:mygo_mobile/data/player/player.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/data/settings/app_state.dart';
import 'package:mygo_mobile/features/plugins/plugin_settings_page.dart';
import 'package:mygo_mobile/ui/ui.dart';

const kugouDir = String.fromEnvironment('KUGOU_DIR', defaultValue: '/workspace/work/mygo-music-kugou-lite');
const fontDir = String.fromEnvironment('CJK_FONT_DIR', defaultValue: '/workspace/work/tools/fonts');

Future<void> _loadFonts() async {
  final f = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    f.addFont(Future.value(ByteData.sublistView(File('$fontDir/NotoSansSC-$w.otf').readAsBytesSync())));
  }
  await f.load();
}

void main() {
  testWidgets('plugin settings: select, password, switch', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late Directory root;
    late Map<String, dynamic> kugou;
    await tester.runAsync(() async {
      await _loadFonts();
      kugou = jsonDecode(File('$kugouDir/plugin.json').readAsStringSync()) as Map<String, dynamic>;
      root = Directory.systemTemp.createTempSync('mygo-settings-');
      final dir = Directory('${root.path}/plugins/settings-demo')..createSync(recursive: true);
      File('${dir.path}/plugin.json').writeAsStringSync(jsonEncode({
        'id': 'settings-demo',
        'name': 'Settings demo',
        'version': '1.0.0',
        'minAppVersion': '0.1.23',
        'settings': [
          ...(kugou['settings'] as List),
          {'key': 'password', 'label': 'Password', 'type': 'password', 'help': 'Masked, saved with Save.'},
          {'key': 'history', 'label': 'Save listening history', 'type': 'boolean', 'help': 'Saves as soon as it changes.'},
          {'key': 'server', 'label': 'Server', 'help': 'A text field as before.'},
        ],
      }));
      File('${dir.path}/index.js').writeAsStringSync('export function home() { return {sections: []}; }\n');
      // Translations, as kugou-lite has them.
      final zh = File('$kugouDir/locales/zh-CN.json');
      if (zh.existsSync()) {
        Directory('${dir.path}/locales').createSync();
        zh.copySync('${dir.path}/locales/zh-CN.json');
      }
      final store = FileStore(root.path);
      final app = AppState(store);
      await app.load(deviceLanguage: 'zh-CN');
      final plugins = PluginManager(
        store: store,
        prelude: File('assets/js/prelude.js').readAsStringSync(),
        language: 'zh-CN',
        platform: 'android',
        arch: 'arm64',
        runtime: const QuickJsRuntime(),
      );
      svc = Services(app: app, plugins: plugins, player: Player())..connectPlayer();
      await plugins.init();
    });
    final plugin = svc.plugins.byId('settings-demo')!;
    expect(plugin.running, isTrue, reason: plugin.error);

    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: mgTheme(MgPalette.darkPalette),
        // The shell puts the content navigator on a Material; so does the test.
        home: Material(type: MaterialType.transparency, child: PluginSettingsPage(plugin: plugin)),
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await ro.toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('screenshots').createSync(recursive: true);
        File('screenshots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        img.dispose();
      });
    }

    Map<String, dynamic> saved() {
      final f = File('${root.path}/plugin-data/settings-demo/settings.json');
      return f.existsSync() ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic> : {};
    }

    Future<void> waitSaved(bool Function(Map<String, dynamic>) ok) async {
      for (var i = 0; i < 40 && !ok(saved()); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    // Save is off while a save still waits for the plugin's answer (the
    // file is written before the answer arrives).
    Future<void> waitIdle() async {
      final save = find.byType(PillButton);
      for (var i = 0; i < 40 && save.evaluate().isNotEmpty && tester.widget<PillButton>(save).onTap == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
    }

    // Opening wrote nothing; kugou-lite's selects show their default option.
    expect(saved(), isEmpty);
    expect(find.text('请求方式'), findsOneWidget, reason: 'kugou-lite label, translated');
    await shot('plugin-settings');

    // A select saves as soon as one is chosen.
    await tester.tap(find.text('酷狗概念版（默认）'));
    await tester.pumpAndSettle();
    await shot('plugin-settings-select');
    await tester.tap(find.text('酷狗音乐').last);
    // Saving shows progress until the plugin's isolate answers (real time).
    await tester.pump(const Duration(milliseconds: 400));
    await waitSaved((m) => m['platform'] == 'standard');
    expect(saved()['platform'], 'standard');

    // A switch saves "true".
    await tester.tap(find.byType(MgSwitch));
    await waitSaved((m) => m['history'] == 'true');
    expect(saved()['history'], 'true');

    // A password is masked and waits for Save.
    final pw = find.descendant(of: find.byType(MgTextField).first, matching: find.byType(EditableText));
    await tester.enterText(pw, 'hunter2');
    await tester.pump();
    expect((tester.widget<EditableText>(pw)).obscureText, isTrue);
    expect(saved().containsKey('password'), isFalse);
    await shot('plugin-settings-filled');
    await waitIdle();
    await tester.tap(find.text('保存'));
    await waitSaved((m) => m['password'] == 'hunter2');
    expect(saved()['password'], 'hunter2');
    expect(saved().containsKey('server'), isFalse, reason: 'an untouched text field is not written');

    // Let the plugin's answer to the last save arrive before stopping it.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    svc.plugins.dispose();
    await tester.pump(const Duration(milliseconds: 400)); // the worker's close timer
  });
}
