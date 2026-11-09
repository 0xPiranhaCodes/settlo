import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  test('toE164 adds +91 to a bare Indian mobile and rejects the rest', () {
    expect(toE164('98200 11223'), '+919820011223');
    expect(toE164('098200-11223'), '+919820011223');
    expect(toE164('+44 (20) 7946 0958'), '+442079460958');
    for (final bad in ['', '12345', '58200 11223', 'abc']) {
      expect(toE164(bad), isNull, reason: bad);
    }
  });

  test('groupPhone groups Indian mobiles only', () {
    expect(groupPhone('+919820011223'), '+91 98200 11223');
    expect(groupPhone('+442079460958'), '+442079460958');
  });
}
