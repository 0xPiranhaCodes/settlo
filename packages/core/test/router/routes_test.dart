import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  test('path builders fill their patterns', () {
    expect(SettloRoutes.join('t'), '/join/t');
    expect(SettloRoutes.space('s'), '/spaces/s');
    expect(SettloRoutes.spaceActivity('s'), '/spaces/s/activity');
    expect(SettloRoutes.spaceBalances('s'), '/spaces/s/balances');
    expect(SettloRoutes.confirmRepayment('r'), '/loans/repayments/r');
    expect(SettloRoutes.confirmSettlement('s', 'e'), '/spaces/s/settle-ups/e');
    expect(SettloRoutes.addExpenseIn('s 1'), '/expenses/new?space=s+1');
    expect(SettloRoutes.settleWith('s'), '/settle?space=s');
    expect(
      SettloRoutes.settleWith('s', memberId: 'm&1'),
      '/settle?space=s&member=m%261',
    );
    expect(SettloRoutes.settlePayTo('s', 'm'), '/settle/pay?space=s&member=m');
    for (final (pattern, path) in [
      (SettloRoutes.joinPattern, SettloRoutes.join(':token')),
      (SettloRoutes.spacePattern, SettloRoutes.space(':spaceId')),
      (
        SettloRoutes.spaceActivityPattern,
        SettloRoutes.spaceActivity(':spaceId'),
      ),
      (
        SettloRoutes.spaceBalancesPattern,
        SettloRoutes.spaceBalances(':spaceId'),
      ),
      (
        SettloRoutes.confirmSettlementPattern,
        SettloRoutes.confirmSettlement(':spaceId', ':expenseId'),
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
