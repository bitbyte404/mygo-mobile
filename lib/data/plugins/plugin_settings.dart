// Editing a plugin's settings, without widgets: what each field shows, what
// is saved, and when (MyGo Music 0.1.23, internal/app/ui_source_settings.go):
//
//   - text and password fields are drafts until an explicit Save;
//   - switches and selects save as soon as they change, their field
//     disabled while the write is in flight;
//   - a failed save leaves the field marked, with Retry, or Restore (which
//     writes the previous value back, since the plugin may have taken the
//     new one before the write failed);
//   - saves for one plugin run in the order they were started;
//   - opening the page writes nothing: a value the app doesn't understand
//     (a boolean saved as "yes", a select value not among its options) is
//     shown as it is and kept until the listener picks something.
import 'package:flutter/foundation.dart';

import 'package:mygo_mobile/core/plugin/manifest.dart';

/// One field's state.
class SettingField {
  SettingField._(this.def, this.saved) : type = def.typeFor(saved), draft = saved;

  final SettingDef def;

  /// The control to show, fixed when the page opens.
  final SettingType type;

  /// What is saved now, and what the field holds.
  String saved, draft;
  bool saving = false, failed = false;

  /// Why the last save failed.
  Object? error;

  bool get dirty => draft != saved;
  bool get savesOnChange => SettingDef.savesOnChange(type);

  /// For a select: whether the saved value is one of its options.
  bool get valueListed => def.options.any((o) => o.value == draft);
}

class PluginSettingsController extends ChangeNotifier {
  PluginSettingsController({required List<SettingDef> defs, required Map<String, String> saved, required this.save})
      : fields = [for (final d in defs) SettingField._(d, saved[d.key] ?? '')];

  final List<SettingField> fields;

  /// Writes one setting (PluginConnection.setSetting through the manager).
  final Future<void> Function(String key, String value) save;

  Future<void> _queue = Future.value();
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  SettingField field(String key) => fields.firstWhere((f) => f.def.key == key);

  /// Whether a text or password field holds something not saved yet.
  bool get hasDrafts => fields.any((f) => !f.savesOnChange && f.dirty);
  bool get busy => fields.any((f) => f.saving);

  /// A text or password field changed (nothing is saved).
  void edit(String key, String value) {
    final f = field(key);
    if (f.draft == value) return;
    f.draft = value;
    notifyListeners();
  }

  /// A switch or select changed: saved at once.
  Future<bool> choose(String key, String value) {
    final f = field(key);
    if (f.saving || (f.draft == value && !f.failed)) return Future.value(true);
    f.draft = value;
    return _write(f, value);
  }

  /// Saves every text and password field that changed, in order. False if
  /// one failed (it stays marked, its draft kept).
  Future<bool> saveDrafts() async {
    var ok = true;
    for (final f in fields) {
      if (f.savesOnChange || !f.dirty || f.saving) continue;
      ok = await _write(f, f.draft) && ok;
    }
    return ok;
  }

  /// Tries a failed field's value again.
  Future<bool> retry(String key) {
    final f = field(key);
    return _write(f, f.draft);
  }

  /// Puts a field back to its saved value. After a failed save the saved
  /// value is written again, as the plugin may already hold the new one.
  Future<bool> restore(String key) {
    final f = field(key);
    f.draft = f.saved;
    if (!f.failed) {
      notifyListeners();
      return Future.value(true);
    }
    return _write(f, f.saved);
  }

  Future<bool> _write(SettingField f, String value) {
    f.saving = true;
    notifyListeners();
    final done = _queue.then((_) async {
      try {
        await save(f.def.key, value);
        f.saved = value;
        f.failed = false;
        f.error = null;
        return true;
      } catch (e) {
        debugPrint('setting ${f.def.key}: $e');
        f.failed = true;
        f.error = e;
        return false;
      } finally {
        f.saving = false;
        notifyListeners();
      }
    });
    _queue = done.then((_) {});
    return done;
  }
}
