import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'package:settlo_test_support/golden.dart';

void main() {
  for (final device in SettloGoldenDevices.all) {
    for (final (name, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      testWidgets('${device.name} $name sample golden', (tester) async {
        await pumpSettloGolden(
          tester,
          device: device,
          theme: theme,
          child: const _GoldenSample(),
        );

        await expectLater(
          find.byKey(settloGoldenSurfaceKey),
          matchesGoldenFile('goldens/golden_harness_${device.name}_$name.png'),
        );
      });
    }
  }
}

class _GoldenSample extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(SettloSpacing.screenMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shared balance',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: SettloSpacing.x2),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(SettloSpacing.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOU ARE OWED',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: SettloSpacing.x1),
                  const MoneyText(Paise.rupees(674200), size: 40, signed: true),
                  const SizedBox(height: SettloSpacing.x1),
                  Text(
                    'Across Flat 402 and Goa trip',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
