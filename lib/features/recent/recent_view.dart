// Recently played: the source's list and this device's, as one entry.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/tracks.dart';
import 'package:mygo_mobile/features/shell/destinations.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// Recently played, as one entry: the source's own list (its navigation page
/// of it, or its `recent` export) and what this device played.
class RecentView extends StatefulWidget {
  const RecentView({super.key, required this.pluginId, this.sourcePage, this.title = ''});
  final String pluginId;
  final String? sourcePage; // '' → recent(); non-empty → browse(page); null → this device only
  final String title;

  @override
  State<RecentView> createState() => _RecentViewState();
}

class _RecentViewState extends State<RecentView> {
  late bool _source = widget.sourcePage != null;

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final hasSource = widget.sourcePage != null;
    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MgHeading(
        widget.title.isEmpty ? s['recent'] : widget.title,
        compact: isCompact(context),
        trailing: _source ? null : MgIconButton(MgIcons.trash, size: 18, color: context.mg.muted, tooltip: s['clearHistory'], onTap: svc.app.clearHistory),
      ),
      if (hasSource)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SizedBox(
            width: 280,
            child: MgSegmented<bool>(values: const [true, false], labels: [s['fromSource'], s['fromLocal']], selected: _source, onChanged: (v) => setState(() => _source = v)),
          ),
        ),
    ]);
    if (!_source) {
      return ListenableBuilder(
        listenable: svc.app,
        builder: (context, _) => TrackListView(key: const ValueKey('local'), tracks: svc.app.history, header: header),
      );
    }
    final page = widget.sourcePage!;
    return Loader<List<Track>>(
      key: const ValueKey('source'),
      pluginId: widget.pluginId,
      load: () async {
        if (page.isEmpty) return svc.music.recent(widget.pluginId);
        final b = await svc.music.browse(widget.pluginId, page);
        return [for (final sec in b.sections) ...sec.tracks];
      },
      builder: (context, tracks, _) => TrackListView(tracks: tracks, header: header),
    );
  }
}

/// Kept for callers of the old screen: the merged recently played, pushed.
class RecentScreen extends StatelessWidget {
  const RecentScreen({super.key, this.pluginId});
  final String? pluginId;

  @override
  Widget build(BuildContext context) {
    final p = pluginId == null ? null : svc.plugin(pluginId!);
    final e = svc.navEntries(p).firstWhere((e) => e.isRecent);
    return entryPage(pluginId ?? '', e, pushed: true);
  }
}
