// The adaptive page frame: room for the bars over a page (from MediaQuery
// padding, which the shell sets from the system's insets plus its own bars),
// the page padding of each width class, and MgPage, MyGo's top scroll edge.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mygo_mobile/ui/components/components.dart';
import 'package:mygo_mobile/ui/theme/mg_theme.dart';

String fmtDuration(Duration d) {
  final m = d.inMinutes, s = d.inSeconds % 60;
  if (m >= 60) return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The page's horizontal padding: 16 on a phone, 28 beside the sidebar
/// (MyGo: pagePad 40 less a row's own 12).
double pageHPad(BuildContext context) => MediaQuery.sizeOf(context).width >= 600 ? 28 : 16;

bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// The padding of a page's scroll view: the bars over it at the top and the
/// foot (MediaQuery padding, set by the shell and MgPage), and [h] at the sides.
EdgeInsets pageInsets(BuildContext context, {double? h, double extraBottom = 24}) {
  final pad = MediaQuery.paddingOf(context);
  final x = h ?? pageHPad(context);
  final kb = MediaQuery.viewInsetsOf(context).bottom;
  return EdgeInsets.fromLTRB(x + pad.left, pad.top + MgSize.pageGap, x + pad.right, math.max(pad.bottom, kb) + extraBottom);
}


/// A page of the content area: what scrolls goes under a strip along the top
/// (the status bar and, with [back], a back button) which fills in as
/// content goes under it and shows [title] once the page's own heading has
/// scrolled away (MyGo's pageTop edge, 180 ms). Its child reads the room the
/// strip takes from MediaQuery.paddingOf and attaches to the
/// PrimaryScrollController.
class MgPage extends StatefulWidget {
  const MgPage({super.key, required this.child, this.title = '', this.back, this.actions = const [], this.titleAfter = 64, this.backLabel});
  final Widget child;
  final String title;
  final String? backLabel; // default: the platform's localized "Back"
  final bool? back; // null: when the navigator can pop
  final List<Widget> actions;
  final double titleAfter;

  @override
  State<MgPage> createState() => _MgPageState();
}

class _MgPageState extends State<MgPage> {
  final _scroll = ScrollController();
  bool _under = false, _titled = false;
  static const bar = 48.0;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final px = n.metrics.pixels - n.metrics.minScrollExtent;
    final under = px > 0.5, titled = px > widget.titleAfter;
    if (under != _under || titled != _titled) {
      setState(() {
        _under = under;
        _titled = titled;
      });
    }
    return false;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.mg;
    final mq = MediaQuery.of(context);
    final back = widget.back ?? (ModalRoute.of(context)?.canPop ?? false);
    final showBar = back || widget.actions.isNotEmpty;
    final top = mq.padding.top + (showBar ? bar : 0);
    return ColoredBox(
      color: p.bg,
      child: Stack(children: [
        Positioned.fill(
          child: MediaQuery(
            data: mq.copyWith(padding: mq.padding.copyWith(top: top)),
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: PrimaryScrollController(controller: _scroll, child: widget.child),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top,
          child: IgnorePointer(
            ignoring: !showBar,
            child: AnimatedContainer(
              duration: MgMotion.edge,
              decoration: BoxDecoration(
                color: _under ? p.bg.withValues(alpha: 0.94) : p.bg.withValues(alpha: 0),
                border: Border(bottom: BorderSide(color: _under ? p.hairline : Colors.transparent, width: 0.5)),
              ),
              padding: EdgeInsets.only(top: mq.padding.top, left: mq.padding.left + 4, right: mq.padding.right + 4),
              child: !showBar
                  ? null
                  : Row(children: [
                      if (back) MgIconButton(MgIcons.back, size: 22, color: p.text, tooltip: widget.backLabel ?? MaterialLocalizations.of(context).backButtonTooltip, onTap: () => Navigator.maybePop(context)) else const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedOpacity(
                          opacity: _titled ? 1 : 0,
                          duration: MgMotion.edge,
                          child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text)),
                        ),
                      ),
                      ...widget.actions,
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}

