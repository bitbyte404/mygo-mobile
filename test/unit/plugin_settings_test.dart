// Typed plugin settings (MyGo Music 0.1.23): how plugin.json's settings are
// read, and when the controller saves what.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/data/plugins/plugin_settings.dart';

SettingDef _def(Map<String, Object?> m) => SettingDef.fromJson({'key': 'k', 'label': 'K', ...m});

void main() {
  group('types', () {
    test('text, password, boolean, select; anything else is text', () {
      expect(_def({}).type, SettingType.text);
      expect(_def({'type': 'text'}).type, SettingType.text);
      expect(_def({'type': 'password'}).type, SettingType.password);
      expect(_def({'type': 'boolean'}).type, SettingType.boolean);
      expect(_def({'type': 'color'}).type, SettingType.text);
      expect(_def({'type': 7}).type, SettingType.text);
      expect(_def({'type': 'select', 'options': [{'value': '', 'label': 'Auto'}, {'value': 'a', 'label': 'A'}]}).type, SettingType.select);
    });
    test('a select with missing, unlabeled or repeated options is text', () {
      expect(_def({'type': 'select'}).type, SettingType.text);
      expect(_def({'type': 'select', 'options': [{'value': 'a', 'label': ''}]}).type, SettingType.text);
      expect(_def({'type': 'select', 'options': [{'value': 'a', 'label': 'A'}, {'value': 'a', 'label': 'B'}]}).type, SettingType.text);
      expect(_def({'type': 'select', 'options': [{'value': 'a', 'label': 'A'}, {'value': 'b', 'label': 'A'}]}).type, SettingType.text);
    });
    test('a boolean saved as something else stays text, unset is a switch', () {
      final d = _def({'type': 'boolean'});
      expect(d.typeFor(''), SettingType.boolean);
      expect(d.typeFor('true'), SettingType.boolean);
      expect(d.typeFor('yes'), SettingType.text);
    });
    test('type and options survive the trip through JSON; none is added', () {
      final d = _def({'type': 'select', 'options': [{'value': '0', 'label': 'Off'}]});
      final again = SettingDef.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map);
      expect(again.rawType, 'select');
      expect(again.options.single.value, '0');
      expect(_def({}).toJson().containsKey('type'), isFalse);
    });
    test('kugou-lite\'s plugin.json: its selects read as selects', () {
      final f = File('/workspace/work/mygo-music-kugou-lite/plugin.json');
      if (!f.existsSync()) return markTestSkipped('kugou-lite checkout not here');
      final m = Manifest.parse(f.readAsStringSync());
      final byKey = {for (final s in m.settings) s.key: s};
      expect(byKey['platform']!.type, SettingType.select);
      expect(byKey['autoVip']!.type, SettingType.select);
      expect(byKey['autoVip']!.options.map((o) => o.value), ['', '0']);
      expect(needsNewerApp(m.minAppVersion), isFalse, reason: 'minAppVersion ${m.minAppVersion} vs $kPluginApiVersion');
    });
  });

  group('plugin API version', () {
    test('0.1.25, and newer asks for a newer app', () {
      expect(kPluginApiVersion, '0.1.25');
      expect(needsNewerApp(''), isFalse);
      expect(needsNewerApp('0.1.20'), isFalse);
      expect(needsNewerApp('0.1.25'), isFalse);
      expect(needsNewerApp('0.1.26'), isTrue);
      expect(needsNewerApp('0.2'), isTrue);
    });
  });

  group('controller', () {
    final defs = [
      _def({'key': 'server', 'label': 'Server'}),
      _def({'key': 'password', 'type': 'password'}),
      _def({'key': 'history', 'type': 'boolean'}),
      _def({'key': 'mode', 'type': 'select', 'options': [{'value': '', 'label': 'Auto'}, {'value': 'token', 'label': 'Token'}]}),
    ];

    test('switches and selects save at once; text and passwords wait for Save', () async {
      final writes = <String>[];
      final c = PluginSettingsController(defs: defs, saved: {'server': 'nas'}, save: (k, v) async => writes.add('$k=$v'));
      c.edit('server', 'nas2');
      c.edit('password', 'secret');
      expect(writes, isEmpty);
      expect(c.hasDrafts, isTrue);
      await c.choose('history', 'true');
      await c.choose('mode', 'token');
      expect(writes, ['history=true', 'mode=token']);
      expect(await c.saveDrafts(), isTrue);
      expect(writes, ['history=true', 'mode=token', 'server=nas2', 'password=secret']);
      expect(c.hasDrafts, isFalse);
    });

    test('opening writes nothing, and unknown values are kept as they are', () async {
      final writes = <String>[];
      final c = PluginSettingsController(defs: defs, saved: {'history': 'yes', 'mode': 'legacy'}, save: (k, v) async => writes.add('$k=$v'));
      expect(c.field('history').type, SettingType.text);
      expect(c.field('mode').type, SettingType.select);
      expect(c.field('mode').valueListed, isFalse);
      expect(c.field('mode').draft, 'legacy');
      expect(await c.saveDrafts(), isTrue);
      expect(writes, isEmpty);
    });

    test('saves run in the order they were started; the field is busy meanwhile', () async {
      final order = <String>[];
      final first = Completer<void>();
      final c = PluginSettingsController(defs: defs, saved: const {}, save: (k, v) async {
        if (k == 'history') await first.future;
        order.add(k);
      });
      final a = c.choose('history', 'true');
      final b = c.choose('mode', 'token');
      expect(c.field('history').saving, isTrue);
      expect(c.busy, isTrue);
      first.complete();
      await Future.wait([a, b]);
      expect(order, ['history', 'mode']);
      expect(c.busy, isFalse);
    });

    test('a failed save is marked; Retry tries again, Restore writes the old value back', () async {
      var fail = true;
      final writes = <String>[];
      final c = PluginSettingsController(defs: defs, saved: {'mode': ''}, save: (k, v) async {
        writes.add('$k=$v');
        if (fail) throw StateError('disk full');
      });
      expect(await c.choose('mode', 'token'), isFalse);
      expect(c.field('mode').failed, isTrue);
      expect(c.field('mode').saved, '');
      fail = false;
      expect(await c.retry('mode'), isTrue);
      expect(c.field('mode').saved, 'token');

      fail = true;
      await c.choose('mode', '');
      fail = false;
      expect(await c.restore('mode'), isTrue);
      expect(c.field('mode').draft, 'token');
      expect(writes.last, 'mode=token');
      expect(c.field('mode').failed, isFalse);
    });
  });
}
