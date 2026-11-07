// A song's comments, a page at a time, as the plugin gives them.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/ui/ui.dart';

class CommentsView extends StatefulWidget {
  const CommentsView({super.key, required this.track});
  final Track track;

  @override
  State<CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends State<CommentsView> {
  final List<Comment> _comments = [];
  int _total = 0;
  bool _more = false, _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await svc.music.comments(widget.track, offset: _comments.length);
      if (!mounted) return;
      setState(() {
        _comments.addAll(r.comments);
        _total = r.total > 0 ? r.total : _total;
        _more = r.more;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = svc.s;
    final white = Colors.white;
    if (_error != null && _comments.isEmpty) return Center(child: Text(svc.describe(_error!), style: TextStyle(color: white.withValues(alpha: 0.6))));
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (_more && !_loading && n.metrics.extentAfter < 400) _load();
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        itemCount: _comments.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('${s['comments']}${_total > 0 ? ' · $_total' : ''}', style: MgType.section.copyWith(fontSize: 17, color: white)),
            );
          }
          if (i == _comments.length + 1) {
            if (_loading) return MgShimmer(onDark: true, child: Column(children: [for (var k = 0; k < (_comments.isEmpty ? 6 : 2); k++) SkeletonCommentRow(index: k)]));
            if (_comments.isEmpty) return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(s['noComments'], style: TextStyle(color: white.withValues(alpha: 0.5)))));
            return const SizedBox(height: 24);
          }
          final c = _comments[i - 1];
          final time = c.time > 0 ? DateTime.fromMillisecondsSinceEpoch(c.time).toLocal().toString().substring(0, 16) : '';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CoverArt(c.avatarUrl, size: 34, round: true, icon: MgIcons.user),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.author, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: white.withValues(alpha: 0.6))),
                  const SizedBox(height: 4),
                  Text(c.text, style: TextStyle(fontSize: 14.5, height: 1.45, color: white)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text(time, style: TextStyle(fontSize: 11.5, color: white.withValues(alpha: 0.4))),
                    const Spacer(),
                    if (c.likes > 0) ...[
                      MgIcon(MgIcons.thumb, size: 13, color: white.withValues(alpha: 0.45)),
                      const SizedBox(width: 4),
                      Text('${c.likes}', style: TextStyle(fontSize: 11.5, color: white.withValues(alpha: 0.45), fontFeatures: MgType.tnum)),
                    ],
                  ]),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}
