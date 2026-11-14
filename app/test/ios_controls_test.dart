import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';
import 'support/fake_expenses.dart';
import 'support/fake_loans.dart';
import 'support/fake_session.dart';
import 'support/fake_space_ledger.dart';
import 'support/fake_spaces.dart';

const TargetPlatform _ios = TargetPlatform.iOS;
const TargetPlatform _android = TargetPlatform.android;

/// The production routes at [location] on [platform], over a stand-in Home.
Future<GoRouter> _pump(
  WidgetTester tester,
  String location,
  TargetPlatform platform,
) async {
  await loadSettloFonts();
  tester.view
    ..physicalSize = SettloGoldenDevices.canvas390.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: SettloRoutes.home,
    routes: [
      GoRoute(path: SettloRoutes.home, builder: (_, _) => const Text('Home')),
      spacesTabRoute,
      activityTabRoute,
      ...expensesRoutes,
      ...loansRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => FakeSessionNotifier(fakeSession)),
        spacesRepositoryProvider.overrideWithValue(
          FakeSpacesRepository(spacesList),
        ),
        spaceLedgerRepositoryProvider.overrideWithValue(
          FakeSpaceLedgerRepository(),
        ),
        expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
        loansRepositoryProvider.overrideWithValue(
          FakeLoansRepository(loansList()),
        ),
        activityRepositoryProvider.overrideWithValue(FakeActivityRepository()),
        activityNowProvider.overrideWithValue(DateTime(2026, 11, 9, 18)),
      ],
      child: MaterialApp.router(
        theme: SettloTheme.dark().copyWith(platform: platform),
        routerConfig: router,
      ),
    ),
  );
  unawaited(router.push(location));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _pressable(String label) => find.byWidgetPredicate(
  (w) => w is SPressable && (w.label?.startsWith(label) ?? false),
);

void main() {
  group('Spaces list', () {
    testWidgets('iOS: search filters the spaces by name', (tester) async {
      await _pump(tester, SettloRoutes.spaces, _ios);
      expect(find.text('Flat 402'), findsOneWidget);
      expect(find.text('Goa trip'), findsOneWidget);

      await tester.enterText(find.byType(CupertinoSearchTextField), 'goa');
      await tester.pumpAndSettle();
      expect(find.text('Flat 402'), findsNothing);
      expect(find.text('Goa trip'), findsOneWidget);

      await tester.enterText(find.byType(CupertinoSearchTextField), 'paris');
      await tester.pumpAndSettle();
      expect(find.text('No space matches "paris".'), findsOneWidget);
    });

    testWidgets('Android: no search, and the circled + stays', (tester) async {
      await _pump(tester, SettloRoutes.spaces, _android);
      expect(find.byType(CupertinoSearchTextField), findsNothing);
      expect(find.byTooltip('New space'), findsOneWidget);
    });

    testWidgets('iOS: Create space is a page sheet with ✕ and Create space', (
      tester,
    ) async {
      await _pump(tester, SettloRoutes.spaces, _ios);
      await _tap(tester, find.bySemanticsLabel('New space'));

      expect(
        ModalRoute.of(tester.element(find.text('New space').last)),
        isA<CupertinoSheetRoute<void>>(),
      );
      // The task-sheet layout (#260): grabber, ✕, one bottom button.
      expect(find.text('Cancel'), findsNothing);
      expect(find.byKey(const ValueKey('task-sheet-grabber')), findsOneWidget);
      final create = find.widgetWithText(FilledButton, 'Create space');
      expect(tester.widget<FilledButton>(create).onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, 'Book club');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
      expect(
        find.byType(CupertinoSlidingSegmentedControl<SpaceKind>),
        findsOneWidget,
      );

      // ✕ with input asks first; Keep editing stays.
      await _tap(tester, find.bySemanticsLabel('Close'));
      expect(find.text('Discard changes?'), findsOneWidget);
      await _tap(tester, find.text('Keep editing'));
      expect(find.text('Book club'), findsOneWidget);

      // A drag down asks too; Discard closes.
      await tester.fling(find.text('PEOPLE'), const Offset(0, 600), 2000);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await _tap(tester, find.text('Discard'));
      expect(find.text('Book club'), findsNothing);
      expect(find.byType(CupertinoSearchTextField), findsOneWidget);
    });

    testWidgets('iOS: VoiceOver can activate New space', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, SettloRoutes.spaces, _ios);
      tester.semantics.tap(find.semantics.byLabel('New space'));
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(tester.element(find.text('New space').last)),
        isA<CupertinoSheetRoute<void>>(),
      );
      semantics.dispose();
    });

    testWidgets('iOS: an untouched Create space closes on ✕', (
      tester,
    ) async {
      await _pump(tester, SettloRoutes.spaces, _ios);
      await _tap(tester, find.bySemanticsLabel('New space'));
      await _tap(tester, find.bySemanticsLabel('Close'));
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('PEOPLE'), findsNothing);
    });

    testWidgets('Android: Create space keeps its Material sheet', (
      tester,
    ) async {
      await _pump(tester, SettloRoutes.spaces, _android);
      await _tap(tester, find.byTooltip('New space'));
      expect(find.text('Create space'), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsNothing);
      expect(
        ModalRoute.of(tester.element(find.text('Create space'))),
        isA<ModalBottomSheetRoute<void>>(),
      );
    });
  });

  group('Activity', () {
    testWidgets('iOS: search filters the feed', (tester) async {
      await _pump(tester, SettloRoutes.activity, _ios);
      expect(find.textContaining('Electricity'), findsWidgets);
      expect(find.textContaining('Groceries'), findsWidgets);

      await tester.enterText(
        find.byType(CupertinoSearchTextField),
        'groceries',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Electricity'), findsNothing);
      expect(find.textContaining('Groceries'), findsWidgets);

      await tester.enterText(find.byType(CupertinoSearchTextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No activity matches "zzz".'), findsOneWidget);
    });

    testWidgets('iOS: day headings are pinned slivers', (tester) async {
      await _pump(tester, SettloRoutes.activity, _ios);
      for (final heading in ['Today', 'This week']) {
        expect(
          find.ancestor(
            of: find.text(heading),
            matching: find.byType(PinnedHeaderSliver),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('Android: no search field or pinned headings', (tester) async {
      await _pump(tester, SettloRoutes.activity, _android);
      expect(find.byType(CupertinoSearchTextField), findsNothing);
      expect(find.byType(PinnedHeaderSliver), findsNothing);
    });
  });

  group('Add expense', () {
    final location = SettloRoutes.addExpenseIn('s1');

    testWidgets('iOS: split rows use a trailing checkmark', (tester) async {
      await _pump(tester, location, _ios);
      expect(find.byType(Checkbox), findsNothing);
      final checks = find.byIcon(CupertinoIcons.checkmark_alt);
      final before = checks.evaluate().length;
      expect(before, greaterThan(0));

      await _tap(tester, checks.first);
      expect(checks.evaluate().length, before - 1);
      expect(
        find.byType(CupertinoSlidingSegmentedControl<SplitType>),
        findsOneWidget,
      );
    });

    testWidgets('iOS: VoiceOver can toggle a split row and open the date', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, location, _ios);
      final checks = find.byIcon(CupertinoIcons.checkmark_alt);
      final before = checks.evaluate().length;
      final row = find.semantics.byPredicate(
        (n) => n.flagsCollection.isChecked == CheckedState.isTrue,
      );
      tester.semantics.tap(row.first);
      await tester.pumpAndSettle();
      expect(checks.evaluate().length, before - 1);

      tester.semantics.tap(find.semantics.byLabel(RegExp('Today')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('iOS: the date opens a Cupertino wheel', (tester) async {
      await _pump(tester, location, _ios);
      await _tap(tester, find.text('Today'));
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);
    });

    testWidgets('Android: checkboxes and the Material calendar stay', (
      tester,
    ) async {
      await _pump(tester, location, _android);
      expect(find.byType(Checkbox), findsWidgets);
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsNothing);
      expect(
        find.byType(CupertinoSlidingSegmentedControl<SplitType>),
        findsNothing,
      );
      await _tap(tester, find.text('Today'));
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });

  group('New loan', () {
    testWidgets('iOS: segmented direction, switch, wheel pickers', (
      tester,
    ) async {
      await _pump(tester, SettloRoutes.newLoan, _ios);
      expect(
        find.byType(CupertinoSlidingSegmentedControl<bool>),
        findsOneWidget,
      );
      await _tap(tester, find.text('I borrowed'));
      expect(find.text('FROM'), findsOneWidget);

      final toggle = tester.widget<CupertinoSwitch>(
        find.byType(CupertinoSwitch),
      );
      expect(toggle.activeTrackColor, SettloColors.dark.action);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);

      // Due day needs a monthly amount first.
      await tester.enterText(find.byType(TextField).first, '10000');
      await tester.enterText(find.byType(TextField).at(3), '1000');
      await tester.pumpAndSettle();
      await _tap(tester, _pressable('Due day'));
      expect(find.byType(CupertinoPicker), findsOneWidget);
      await tester.drag(find.byType(CupertinoPicker), const Offset(0, -50));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Done'));
      expect(find.byType(CupertinoPicker), findsNothing);

      await _tap(tester, _pressable('Starts'));
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
    });

    testWidgets('iOS: VoiceOver can pick a direction and open both wheels', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, SettloRoutes.newLoan, _ios);
      tester.semantics.tap(find.semantics.byLabel('I borrowed'));
      await tester.pumpAndSettle();
      expect(find.text('FROM'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '10000');
      await tester.enterText(find.byType(TextField).at(3), '1000');
      await tester.pumpAndSettle();
      await tester.ensureVisible(_pressable('Due day'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel(RegExp('Due day')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoPicker), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('Done'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(_pressable('Starts'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel(RegExp('Starts')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('Android: Material switch and dropdown stay', (tester) async {
      await _pump(tester, SettloRoutes.newLoan, _android);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsNothing);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      expect(find.byType(CupertinoSlidingSegmentedControl<bool>), findsNothing);
    });
  });
}
