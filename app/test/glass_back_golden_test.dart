import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

void main() {
  for (final device in SettloGoldenDevices.accessible) {
    for (final dark in [false, true]) {
      testWidgets('${device.name} glass back ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        await pumpSettloGolden(
          tester,
          device: device,
          theme: (dark ? SettloTheme.dark() : SettloTheme.light()).copyWith(
            platform: TargetPlatform.iOS,
          ),
          child: Navigator(
            onGenerateInitialRoutes: (_, _) => [
              CupertinoPageRoute<void>(
                title: 'Spaces',
                builder: (_) => const Scaffold(body: Text('Spaces')),
              ),
              CupertinoPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: SettloScrollScaffold(
                    title: 'Flat 402',
                    largeTitle: 'Flat 402',
                    previousPageTitle: 'Spaces',
                    children: [
                      SizedBox(),
                      SCard(child: Text('Shared pushed-screen header')),
                    ],
                  ),
                ),
              ),
            ],
            onGenerateRoute: (_) => null,
          ),
        );
        await expectLater(
          find.byKey(settloGoldenSurfaceKey),
          matchesGoldenFile(
            'goldens/glass_back_${device.name}_${dark ? 'dark' : 'light'}.png',
          ),
        );
      });
    }
  }
}
