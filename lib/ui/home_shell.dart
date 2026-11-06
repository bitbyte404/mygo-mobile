import 'package:flutter/material.dart';

import '../plugins/plugin_manager.dart';
import '../runtime/manifest.dart';
import '../services.dart';
import 'browse_page.dart';
import 'detail_pages.dart';
import 'me_page.dart';
import 'now_playing.dart';
import 'plugins_page.dart';
import 'search_page.dart';
import 'settings_page.dart';

IconData navIcon(NavItem n) {
  if (n.builtin.isNotEmpty) {
    switch (n.builtin) {
      case 'home':
        return Icons.home_outlined;
      case 'liked':
        return Icons.favorite_border;
      case 'savedAlbums':
        return Icons.album_outlined;
      case 'stations':
        return Icons.radio;
      case 'shows':
        return Icons.podcasts;
    }
  }
  switch (n.icon) {
    case 'home':
      return Icons.home_outlined;
    case 'album':
      return Icons.album_outlined;
    case 'artist':
      return Icons.person_outline;
    case 'playlist':
      return Icons.queue_music;
    case 'radio':
      return Icons.radio;
    case 'podcast':
      return Icons.podcasts;
    case 'chart':
      return Icons.bar_chart;
    case 'calendar':
      return Icons.calendar_today_outlined;
    case 'heart':
      return Icons.favorite_border;
    case 'search':
      return Icons.search;
    case 'star':
      return Icons.star_outline;
  }
  return Icons.music_note_outlined;
}

String navTitle(InstalledPlugin p, NavItem n) {
  if (n.title.isNotEmpty) return p.t(n.title);
  final s = svc.s;
  return switch (n.builtin) {
    'home' => s['home'],
    'liked' => s['liked'],
    'savedAlbums' => s['savedAlbums'],
    'stations' => s['stations'],
    'shows' => s['shows'],
    _ => n.page,
  };
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  int _nav = 0; // which navigation entry the Discover tab shows
  int _gen = 0; // bumps to reload a tab when it's opened again

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([svc.plugins, svc.app]),
      builder: (context, _) {
        final s = svc.s;
        final p = svc.plugins.active;
        if (p != null && svc.app.activePlugin != p.id) svc.app.setActivePlugin(p.id);
        final nav = p?.navigation ?? const <NavItem>[];
        if (_nav >= nav.length) _nav = 0;
        final item = nav.isEmpty ? null : nav[_nav];
        final title = switch (_tab) {
          0 => p == null ? s['appName'] : (item == null ? p.name : navTitle(p, item)),
          1 => s['search'],
          _ => s['me'],
        };
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (svc.plugins.plugins.length > 1)
                PopupMenuButton<String>(
                  tooltip: s['chooseSource'],
                  icon: const Icon(Icons.swap_horiz),
                  onSelected: (id) {
                    svc.plugins.setActive(id);
                    setState(() {
                      _nav = 0;
                      _gen++;
                    });
                  },
                  itemBuilder: (_) => [
                    for (final x in svc.plugins.plugins) CheckedPopupMenuItem(value: x.id, checked: x.id == p?.id, child: Text(x.name)),
                  ],
                ),
            ],
          ),
          drawer: _drawer(context, p, nav),
          body: Column(children: [
            Expanded(
              child: p == null
                  ? const _NoPlugins()
                  : p.worker == null
                      ? _PluginBroken(plugin: p)
                      : IndexedStack(index: _tab, children: [
                          KeyedSubtree(key: ValueKey('d$_gen/${p.id}/$_nav'), child: _navView(context, p, item)),
                          KeyedSubtree(key: ValueKey('s/${p.id}'), child: SearchView(pluginId: p.id)),
                          KeyedSubtree(key: ValueKey('m$_gen/${p.id}'), child: MeView(pluginId: p.id)),
                        ]),
            ),
            const MiniPlayer(),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() {
              if (i != 1) _gen++; // pages refresh each time they're opened
              _tab = i;
            }),
            destinations: [
              NavigationDestination(icon: Icon(item == null ? Icons.explore_outlined : navIcon(item)), label: item == null || p == null ? s['discover'] : navTitle(p, item)),
              NavigationDestination(icon: const Icon(Icons.search), label: s['search']),
              NavigationDestination(icon: const Icon(Icons.person_outline), label: s['me']),
            ],
          ),
        );
      },
    );
  }

  Widget _navView(BuildContext context, InstalledPlugin p, NavItem? item) {
    if (item == null) return BrowseView(pluginId: p.id);
    if (item.page.isNotEmpty) return BrowseView(pluginId: p.id, page: item.page);
    switch (item.builtin) {
      case 'home':
        return BrowseView(pluginId: p.id);
      case 'liked':
        return LikedView(pluginId: p.id);
      case 'stations':
        return StationsView(pluginId: p.id);
    }
    return Center(child: Text(svc.s['errUnsupported']));
  }

  Widget _drawer(BuildContext context, InstalledPlugin? p, List<NavItem> nav) {
    final s = svc.s;
    return NavigationDrawer(
      selectedIndex: _tab == 0 && nav.isNotEmpty ? _nav : null,
      onDestinationSelected: (i) {
        Navigator.pop(context);
        if (i < nav.length) {
          final n = nav[i];
          if (n.builtin == 'savedAlbums') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => SavedAlbumsScreen(pluginId: p!.id, title: navTitle(p, n))));
            return;
          }
          setState(() {
            _nav = i;
            _tab = 0;
            _gen++;
          });
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 16, 10),
          child: Text(p?.name ?? s['appName'], style: Theme.of(context).textTheme.titleLarge),
        ),
        if (p != null)
          for (final n in nav) NavigationDrawerDestination(icon: Icon(navIcon(n)), label: Text(navTitle(p, n))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8), child: Divider()),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.history),
          title: Text(s['recent']),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => RecentScreen(pluginId: p?.id)));
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.extension_outlined),
          title: Text(s['plugins']),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PluginsPage()));
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.settings_outlined),
          title: Text(s['settings']),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
          },
        ),
      ],
    );
  }
}

class _NoPlugins extends StatelessWidget {
  const _NoPlugins();

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.extension_outlined, size: 64),
          const SizedBox(height: 16),
          Text(s['noPlugins'], style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(s['noPluginsHint'], textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: () => addPlugin(context), icon: const Icon(Icons.add), label: Text(s['addPlugin'])),
          const SizedBox(height: 12),
          ActionChip(
            avatar: const Icon(Icons.code, size: 18),
            label: const Text('bitbyte404/mygo-music-kugou-lite'),
            onPressed: () => installFromRepo(context, 'bitbyte404/mygo-music-kugou-lite'),
          ),
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text('${plugin.name}: ${plugin.error ?? ''}', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => svc.plugins.restart(plugin), child: Text(svc.s['retry'])),
        ]),
      ),
    );
  }
}
