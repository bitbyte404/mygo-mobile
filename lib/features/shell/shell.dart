// The app's frame, adaptive by width class (lib/ui/theme/tokens.dart):
//  - compact (< 600): the content full screen, under a tab bar (Home, Search,
//    Library) and the mini player; the library stands in for the sidebar.
//  - medium (600-840): an icon rail, the player bar along the foot.
//  - expanded (>= 840): MyGo desktop: the 232-point sidebar with the plugin's
//    navigation, search and playlists; the content; the 84-point player bar.
// Now Playing covers it all in every class. Edge to edge: the content and the
// bars draw under the status and navigation bars; the content learns the
// room they take (system insets plus the app's own bars) from MediaQuery
// padding, so nothing it shows is hidden under them.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/data/navigation.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/features/account/library_view.dart';
import 'package:mygo_mobile/features/account/source_picker.dart';
import 'package:mygo_mobile/features/now_playing/mini_player.dart';
import 'package:mygo_mobile/features/now_playing/now_playing_controller.dart';
import 'package:mygo_mobile/features/now_playing/now_playing_layer.dart';
import 'package:mygo_mobile/features/playlist/playlist_screens.dart';
import 'package:mygo_mobile/features/plugins/install_flow.dart';
import 'package:mygo_mobile/features/plugins/plugins_page.dart';
import 'package:mygo_mobile/features/search/search_view.dart';
import 'package:mygo_mobile/features/settings/settings_page.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'destinations.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'navigation.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _hero = HeroController(createRectTween: (b, e) => MaterialRectArcTween(begin: b, end: e));
  bool _nestedCanPop = false;

  @override
  void initState() {
    super.initState();
    closeNowPlaying = nowPlaying.close;
    svc.music.onAccountChanged = PageCache.clear;
  }

  /// Scroll positions of the tab pages, kept across switching tabs.
  final _scroll = PageStorageBucket();

  String _homeKey(List<NavEntry> entries) => entries.firstWhere((e) => e.isHome, orElse: () => entries.first).key;

  Widget _root(InstalledPlugin? p, List<NavEntry> entries, MgWidth wc) {
    final s = svc.s;
    if (p == null) return const MgPage(back: false, child: _NoPlugins());
    if (!p.running) return MgPage(back: false, child: _PluginBroken(plugin: p));
    switch (shellState.dest) {
      case 'search':
        return MgPage(back: false, title: s['search'], child: SearchView(pluginId: p.id, initialQuery: shellState.searchQuery));
      case 'library':
        return MgPage(back: false, title: s['me'], child: MeView(pluginId: p.id));
      case 'plugins':
        return const PluginsPage(back: false);
      case 'settings':
        return const SettingsPage(back: false);
    }
    final e = entries.firstWhere((e) => e.key == shellState.dest, orElse: () => entries.firstWhere((e) => e.isHome, orElse: () => entries.first));
    final switcher = wc == MgWidth.compact && svc.plugins.plugins.length > 1 ? const _SourceChip() : null;
    return entryPage(p.id, e, homeHeader: switcher);
  }

  void _onPop(bool didPop, Object? _) {
    if (didPop) return;
    if (nowPlaying.isOpen) {
      nowPlaying.close();
    } else if (contentNavKey.currentState?.canPop() ?? _nestedCanPop) {
      // Asked of the navigator itself: the flag lags a page pushed this frame.
      contentNavKey.currentState?.maybePop();
    } else {
      final entries = svc.navEntries(svc.plugins.active);
      final home = _homeKey(entries);
      if (shellState.dest != home) shellState.go(home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([svc.plugins, svc.app, shellState, nowPlaying]),
      builder: (context, _) {
        final p = svc.plugins.active;
        if (p != null && svc.app.activePlugin != p.id) svc.app.setActivePlugin(p.id);
        final entries = svc.navEntries(p);
        final pal = context.mg;
        final mq = MediaQuery.of(context);
        final vp = mq.viewPadding;
        final wc = widthClassOf(mq.size.width);
        final homeKey = _homeKey(entries);
        final atHome = shellState.dest == homeKey;

        Widget content(EdgeInsets padding) => MediaQuery(
              data: mq.copyWith(padding: padding),
              child: NotificationListener<NavigationNotification>(
                onNotification: (n) {
                  if (n.canHandlePop != _nestedCanPop) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _nestedCanPop = n.canHandlePop);
                    });
                  }
                  return false;
                },
                child: HeroControllerScope(
                  controller: _hero,
                  child: Navigator(
                    key: contentNavKey,
                    pages: [MaterialPage<void>(key: ValueKey('${p?.id}/${shellState.dest}/${shellState.gen}'), child: PageStorage(bucket: _scroll, child: _root(p, entries, wc)))],
                    onDidRemovePage: (_) {},
                  ),
                ),
              ),
            );

        Widget body;
        if (wc == MgWidth.compact) {
          body = ValueListenableBuilder<Track?>(
            valueListenable: svc.player.current,
            builder: (context, track, _) {
              final bottom = MgSize.tabBarHeight + vp.bottom + (track != null ? MgSize.miniPlayerHeight + 8 : 0);
              return Stack(children: [
                Positioned.fill(child: content(EdgeInsets.fromLTRB(vp.left, vp.top, vp.right, bottom))),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(padding: EdgeInsets.only(left: vp.left, right: vp.right), child: const MiniPlayer()),
                    if (track != null) const SizedBox(height: 8),
                    // Full width, under a landscape cutout too; its items keep clear of it.
                    _TabBar(
                      selected: shellState.dest == 'search' ? 1 : (atHome ? 0 : 2),
                      bottomInset: vp.bottom,
                      sideInsets: EdgeInsets.only(left: vp.left, right: vp.right),
                      onSelect: (i) => shellState.go(switch (i) { 0 => homeKey, 1 => 'search', _ => 'library' }),
                    ),
                  ]),
                ),
              ]);
            },
          );
        } else {
          final railW = (wc == MgWidth.expanded ? MgSize.sidebarWidth : MgSize.railWidth) + vp.left;
          body = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: railW,
              padding: EdgeInsets.only(left: vp.left),
              decoration: BoxDecoration(color: pal.sidebar, border: Border(right: BorderSide(color: pal.hairline, width: 0.5))),
              child: wc == MgWidth.expanded ? _Sidebar(plugin: p, entries: entries) : _Rail(entries: entries, plugin: p),
            ),
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: content(EdgeInsets.fromLTRB(0, vp.top, vp.right, MgSize.playerBarHeight + vp.bottom))),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: EdgeInsets.only(bottom: vp.bottom, right: vp.right),
                    decoration: BoxDecoration(color: pal.bg.withValues(alpha: 0.96), border: Border(top: BorderSide(color: pal.hairline, width: 0.5))),
                    child: const PlayerBar(),
                  ),
                ),
              ]),
            ),
          ]);
        }
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: mgOverlay(!pal.dark),
          child: PopScope(
            // A web app never pops itself: leaving it in the browser's history
            // reloads it from the launch screen.
            canPop: !kIsWeb && !nowPlaying.isOpen && !_nestedCanPop && atHome,
            onPopInvokedWithResult: _onPop,
            // A Material, for what Flutter's text fields need above them;
            // it draws nothing but the page color (no ink: NoSplash).
            child: Material(
              color: pal.bg,
              child: Stack(children: [
                Positioned.fill(child: body),
                Positioned.fill(child: NowPlayingLayer(wide: wc == MgWidth.expanded)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// The phone's tab bar: Home, Search, Library. It reaches under the gesture
/// bar (or the three buttons) on a translucent fill; its items sit above it.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onSelect, required this.bottomInset, this.sideInsets = EdgeInsets.zero});
  final int selected;
  final ValueChanged<int> onSelect;
  final double bottomInset;
  final EdgeInsets sideInsets;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final s = svc.s;
    final items = [(MgIcons.home, s['home']), (MgIcons.search, s['search']), (MgIcons.library, s['me'])];
    return Container(
      height: MgSize.tabBarHeight + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset, left: sideInsets.left, right: sideInsets.right),
      decoration: BoxDecoration(color: p.bg.withValues(alpha: 0.97), border: Border(top: BorderSide(color: p.hairline, width: 0.5))),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: Pressable(
              onTap: () => onSelect(i),
              pressedScale: 0.9,
              semanticLabel: items[i].$2,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                MgIcon(items[i].$1, size: 22, color: i == selected ? p.accent : p.muted),
                const SizedBox(height: 3),
                Text(items[i].$2, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: i == selected ? p.accent : p.muted)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// A sidebar entry (ui_main.go navItem): 34 tall, 8-point corners, a 17-point
/// icon in the accent and the press fill when chosen.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final MgIconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.98,
        color: selected ? p.press : Colors.transparent,
        pressedColor: p.hover,
        borderRadius: BorderRadius.circular(MgRadius.nav),
        semanticLabel: label,
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              MgIcon(icon, size: 17, color: selected ? p.accent : p.text),
              const SizedBox(width: 10),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.nav.copyWith(color: p.text))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({required this.plugin, required this.entries});
  final InstalledPlugin? plugin;
  final List<NavEntry> entries;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final _search = TextEditingController();
  Future<List<Playlist>>? _lists;
  String? _listsFor;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final s = svc.s;
    final pl = widget.plugin;
    final top = MediaQuery.viewPaddingOf(context).top;
    if (pl != null && pl.can('playlists') && _listsFor != pl.id) {
      _listsFor = pl.id;
      _lists = svc.music.playlists(pl.id).catchError((Object _) => <Playlist>[]);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(14, top + 14, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The source switcher: a line of text atop it (ui_main.go sourceSwitcher).
        Pressable(
          onTap: svc.plugins.plugins.length > 1 ? () => chooseSource(context) : null,
          color: Colors.transparent,
          pressedColor: p.hover,
          borderRadius: BorderRadius.circular(7),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(children: [
            Flexible(child: Text(pl?.name ?? s['appName'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.muted))),
            if (svc.plugins.plugins.length > 1) ...[const SizedBox(width: 4), MgIcon(MgIcons.upDown, size: 11, color: p.faint)],
          ]),
        ),
        const SizedBox(height: 8),
        if (pl != null && pl.can('search')) ...[
          MgTextField(controller: _search, hint: s['search'], icon: MgIcons.search, action: TextInputAction.search, onSubmitted: (q) => shellState.search(q.trim())),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            for (final e in widget.entries)
              _NavItem(icon: navIcon(e.icon), label: e.title, selected: shellState.dest == e.key, onTap: () => shellState.go(e.key)),
            if (pl != null && pl.can('search')) _NavItem(icon: MgIcons.search, label: s['search'], selected: shellState.dest == 'search', onTap: () => shellState.go('search')),
            if (_lists != null)
              FutureBuilder<List<Playlist>>(
                future: _lists,
                builder: (context, snap) {
                  final lists = snap.data ?? const [];
                  if (lists.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
                      child: Text(s['myPlaylists'], style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.muted)),
                    ),
                    for (final l in lists.take(30)) _NavItem(icon: MgIcons.playlist, label: l.name, selected: false, onTap: () => pushPage(context, PlaylistScreen(pluginId: pl!.id, playlist: l))),
                  ]);
                },
              ),
          ]),
        ),
        Divider(height: 16, color: p.hairline),
        _NavItem(icon: MgIcons.user, label: s['me'], selected: shellState.dest == 'library', onTap: () => shellState.go('library')),
        _NavItem(icon: MgIcons.plug, label: s['plugins'], selected: shellState.dest == 'plugins', onTap: () => shellState.go('plugins')),
        _NavItem(icon: MgIcons.settings, label: s['settings'], selected: shellState.dest == 'settings', onTap: () => shellState.go('settings')),
      ]),
    );
  }
}

/// The medium width's rail: the sidebar's entries as icons.
class _Rail extends StatelessWidget {
  const _Rail({required this.entries, required this.plugin});
  final List<NavEntry> entries;
  final InstalledPlugin? plugin;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final s = svc.s;
    final top = MediaQuery.viewPaddingOf(context).top;
    Widget item(MgIconData icon, String label, String dest) {
      final on = shellState.dest == dest;
      return Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Pressable(
            onTap: () => shellState.go(dest),
            pressedScale: 0.9,
            color: on ? p.press : Colors.transparent,
            pressedColor: p.hover,
            borderRadius: BorderRadius.circular(12),
            semanticLabel: label,
            child: SizedBox(width: 52, height: 44, child: Center(child: MgIcon(icon, size: 20, color: on ? p.accent : p.text))),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: top + 14, bottom: 14),
      child: Column(children: [
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            for (final e in entries) Center(child: item(navIcon(e.icon), e.title, e.key)),
            if (plugin != null && plugin!.can('search')) Center(child: item(MgIcons.search, s['search'], 'search')),
          ]),
        ),
        item(MgIcons.user, s['me'], 'library'),
        item(MgIcons.plug, s['plugins'], 'plugins'),
        item(MgIcons.settings, s['settings'], 'settings'),
      ]),
    );
  }
}

/// On a phone with more than one plugin: which one Home shows, over the
/// greeting.
class _SourceChip extends StatelessWidget {
  const _SourceChip();

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return Align(
      alignment: Alignment.centerLeft,
      child: Pressable(
        onTap: () => chooseSource(context),
        color: Colors.transparent,
        pressedColor: p.hover,
        borderRadius: BorderRadius.circular(7),
        padding: const EdgeInsets.fromLTRB(0, 4, 8, 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(svc.plugins.active?.name ?? '', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.muted)),
          const SizedBox(width: 4),
          MgIcon(MgIcons.upDown, size: 11, color: p.faint),
        ]),
      ),
    );
  }
}

class _NoPlugins extends StatelessWidget {
  const _NoPlugins();

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return Center(
      child: SingleChildScrollView(
        padding: pageInsets(context),
        child: MgEmpty(icon: MgIcons.plug, title: s['noPlugins'], message: s['noPluginsHint'], actions: [
          PillButton(primary: true, icon: MgIcons.plus, label: s['addPlugin'], onTap: () => addPlugin(context)),
          PillButton(icon: MgIcons.code, label: 'bitbyte404/mygo-music-kugou-lite', onTap: () => installFromRepo(context, 'bitbyte404/mygo-music-kugou-lite')),
        ]),
      ),
    );
  }
}

class _PluginBroken extends StatelessWidget {
  const _PluginBroken({required this.plugin});
  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MgEmpty(icon: MgIcons.alert, title: plugin.name, message: plugin.error ?? '', actions: [
        PillButton(icon: MgIcons.refresh, label: svc.s['retry'], onTap: () => svc.plugins.restart(plugin)),
      ]),
    );
  }
}
