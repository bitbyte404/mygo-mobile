import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/core/plugin/manifest.dart';
import 'package:mygo_mobile/data/navigation.dart';

List<NavEntry> build(List<NavItem> nav, {bool canRecent = false, Map<String, String> tr = const {}}) => buildNavEntries(
      nav: nav,
      translate: (t) => tr[t] ?? t,
      builtinTitle: (n) => n.builtin,
      recentTitle: '最近播放',
      canRecent: canRecent,
    );

void main() {
  test('a plugin page titled "Recently played" is the one recent entry', () {
    final e = build([
      NavItem(title: '', builtin: 'home'),
      NavItem(title: 'Recently played', page: 'recent', icon: 'star'),
    ], canRecent: true, tr: {'Recently played': '最近播放'});
    expect(e.where((x) => x.isRecent).length, 1);
    final r = e.firstWhere((x) => x.isRecent);
    expect(r.key, 'nav:1');
    expect(r.recentPage, 'recent');
    expect(r.icon, 'history');
  });

  test('without one, the app adds its own, using recent() when exported', () {
    final e = build([NavItem(title: '', builtin: 'home')], canRecent: true);
    expect(e.last.key, 'recent');
    expect(e.last.recentPage, '');
    final local = build([NavItem(title: '', builtin: 'home')]);
    expect(local.last.recentPage, isNull);
    expect(local.last.isRecent, isTrue);
  });

  test('builtins get their icons; shows hidden without the export', () {
    final e = build([NavItem(title: '', builtin: 'liked'), NavItem(title: '', builtin: 'shows'), NavItem(title: 'Charts', page: 'charts', icon: 'chart')]);
    expect(e.map((x) => x.icon), ['heart', 'chart', 'history']);
    expect(e.first.title, 'liked');
    expect(e[1].title, 'Charts');
  });
}
