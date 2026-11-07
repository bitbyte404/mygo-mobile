import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mygo_mobile/app/system_insets.dart';

void main() {
  test('web insets fold into view padding, the keyboard taking the bottom', () {
    const mq = MediaQueryData(size: Size(390, 844), viewPadding: EdgeInsets.only(top: 20));
    final m = SystemInsets.apply(mq, const EdgeInsets.fromLTRB(0, 59, 0, 34));
    expect(m.viewPadding, const EdgeInsets.fromLTRB(0, 59, 0, 34));
    expect(m.padding, const EdgeInsets.fromLTRB(0, 59, 0, 34));
    final kb = SystemInsets.apply(mq.copyWith(viewInsets: const EdgeInsets.only(bottom: 300)), const EdgeInsets.fromLTRB(0, 59, 0, 34));
    expect(kb.padding.bottom, 0);
    expect(identical(SystemInsets.apply(mq, EdgeInsets.zero), mq), isTrue);
  });
}
