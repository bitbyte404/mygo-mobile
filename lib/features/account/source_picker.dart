import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/features/shell/navigation.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// The plugins installed, to choose the active one (MyGo's source switcher).
Future<void> chooseSource(BuildContext context) async {
  final s = svc.s;
  await showMgSheet<void>(
    context,
    builder: (ctx) {
      final p = ctx.mg;
      final active = svc.plugins.active?.id;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: Text(s['chooseSource'], style: MgType.section.copyWith(fontSize: 17, color: p.text))),
          for (final x in svc.plugins.plugins)
            MgListRow(
              leading: MgIcon(MgIcons.check, size: 18, color: x.id == active ? p.accent : Colors.transparent),
              label: x.name,
              sub: x.manifest.version,
              onTap: () {
                Navigator.pop(ctx);
                svc.plugins.setActive(x.id);
                shellState.go('nav:0');
              },
            ),
        ]),
      );
    },
  );
}
