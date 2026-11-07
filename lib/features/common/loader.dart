// Loading a page's data with a spinner, pull-to-refresh, and an error view
// that knows the remedies a plugin's error asks for (sign in, settings).
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/errors.dart';
import 'package:mygo_mobile/features/account/sign_in.dart';
import 'package:mygo_mobile/features/plugins/plugin_settings_page.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// Loads what a page shows each time it opens, with pull-to-refresh, and an
/// error view that knows sign-in and settings.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.pluginId});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T value, Future<void> Function() refresh) builder;
  final String? pluginId;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> _refresh() async {
    final f = widget.load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        Widget child;
        if (snap.connectionState != ConnectionState.done) {
          child = KeyedSubtree(key: const ValueKey('loading'), child: Padding(padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top), child: const Center(child: MgSpinner())));
        } else if (snap.hasError) {
          child = KeyedSubtree(key: const ValueKey('error'), child: ErrorView(error: snap.error!, onRetry: _refresh, pluginId: widget.pluginId));
        } else {
          child = KeyedSubtree(
            key: const ValueKey('done'),
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: p.accent,
              backgroundColor: p.popover,
              edgeOffset: MediaQuery.paddingOf(context).top,
              child: widget.builder(context, snap.data as T, _refresh),
            ),
          );
        }
        // Content fades in over the spinner, as covers fade over theirs.
        return AnimatedSwitcher(duration: MgMotion.artFade, switchInCurve: Curves.easeOut, child: child);
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.pluginId});
  final Object error;
  final VoidCallback? onRetry;
  final String? pluginId;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final code = error is PluginError ? (error as PluginError).code : '';
    final p = pluginId == null ? null : svc.plugin(pluginId!);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pageInsets(context),
      children: [
        const SizedBox(height: 40),
        MgEmpty(
          icon: code == PluginError.signIn ? MgIcons.lock : MgIcons.alert,
          title: code == PluginError.signIn ? s['signIn'] : s['loadFailed'],
          message: svc.describe(error),
          actions: [
            if (code == PluginError.signIn && p != null)
              PillButton(
                primary: true,
                icon: MgIcons.qr,
                label: s['signIn'],
                onTap: () async {
                  final ok = await signIn(context, p);
                  if (ok) onRetry?.call();
                },
              ),
            if (code == PluginError.setup && p != null)
              PillButton(primary: true, label: s['openSettings'], onTap: () => pushPage(context, PluginSettingsPage(plugin: p))),
            if (onRetry != null) PillButton(icon: MgIcons.refresh, label: s['retry'], onTap: onRetry),
          ],
        ),
      ],
    );
  }
}

