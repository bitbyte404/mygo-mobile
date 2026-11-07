// A running plugin's own data: what host.storage holds and its settings. The
// host API is synchronous, so a runtime loads both when the plugin starts and
// writes through on every change. Layout (the same on every platform, inside
// the app's Store): plugin-data/<id>/storage.json and settings.json, plus any
// folders the plugin makes there (host.removeDataDir removes one).
//
// Implementations: FilePluginData (dart:io; the QuickJS PluginHost on the
// phone) and, in the browser, the plugin worker's own over IndexedDB
// (web/mygo/plugin_worker.js, same paths through web/mygo/idb.js).
abstract interface class PluginDataStore {
  Map<String, dynamic> loadStorage();
  void saveStorage(Map<String, dynamic> storage);
  Map<String, String> loadSettings();
  void saveSettings(Map<String, String> settings);

  /// Removes a folder of the plugin's data ([name] is relative, already checked).
  void removeDir(String name);
}
