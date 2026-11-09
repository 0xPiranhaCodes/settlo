import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_loans.dart';

/// The Loans tab and its routes at 360x800, at [location].
Future<({GoRouter router, FakeLoansRepository loans})> _pump(
  WidgetTester tester, {
  String location = SettloRoutes.loans,
  FakeLoansRepository? loans,
}) async {
  await loadSettloFonts();
  tester.view
    ..physicalSize = SettloGoldenDevices.compact360.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = loans ?? FakeLoansRepository(loansList());
  final router = GoRouter(
    initialLocation: location,
    routes: [...loansRoutes, loansTabRoute],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [loansRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        theme: SettloTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, loans: repo);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// List items merge their semantics, so labels are matched within.
Finder _said(String label) =>
    find.bySemanticsLabel(RegExp(RegExp.escape(label)));

void main() {
  group('ring geometry', () {
    test("the canvas ring: r 51 in a 112 box, from twelve o'clock", () {
      final g = const LoanRingPainter(
        0.325,
        track: Color(0xFF262A30),
        arc: Color(0xFFF3F2EE),
      ).geometry(const Size.square(112));

      expect(g.rect, Rect.fromCircle(center: const Offset(56, 56), radius: 51));
      expect(g.start, -math.pi / 2);
      // The canvas draws it as stroke-dasharray 104.1 of 320.4.
      expect(g.sweep * 51, closeTo(104.1, 0.1));
      expect(2 * math.pi * 51, closeTo(320.4, 0.1));
    });

    for (final (progress, sweep) in [
      (0.0, 0.0),
      (0.5, math.pi),
      (1.0, 2 * math.pi),
      (1.4, 2 * math.pi),
      (-0.2, 0.0),
    ]) {
      test('$progress sweeps $sweep', () {
        final g = LoanRingPainter(
          progress,
          track: const Color(0xFF000000),
          arc: const Color(0xFFFFFFFF),
        ).geometry(const Size(200, 112));
        expect(g.sweep, closeTo(sweep, 1e-9));
        // A wider box keeps the ring round and centred.
        expect((g.rect.center, g.rect.width), (const Offset(100, 56), 102));
      });
    }

    test('the label rounds down, so 100% means fully repaid', () {
      expect(const LoanRing(0.325).percent, 32);
      expect(const LoanRing(0.999).percent, 99);
      expect(const LoanRing(1).percent, 100);
    });
  });

  group('Loans tab', () {
    testWidgets('lists loans open first, each from your side', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      expect(find.text('Arjun · interest free'), findsOne);
      expect(find.text('13 of 40 · next 5 Dec'), findsOne);
      expect(find.text('you borrowed · flexible'), findsOne);
      expect(find.text('you borrowed · repaid'), findsOne);
      expect(find.text('1 repayment to confirm'), findsOne);
      expect(_said('six lakh seventy-five thousand rupees'), findsOne);
      semantics.dispose();
    });

    testWidgets('a loan opens its detail', (tester) async {
      final (:router, loans: _) = await _pump(tester);
      await _tap(tester, find.text('Arjun · interest free'));
      expect(router.state.uri.toString(), SettloRoutes.loan('l1'));
      expect(find.byType(LoanDetailScreen), findsOne);
    });

    testWidgets('with no loans it offers to record one', (tester) async {
      final (:router, loans: _) = await _pump(
        tester,
        loans: FakeLoansRepository(LoansData(today: DateTime(2026, 11, 9))),
      );
      expect(find.text('No loans yet'), findsOne);
      await _tap(tester, find.text('Record a loan'));
      expect(router.state.uri.toString(), SettloRoutes.newLoan);
    });

    testWidgets('a failed load says so', (tester) async {
      await _pump(
        tester,
        loans: FakeLoansRepository(loansList())..failLoad = true,
      );
      expect(find.textContaining("couldn't load your loans"), findsOne);
    });
  });

  group('Loan detail', () {
    testWidgets('ring, three tiles and the history', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, location: SettloRoutes.loan('l1'));

      expect(_said('32 percent repaid'), findsOne);
      expect(find.text(' · since Mar 2026'), findsOne);
      for (final text in [
        'monthly · 5th',
        '5 Dec',
        'in 26 days',
        'On track',
        'ends Jul 2029',
        'UPI · confirmed by you',
        'Cash · confirmed by you',
        'awaiting you',
      ]) {
        expect(find.text(text), findsOne, reason: text);
      }
      expect(
        _said('Instalment, twenty-five thousand rupees, monthly · 5th'),
        findsOne,
      );
      expect(_said('of ten lakh rupees · interest free'), findsOne);
      semantics.dispose();
    });

    testWidgets('record → pending → confirm: only confirmed counts', (
      tester,
    ) async {
      final (router: _, :loans) = await _pump(
        tester,
        location: SettloRoutes.loan('l1'),
      );

      await _tap(tester, find.text('Record repayment'));
      expect(find.text('Record repayment · Arjun'), findsOne);
      expect(find.text('ARJUN PAID YOU'), findsOne);
      // The amount comes first, prefilled with the instalment.
      expect(find.widgetWithText(TextField, '25,000'), findsOne);
      await tester.enterText(find.byType(TextField), '10000');
      await _tap(tester, find.text('Cash'));
      await _tap(tester, find.text('Record repayment').last);

      // Recorded by you, so it waits for Arjun and offers you nothing.
      expect(find.text('Record repayment · Arjun'), findsNothing);
      expect(find.text('awaiting Arjun'), findsOne);
      expect(find.text('Confirm received'), findsOne);
      expect(find.byType(LoanRing), findsOne);
      expect(tester.widget<LoanRing>(find.byType(LoanRing)).percent, 32);

      // Arjun's 5 Oct repayment waits for you: confirming it counts.
      await _tap(tester, find.text('Confirm received'));
      expect(tester.widget<LoanRing>(find.byType(LoanRing)).percent, 35);
      expect(find.text('awaiting you'), findsNothing);
      expect(find.text('UPI · confirmed by you'), findsNWidgets(2));
      expect(loans.calls.map((c) => c.split(' ').first), [
        'record_repayment',
        'confirm_repayment',
      ]);
    });

    testWidgets('a retried confirmation reuses its key and shows plain copy', (
      tester,
    ) async {
      final repo = FakeLoansRepository(loansList())
        ..error = const LoanRejected(LoanRejection.notPending);
      await _pump(tester, location: SettloRoutes.loan('l1'), loans: repo);

      await _tap(tester, find.text('Confirm received'));
      expect(
        find.text('This repayment was already answered. Pull down to see it.'),
        findsOne,
      );
      await _tap(tester, find.text('Confirm received'));
      expect(repo.calls, hasLength(2));
      expect(repo.calls.first, repo.calls.last);
      expect(find.text('awaiting you'), findsNothing);
    });

    testWidgets('dispute asks for a reason and never counts', (tester) async {
      final (router: _, :loans) = await _pump(
        tester,
        location: SettloRoutes.loan('l1'),
      );

      await _tap(tester, find.text("Didn't get it"));
      expect(find.text("Didn't get ₹25,000 from Arjun?"), findsOne);
      final send = find.widgetWithText(FilledButton, 'Mark as not received');
      expect(tester.widget<FilledButton>(send).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '  Not received yet ');
      await tester.pump();
      await _tap(tester, send);

      expect(find.text('UPI · disputed by you'), findsOne);
      expect(find.text('“Not received yet”'), findsOne);
      expect(find.text('Confirm received'), findsNothing);
      expect(tester.widget<LoanRing>(find.byType(LoanRing)).percent, 32);
      expect(loans.calls.single, endsWith(' Not received yet'));
    });

    testWidgets('more than is outstanding cannot be recorded', (tester) async {
      await _pump(tester, location: SettloRoutes.loan('l1'));
      await _tap(tester, find.text('Record repayment'));
      await tester.enterText(find.byType(TextField), '675001');
      await tester.pump();

      expect(find.text("That's more than is left on the loan."), findsOne);
      final record = find.widgetWithText(FilledButton, 'Record repayment').last;
      expect(tester.widget<FilledButton>(record).onPressed, isNull);
    });

    testWidgets('a refused repayment shows the plain reason', (tester) async {
      final repo = FakeLoansRepository(loansList())
        ..error = const LoanRejected(LoanRejection.overpayment);
      await _pump(tester, location: SettloRoutes.loan('l1'), loans: repo);
      await _tap(tester, find.text('Record repayment'));
      await _tap(tester, find.text('Record repayment').last);

      expect(
        find.text("That's more than is left on the loan. Check the amount."),
        findsOne,
      );
      expect(find.text('Record repayment · Arjun'), findsOne);
    });

    testWidgets('a closed loan cannot take more repayments', (tester) async {
      await _pump(tester, location: SettloRoutes.loan('l3'));
      expect(tester.widget<LoanRing>(find.byType(LoanRing)).percent, 100);
      expect(find.text('Repaid'), findsOne);
      expect(find.text('Record repayment'), findsNothing);
    });

    testWidgets('back returns to the list', (tester) async {
      final (:router, loans: _) = await _pump(
        tester,
        location: SettloRoutes.loan('l1'),
      );
      await _tap(tester, find.byTooltip('Back'));
      expect(router.state.uri.toString(), SettloRoutes.loans);
    });
  });

  group('a double tap in one frame sends once', () {
    // Two taps with no pump between while the first write is in flight:
    // the button is still enabled for the second, as it would be for a
    // fast double tap.
    Future<void> twice(
      WidgetTester tester,
      FakeLoansRepository loans,
      Finder finder,
    ) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final hold = loans.hold = Completer<void>();
      await tester.tap(finder);
      await tester.tap(finder);
      hold.complete();
      await tester.pumpAndSettle();
    }

    testWidgets('record', (tester) async {
      final (router: _, :loans) = await _pump(
        tester,
        location: SettloRoutes.loan('l1'),
      );
      await _tap(tester, find.text('Record repayment'));
      await twice(
        tester,
        loans,
        find.widgetWithText(FilledButton, 'Record repayment').last,
      );
      expect(loans.calls, [startsWith('record_repayment ')]);
    });

    testWidgets('confirm', (tester) async {
      final (router: _, :loans) = await _pump(
        tester,
        location: SettloRoutes.loan('l1'),
      );
      await twice(tester, loans, find.text('Confirm received'));
      expect(loans.calls, [startsWith('confirm_repayment ')]);
    });

    testWidgets('dispute', (tester) async {
      final (router: _, :loans) = await _pump(
        tester,
        location: SettloRoutes.loan('l1'),
      );
      await _tap(tester, find.text("Didn't get it"));
      await tester.enterText(find.byType(TextField), 'Not received yet');
      await tester.pump();
      await twice(
        tester,
        loans,
        find.widgetWithText(FilledButton, 'Mark as not received'),
      );
      expect(loans.calls, [startsWith('dispute_repayment ')]);
    });
  });

  group('targets are at least 44pt', () {
    for (final (name, location) in [
      ('Loans tab', SettloRoutes.loans),
      ('Loan detail', SettloRoutes.loan('l1')),
    ]) {
      testWidgets(name, (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, location: location);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await tester.drag(find.byType(ListView), const Offset(0, -800));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        semantics.dispose();
      });
    }

    testWidgets('record repayment sheet', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, location: SettloRoutes.loan('l1'));
      await _tap(tester, find.text('Record repayment'));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      semantics.dispose();
    });
  });
}
