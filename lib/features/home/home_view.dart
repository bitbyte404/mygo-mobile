// Home: the plugin's own home page under a greeting.
import 'package:flutter/material.dart';
import 'package:mygo_mobile/app/services.dart';
import 'package:mygo_mobile/core/models/models.dart';
import 'package:mygo_mobile/features/browse/browse_view.dart';
import 'package:mygo_mobile/features/common/loader.dart';
import 'package:mygo_mobile/features/common/skeletons.dart';
import 'package:mygo_mobile/ui/ui.dart';

/// What to say at this hour (ui_kit.go greeting).
String greeting(DateTime now) {
  final s = svc.s;
  final h = now.hour;
  if (h < 5) return s['goodNight'];
  if (h < 12) return s['goodMorning'];
  if (h < 18) return s['goodAfternoon'];
  return s['goodEvening'];
}

String todayLine(DateTime d) {
  final s = svc.s;
  if (s.zh) {
    const wd = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${d.month}月${d.day}日 ${wd[d.weekday - 1]}';
  }
  const wd = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const mo = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${wd[d.weekday - 1]}, ${mo[d.month - 1]} ${d.day}';
}

class _Home {
  _Home(this.browse, this.account);
  final Browse browse;
  final Account? account;
}

/// A plugin's Home, under a greeting (ui_pages.go homeHello) in place of the
/// plugin's own "Home" title, which the navigation already says; on a phone,
/// the plugin's other pages as chips under it.
class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.pluginId, this.header});
  final String pluginId;
  final Widget? header; // the source switcher etc., over the greeting

  Future<_Home> _load() async {
    // The greeting names whoever is signed in; Home doesn't wait on a failure of it.
    final acc = svc.music.account(pluginId).then<Account?>((a) => a, onError: (Object _) => null);
    final b = await svc.music.home(pluginId);
    return _Home(b, await acc);
  }

  @override
  Widget build(BuildContext context) {
    return Loader<_Home>(
      key: ValueKey('$pluginId/home'),
      pluginId: pluginId,
      skeleton: SkeletonKind.browse,
      skeletonHeader: header,
      load: _load,
      builder: (context, h, _) {
        final now = DateTime.now();
        final name = h.account?.name ?? '';
        final hello = name.isEmpty ? greeting(now) : '${greeting(now)}${svc.s.zh ? '，' : ', '}$name';
        return BrowseBody(
          pluginId: pluginId,
          browse: h.browse,
          header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ?header,
            MgHeading(hello, eyebrow: todayLine(now), compact: isCompact(context)),
          ]),
          chips: isCompact(context),
        );
      },
    );
  }
}

