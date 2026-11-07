import 'package:mygo_mobile/core/runtime/plugin_runtime.dart';
import 'package:mygo_mobile/core/storage/store.dart';
import 'package:mygo_mobile/data/plugins/installer.dart';
import 'package:mygo_mobile/data/relay/relay_client.dart';

/// What differs between the phone and the browser, decided once at startup.
class PlatformBits {
  PlatformBits({required this.store, required this.platform, required this.arch, required this.runtime, this.github, this.relay});

  /// Where the app keeps plugins, their data and its settings.
  final Store store;

  /// What host.platform / host.arch tell plugins.
  final String platform, arch;
  final PluginRuntime runtime;

  /// How GitHub is reached for installs (null: directly).
  final GitHubEndpoints? github;

  /// The relay (web only).
  final RelayClient? relay;
}
