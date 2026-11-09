import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  test('path builders fill their patterns', () {
    expect(SettloRoutes.join('t'), '/join/t');
    expect(SettloRoutes.space('s'), '/spaces/s');
    expect(SettloRoutes.spaceBalances('s'), '/spaces/s/balances');
    expect(SettloRoutes.confirmRepayment('r'), '/loans/repayments/r');
    for (final (pattern, path) in [
      (SettloRoutes.joinPattern, SettloRoutes.join(':token')),
      (SettloRoutes.spacePattern, SettloRoutes.space(':spaceId')),
      (
        SettloRoutes.spaceBalancesPattern,
        SettloRoutes.spaceBalances(':spaceId'),
      ),
      (
        SettloRoutes.confirmRepaymentPattern,
        SettloRoutes.confirmRepayment(':repaymentId'),
      ),
    ]) {
      expect(path, pattern);
    }
  });
}
