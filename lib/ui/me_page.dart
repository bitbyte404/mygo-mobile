import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models.dart';
import '../plugins/plugin_manager.dart';
import '../services.dart';
import 'browse_page.dart';
import 'common.dart';
import 'detail_pages.dart';
import 'plugins_page.dart';
import 'settings_page.dart';

/// Signs in with the plugin, showing what it asks shown on the way: a QR
/// code to scan (host.signInPrompt), and its text. Answers whether it worked.
Future<bool> signIn(BuildContext context, InstalledPlugin p) async {
  svc.plugins.signInPrompt.value = null;
  final call = p.call('signIn');
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _SignInDialog(plugin: p, call: call),
  );
  return ok == true;
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.plugin, required this.call});
  final InstalledPlugin plugin;
  final Future<Object?> call;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.call.then((_) {
      if (mounted) Navigator.pop(context, true);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    return AlertDialog(
      title: Text('${s['signIn']} · ${widget.plugin.name}'),
      content: SizedBox(
        width: 280,
        child: ValueListenableBuilder<SignInPrompt?>(
          valueListenable: svc.plugins.signInPrompt,
          builder: (context, prompt, _) {
            if (_error != null) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text('${s['signInFailed']}: ${svc.describe(_error!)}', textAlign: TextAlign.center),
              ]);
            }
            if (prompt == null) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(s['waiting']),
              ]);
            }
            return Column(mainAxisSize: MainAxisSize.min, children: [
              if (prompt.qr.isNotEmpty)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(data: prompt.qr, size: 220, backgroundColor: Colors.white),
                ),
              const SizedBox(height: 12),
              if (prompt.text.isNotEmpty) Text(prompt.text, textAlign: TextAlign.center),
            ]);
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s['cancel'])),
      ],
    );
  }
}

class MeView extends StatefulWidget {
  const MeView({super.key, required this.pluginId});
  final String pluginId;

  @override
  State<MeView> createState() => _MeViewState();
}

class _MeViewState extends State<MeView> {
  int _gen = 0;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final p = svc.plugin(widget.pluginId);
    if (p == null) return const SizedBox.shrink();
    return Loader<Account?>(
      key: ValueKey(_gen),
      pluginId: widget.pluginId,
      load: () async {
        if (!p.can('account')) return null;
        final r = await p.call('account');
        return r is Map ? Account.fromJson(r) : null;
      },
      builder: (context, a, refresh) {
        final tiles = <Widget>[];
        if (p.can('account') || p.can('signIn')) {
          if (a == null) {
            tiles.add(Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Icon(Icons.account_circle_outlined, size: 56),
                  const SizedBox(height: 8),
                  Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(s['signedOutHint'], textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  if (p.can('signIn'))
                    FilledButton.icon(
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(s['signIn']),
                      onPressed: () async {
                        if (await signIn(context, p)) setState(() => _gen++);
                      },
                    ),
                ]),
              ),
            ));
          } else {
            tiles.add(ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              leading: Cover(a.imageUrl, size: 56, round: true, icon: Icons.person),
              title: Text(a.name, style: Theme.of(context).textTheme.titleLarge),
              subtitle: Text(p.name),
              trailing: a.page.isNotEmpty ? const Icon(Icons.chevron_right) : null,
              onTap: a.page.isEmpty
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrowseScreen(pluginId: p.id, page: a.page, title: s['myPage']))),
            ));
          }
        }
        if (p.can('liked')) {
          tiles.add(ListTile(
            leading: const Icon(Icons.favorite),
            title: Text(s['liked']),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LikedScreen(pluginId: p.id))),
          ));
        }
        if (p.can('playlists')) {
          tiles.add(ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(s['playlists']),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistsScreen(pluginId: p.id))),
          ));
        }
        if (p.can('savedAlbums')) {
          tiles.add(ListTile(
            leading: const Icon(Icons.album),
            title: Text(s['savedAlbums']),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SavedAlbumsScreen(pluginId: p.id))),
          ));
        }
        tiles.add(ListTile(
          leading: const Icon(Icons.history),
          title: Text(s['recent']),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecentScreen(pluginId: p.id))),
        ));
        tiles.add(const Divider());
        tiles.add(ListTile(
          leading: const Icon(Icons.extension),
          title: Text(s['plugins']),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PluginsPage())),
        ));
        tiles.add(ListTile(
          leading: const Icon(Icons.settings),
          title: Text(s['settings']),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
        ));
        if (a != null && p.can('signOut')) {
          tiles.add(ListTile(
            leading: const Icon(Icons.logout),
            title: Text(s['signOut']),
            onTap: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('${s['signOut']}?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s['cancel'])),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s['ok'])),
                  ],
                ),
              );
              if (yes != true) return;
              try {
                await p.call('signOut');
              } catch (e) {
                if (context.mounted) toast(context, svc.describe(e));
              }
              setState(() => _gen++);
            },
          ));
        }
        return ListView(physics: const AlwaysScrollableScrollPhysics(), children: tiles);
      },
    );
  }
}
