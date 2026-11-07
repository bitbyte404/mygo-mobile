// Adds the insets the engine doesn't report (the web: notch, home indicator,
// Safari's toolbar) to MediaQuery's view padding, so everything that keeps
// clear of the system's bars (the shell, Now Playing, sheets, toasts) does so
// in the browser and the home-screen app too.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'platform/platform.dart';

class SystemInsets extends StatelessWidget {
  const SystemInsets({super.key, required this.child, this.insets});
  final Widget child;

  /// For tests; the platform's otherwise.
  final ValueListenable<EdgeInsets>? insets;

  /// [mq] with [extra] folded into its view padding (each side the larger),
  /// and padding as the view padding less what the keyboard covers.
  static MediaQueryData apply(MediaQueryData mq, EdgeInsets extra) {
    if (extra == EdgeInsets.zero) return mq;
    final vp = EdgeInsets.fromLTRB(
      math.max(mq.viewPadding.left, extra.left),
      math.max(mq.viewPadding.top, extra.top),
      math.max(mq.viewPadding.right, extra.right),
      math.max(mq.viewPadding.bottom, extra.bottom),
    );
    final kb = mq.viewInsets;
    return mq.copyWith(
      viewPadding: vp,
      padding: EdgeInsets.fromLTRB(
        math.max(0, vp.left - kb.left),
        math.max(0, vp.top - kb.top),
        math.max(0, vp.right - kb.right),
        math.max(0, vp.bottom - kb.bottom),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<EdgeInsets>(
        valueListenable: insets ?? systemInsets,
        builder: (context, extra, child) => MediaQuery(data: apply(MediaQuery.of(context), extra), child: child!),
        child: child,
      );
}
