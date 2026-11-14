import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final reduced in [false, true]) {
      testWidgets('$platform reduced=$reduced task navigation retains sheet', (
        tester,
      ) async {
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () => pushSettloTask<void>(context, '/sheet'),
                  child: const Text('Open'),
                ),
              ),
            ),
            GoRoute(
              path: '/sheet',
              pageBuilder: (_, _) => SettloRootSheetPage<void>(
                child: Builder(
                  builder: (context) => SSheetScaffold(
                    title: 'Root',
                    onClose: () => popSettloTask(context, fallback: '/'),
                    children: [
                      TextButton(
                        onPressed: () => pushSettloTask<void>(context, '/step'),
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/step',
              pageBuilder: (_, _) => SettloRootSheetPage<void>(
                child: Builder(
                  builder: (context) => SSheetScaffold(
                    title: 'Step',
                    onClose: () => popSettloTask(context, fallback: '/'),
                    children: [
                      TextButton(
                        onPressed: () => finishSettloSheet(context, 'saved'),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            theme: SettloTheme.light().copyWith(platform: platform),
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final rootContext = tester.element(find.text('Next'));
        final sheet = SettloSheetScope.maybeOf(rootContext)!;
        expect(sheet.isCurrent(), isTrue);
        final navigator = Navigator.of(rootContext);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/sheet');
        expect(
          Navigator.of(tester.element(find.text('Save'))),
          same(navigator),
        );
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Next'), findsOneWidget);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Next'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsOneWidget);
        // Direct links have no parent route to pop: return to the tab fallback.
        router.go('/step');
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
