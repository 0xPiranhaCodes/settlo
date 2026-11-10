import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  testWidgets(
    'large-text rupee stays subordinate and the complete amount fits',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 320,
                child: MoneyText(Paise.rupees(1000000), size: 52),
              ),
            ),
          ),
        ),
      );
      final amount = tester.getRect(find.byType(MoneyText));
      final symbol = tester.getRect(find.text('₹'));
      expect(symbol.height, lessThan(amount.height * 0.8));
      expect(symbol.top, greaterThanOrEqualTo(amount.top));
      expect(amount.width, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );
}
