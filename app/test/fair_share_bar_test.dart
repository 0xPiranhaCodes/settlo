import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/settlo_spaces.dart';

import 'support/fake_space_ledger.dart';

/// The bar is 300 wide: what [flatLedger] says [member] paid, against
/// their fair share of the month's ₹18,450.
Future<void> _pump(WidgetTester tester, String member, ThemeData theme) {
  final f = flatLedger.fairness[member]!;
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: FairShareBar(
              name: member,
              paid: f.paid,
              fairShare: f.fairShare,
              monthTotal: const Paise.rupees(18450),
            ),
          ),
        ),
      ),
    ),
  );
}

Color _colour(WidgetTester tester, Key key) =>
    ((tester.widget<Positioned>(find.byKey(key)).child as DecoratedBox)
                .decoration
            as BoxDecoration)
        .color!;

void main() {
  double left(WidgetTester t) => t.getTopLeft(find.byType(FairShareBar)).dx;

  for (final (member, paid) in [('m1', 9000), ('m2', 5400), ('m3', 4050)]) {
    testWidgets('$member: the bar is what they paid, the tick their share', (
      tester,
    ) async {
      await _pump(tester, member, SettloTheme.dark());

      final bar = tester.getRect(find.byKey(FairShareBar.paidKey));
      final tick = tester.getRect(find.byKey(FairShareBar.tickKey));
      expect(bar.width, closeTo(300 * paid / 18450, 0.01));
      // ₹6,150 of ₹18,450 is a third.
      expect(tick.center.dx - left(tester), closeTo(100, 0.01));
      expect(tick.size, const Size(2, 16), reason: 'it stands proud');
      expect(tick.top, bar.top - 4);
    });
  }

  for (final (name, theme, colours) in [
    ('dark', SettloTheme.dark(), SettloColors.dark),
    ('light', SettloTheme.light(), SettloColors.light),
  ]) {
    testWidgets('the tick is primary text in $name, never gold', (
      tester,
    ) async {
      await _pump(tester, 'm1', theme);

      final tick = _colour(tester, FairShareBar.tickKey);
      expect(tick, colours.textPrimary);
      expect(tick, isNot(SettloColors.dark.action));
    });
  }

  testWidgets('it reads paid against fair share in rupees', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, 'm2', SettloTheme.dark());

    expect(
      find.bySemanticsLabel(
        'm2 paid five thousand four hundred rupees, fair share six thousand '
        'one hundred fifty rupees, seven hundred fifty rupees less than '
        'their share',
      ),
      findsOne,
    );
    semantics.dispose();
  });
}
