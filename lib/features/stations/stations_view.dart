// Radio stations, played as endless queues.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/skeletons.dart';
import 'package:mygo_mobile/ui/ui.dart';

Future<void> playStation(BuildContext context, String pluginId, Station st) async {
  try {
    final tracks = await svc.music.stationNext(pluginId, st.id);
    if (tracks.isEmpty) {
      if (context.mounted) toast(context, svc.s['nothing']);
      return;
    }
    await svc.player.playStation(pluginId, st.id, tracks);
  } catch (e) {
    if (context.mounted) toast(context, svc.describe(e));
  }
}

class StationsView extends StatelessWidget {
  const StationsView({super.key, required this.pluginId, this.title = ''});
  final String pluginId, title;

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    return Loader<List<Station>>(
      pluginId: pluginId,
      skeleton: SkeletonKind.cards,
      load: () => svc.music.stations(pluginId),
      cacheKey: '$pluginId/stations',
      builder: (context, stations, _) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pageInsets(context),
        children: [
          MgHeading(title.isEmpty ? svc.s['stations'] : title, compact: isCompact(context)),
          if (stations.isEmpty) Center(child: Text(svc.s['nothing'], style: TextStyle(color: p.muted))),
          for (final st in stations)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Pressable(
                onTap: () => playStation(context, pluginId, st),
                color: p.hover,
                pressedColor: p.press,
                borderRadius: BorderRadius.circular(14),
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  CoverArt(st.imageUrl, size: 64, radius: MgRadius.card, icon: MgIcons.radio),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(st.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
                      if (st.description.isNotEmpty) ...[const SizedBox(height: 4), Text(st.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.rowSub.copyWith(color: p.muted))],
                    ]),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                    child: Center(child: Padding(padding: const EdgeInsets.only(left: 2), child: MgIcon(MgIcons.play, size: 16, color: p.onAccent))),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

