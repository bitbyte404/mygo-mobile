// Loading a page's data behind a skeleton of the page, pull-to-refresh, and an error view
// that knows the remedies a plugin's error asks for (sign in, settings).
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/errors.dart';
import 'package:mygo_mobile/features/account/sign_in.dart';
import 'package:mygo_mobile/features/common/skeletons.dart';
import 'package:mygo_mobile/features/plugins/plugin_settings_page.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// What pages last loaded, kept for the session so coming back to a page
/// (a tab, a back swipe) shows it at once instead of loading it again.
class PageCache {
  PageCache._();
  static final _entries = <String, (Object?, DateTime)>{};
  static const _max = 60;

  static (Object?, DateTime)? get(String key) => _entries[key];

  static void put(String key, Object? value) {
    _entries.remove(key);
    _entries[key] = (value, DateTime.now());
    while (_entries.length > _max) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Everything a plugin's pages showed, after its account changed.
  static void clear([String? pluginId]) {
    if (pluginId == null) {
      _entries.clear();
    } else {
      _entries.removeWhere((k, _) => k.startsWith('$pluginId/'));
    }
  }
}

/// Loads what a page shows, with pull-to-refresh, and an error view that
/// knows sign-in and settings. With a [cacheKey], a page opened again shows
/// what it showed last; once that is older than [fresh] it is reloaded
/// quietly behind it, with no skeleton.
class Loader<T> extends StatefulWidget {
  const Loader({
    super.key,
    required this.load,
    required this.builder,
    this.pluginId,
    this.skeleton = SkeletonKind.tracks,
    this.skeletonHeader,
    this.cacheKey,
    this.fresh = const Duration(minutes: 10),
  });
  final Future<T> Function() load;

  /// Where this page's data is kept between visits, starting with its plugin id.
  final String? cacheKey;

  /// How long kept data is shown without reloading it.
  final Duration fresh;

  /// The page's shape while it loads.
  final SkeletonKind skeleton;

  /// Shown over the skeleton as it will be over the page (a source switcher).
  final Widget? skeletonHeader;
  final Widget Function(BuildContext context, T value, Future<void> Function() refresh) builder;
  final String? pluginId;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  bool _has = false;
  T? _value;
  Object? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    final key = widget.cacheKey;
    final kept = key == null ? null : PageCache.get(key);
    if (kept != null && kept.$1 is T) {
      _has = true;
      _value = kept.$1 as T;
      // Stale: reload behind it, keeping it if the reload fails.
      if (DateTime.now().difference(kept.$2) >= widget.fresh) _run(quiet: true);
    } else {
      _run();
    }
  }

  /// Loads the page. Loud: the skeleton (or the error) replaces what is shown.
  /// Quiet: what is shown stays until the new data arrives.
  Future<void> _run({bool quiet = false, bool tell = false}) async {
    final gen = ++_gen;
    if (!quiet && (_has || _error != null)) {
      setState(() {
        _has = false;
        _error = null;
      });
    }
    try {
      final v = await widget.load();
      final key = widget.cacheKey;
      if (key != null) PageCache.put(key, v);
      if (!mounted || gen != _gen) return;
      setState(() {
        _has = true;
        _value = v;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      if (!quiet) {
        setState(() => _error = e);
      } else if (tell) {
        toast(context, svc.describe(e));
      }
    }
  }

  // Pull-to-refresh keeps the page under its indicator.
  // A failed refresh says why and leaves the page as it was.
  Future<void> _refresh() => _run(quiet: _has, tell: true);

  Future<void> _retry() => _run();

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    Widget child;
    if (_has) {
      child = KeyedSubtree(
        key: const ValueKey('done'),
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: p.accent,
          backgroundColor: p.popover,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: widget.builder(context, _value as T, _refresh),
        ),
      );
    } else if (_error != null) {
      child = KeyedSubtree(key: const ValueKey('error'), child: ErrorView(error: _error!, onRetry: _retry, pluginId: widget.pluginId));
    } else {
      child = KeyedSubtree(key: const ValueKey('loading'), child: PageSkeleton(kind: widget.skeleton, header: widget.skeletonHeader));
    }
    // Content fades in over its skeleton, as covers fade over theirs.
    return AnimatedSwitcher(duration: MgMotion.artFade, switchInCurve: Curves.easeOut, child: child);
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

