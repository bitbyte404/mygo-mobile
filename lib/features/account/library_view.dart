// The library ("我的"): account, the plugin's pages, playlists, plugins and
// settings. On a phone it stands in for the desktop sidebar.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/data/plugins/plugin_manager.dart';
import 'package:mygo_mobile/features/browse/browse_view.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/playlist/playlist_screens.dart';
import 'package:mygo_mobile/features/plugins/plugins_page.dart';
import 'package:mygo_mobile/features/settings/settings_page.dart';
import 'package:mygo_mobile/features/shell/destinations.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

import 'sign_in.dart';
import 'source_picker.dart';

/// The library: the account, the plugin's pages (on a phone, the sidebar's
/// entries live here), playlists, plugins and settings.
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
    final p = svc.plugin(widget.pluginId);
    if (p == null) return const SizedBox.shrink();
    return Loader<Account?>(
      key: ValueKey(_gen),
      pluginId: widget.pluginId,
      load: () => svc.music.account(p.id),
      builder: (context, a, refresh) => _body(context, p, a),
    );
  }

  Widget _body(BuildContext context, InstalledPlugin p, Account? a) {
    final s = svc.s;
    final pal = context.mg;
    final compact = isCompact(context);
    final rows = <Widget>[
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: MgHeading(s['me'], compact: compact)),
    ];
    if (p.can('account') || p.can('signIn')) {
      if (a == null) {
        rows.add(Container(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: pal.hover, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            MgIcon(MgIcons.user, size: 40, color: pal.muted),
            const SizedBox(height: 10),
            Text(p.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
            const SizedBox(height: 4),
            Text(s['signedOutHint'], textAlign: TextAlign.center, style: TextStyle(color: pal.muted, fontSize: 13)),
            const SizedBox(height: 14),
            if (p.can('signIn'))
              PillButton(
                primary: true,
                icon: MgIcons.qr,
                label: s['signIn'],
                onTap: () async {
                  if (await signIn(context, p)) setState(() => _gen++);
                },
              ),
          ]),
        ));
      } else {
        rows.add(MgListRow(
          leading: CoverArt(a.imageUrl, size: 52, round: true, icon: MgIcons.user),
          label: a.name,
          sub: p.name,
          trailing: a.page.isNotEmpty ? MgIcon(MgIcons.forward, size: 16, color: pal.faint) : null,
          onTap: a.page.isEmpty ? null : () => pushPage(context, BrowseScreen(pluginId: p.id, page: a.page, title: s['myPage'])),
        ));
      }
    }
    if (svc.plugins.plugins.length > 1) {
      rows.add(MgListRow(icon: MgIcons.swap, label: s['chooseSource'], sub: p.name, onTap: () => chooseSource(context)));
    }
    rows.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: MgSectionTitle(p.name, top: 18)));
    for (final e in svc.navEntries(p).where((e) => !e.isHome)) {
      rows.add(MgListRow(icon: navIcon(e.icon), label: e.title, trailing: MgIcon(MgIcons.forward, size: 16, color: pal.faint), onTap: () => pushPage(context, entryPage(p.id, e, pushed: true))));
    }
    if (p.can('playlists')) {
      rows.add(MgListRow(icon: MgIcons.playlist, label: s['playlists'], trailing: MgIcon(MgIcons.forward, size: 16, color: pal.faint), onTap: () => pushPage(context, PlaylistsScreen(pluginId: p.id))));
    }
    rows.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: MgSectionTitle(s['appName'], top: 18)));
    rows.add(MgListRow(icon: MgIcons.plug, label: s['plugins'], trailing: MgIcon(MgIcons.forward, size: 16, color: pal.faint), onTap: () => pushPage(context, const PluginsPage())));
    rows.add(MgListRow(icon: MgIcons.settings, label: s['settings'], trailing: MgIcon(MgIcons.forward, size: 16, color: pal.faint), onTap: () => pushPage(context, const SettingsPage())));
    if (a != null && p.can('signOut')) {
      rows.add(MgListRow(
        icon: MgIcons.signOut,
        label: s['signOut'],
        danger: true,
        onTap: () async {
          final yes = await showMgConfirm(context, title: '${s['signOut']}?', ok: s['signOut'], cancel: s['cancel']);
          if (!yes) return;
          try {
            await svc.music.signOut(p.id);
          } catch (e) {
            if (context.mounted) toast(context, svc.describe(e));
          }
          setState(() => _gen++);
        },
      ));
    }
    return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: pageInsets(context, h: pageHPad(context) - 12), children: rows);
  }
}

