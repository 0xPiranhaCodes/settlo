import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_home.dart';
import 'support/fake_loans.dart';
import 'support/fake_session.dart';

/// Links opened, such as WhatsApp's; reset by [_pump].
final _opened = <Uri>[];

/// Whether opening a link works; reset by [_pump].
var _canOpen = true;

/// The Loan artboard's start: ₹10 lakh at ₹25,000 from March ends Jul 2029.
final _today = DateTime(2026, 3, 5);

/// Files handed to the share sheet, with their bytes; reset by [_pump].
final _shared = <List<(SharedFile, List<int>)>>[];

/// Completes when the share sheet opens; set by a test.
Completer<void>? _sharing;

/// While set, the share sheet stays open until it completes.
Completer<void>? _sheetOpen;

Future<void> _share(List<SharedFile> files, Rect origin) async {
  _shared.add([for (final f in files) (f, File(f.path).readAsBytesSync())]);
  _sharing?.complete();
  await _sheetOpen?.future;
}

Future<bool> _open(Uri uri) async {
  _opened.add(uri);
  return _canOpen;
}

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
  final temp = Directory.systemTemp.createTempSync('settlo');
  addTearDown(() => temp.deleteSync(recursive: true));
  final exports = Directory('${temp.path}/exports');
  _opened.clear();
  _shared.clear();
  _canOpen = true;
  final router = GoRouter(
    initialLocation: location,
    routes: [...loansRoutes, loansTabRoute],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        loansRepositoryProvider.overrideWithValue(repo),
        invitesRepositoryProvider.overrideWithValue(FakeInvitesRepository()),
        sessionProvider.overrideWith(() => FakeSessionNotifier(fakeSession)),
        indiaTodayProvider.overrideWithValue(_today),
        openUrlProvider.overrideWithValue(_open),
        shareFilesProvider.overrideWithValue(_share),
        exportsDirectoryProvider.overrideWithValue(() async => exports),
      ],
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
  test('India date crosses midnight independently of a UTC-8 device', () {
    final justAfterIstMidnight = DateTime.parse('2026-11-09T10:45:00-08:00');

    expect(indiaDate(justAfterIstMidnight), DateTime(2026, 11, 10));
  });

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
      expect(find.text('PAID ON'), findsOne);
      expect(find.text('Today'), findsOne);
      expect(find.text('REFERENCE · OPTIONAL'), findsOne);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'UPI or bank reference'),
            )
            .maxLength,
        64,
      );
      await tester.enterText(
        find.bySemanticsLabel('Amount in rupees'),
        '10000',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'UPI or bank reference'),
        'UPI 1234',
      );
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
      expect(loans.data.loans.first.repayments.first.reference, 'UPI 1234');
    });

    testWidgets('paid-on picker is bounded by loan start and today', (
      tester,
    ) async {
      await _pump(tester, location: SettloRoutes.loan('l1'));
      await _tap(tester, find.text('Record repayment'));
      await _tap(tester, find.text('Today'));

      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(calendar.firstDate, DateTime(2026, 3, 5));
      expect(calendar.lastDate, _today);
    });

    testWidgets('reference trims Unicode whitespace and filters Cc/Cf', (
      tester,
    ) async {
      final (router: _, :loans) = await _pump(
        tester,
        location: SettloRoutes.loan('l1'),
      );
      await _tap(tester, find.text('Record repayment'));
      final reference = find.widgetWithText(TextField, 'UPI or bank reference');

      await tester.enterText(
        reference,
        '\u00A0UPI\u200B\u202E\uFEFF\u0007 123\u2003',
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(reference).controller!.text,
        '\u00A0UPI 123\u2003',
      );

      await _tap(tester, find.text('Record repayment').last);
      expect(loans.data.loans.first.repayments.first.reference, 'UPI 123');
    });

    testWidgets('reference limit counts Unicode code points', (tester) async {
      await _pump(tester, location: SettloRoutes.loan('l1'));
      await _tap(tester, find.text('Record repayment'));
      final reference = find.widgetWithText(TextField, 'UPI or bank reference');
      final sixtyFourRupees = List.filled(64, '₹').join();

      await tester.enterText(reference, '\u00A0$sixtyFourRupees\u3000');
      await tester.pump();
      expect(
        tester.widget<TextField>(reference).controller!.text,
        '\u00A0$sixtyFourRupees\u3000',
      );

      final fortyCombinedGraphemes = List.filled(40, 'e\u0301').join();

      await tester.enterText(reference, fortyCombinedGraphemes);
      await tester.pump();

      final text = tester.widget<TextField>(reference).controller!.text;
      expect(text.runes, hasLength(64));
      expect(text, List.filled(32, 'e\u0301').join());
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
      await tester.enterText(
        find.bySemanticsLabel('Amount in rupees'),
        '675001',
      );
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

    testWidgets('download statement shares one PDF, even on a no-pump '
        'double tap', (tester) async {
      await _pump(tester, location: SettloRoutes.loan('l1'));
      final download = find.byTooltip('Download statement');
      expect(tester.getSize(download), const Size(44, 44));
      _sharing = Completer<void>();
      final sheet = _sheetOpen = Completer<void>();
      addTearDown(() => _sheetOpen = null);

      await tester.tap(download);
      await tester.tap(download);
      // Real file and isolate work, with pumps so its callbacks land.
      while (!_sharing!.isCompleted) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump();
      sheet.complete();
      await tester.pumpAndSettle();

      expect(_shared, hasLength(1));
      final [(file, bytes)] = _shared.single;
      expect(
        file.path,
        matches(
          RegExp(
            r'/exports/share-[^/]+/settlo-loan-statement-\d{4}-\d\d-\d\d\.pdf$',
          ),
        ),
      );
      expect(file.mimeType, 'application/pdf');
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('New loan', () {
    Finder field(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(TextField));

    /// The canvas loan: you lent Arjun Mehta ₹10 lakh at ₹25,000 a month.
    Future<void> fill(
      WidgetTester tester, {
      String installment = '25,000',
    }) async {
      await tester.enterText(find.byType(TextField).first, '10,00,000');
      await tester.enterText(field('Phone number'), '98200 11223');
      await tester.enterText(field('Their name'), 'Arjun Mehta');
      await _tap(tester, find.text('Add person'));
      await tester.enterText(find.byType(TextField).last, installment);
      await tester.pumpAndSettle();
    }

    Finder create() =>
        find.widgetWithText(FilledButton, 'Create loan and share');

    testWidgets('the + opens it; it creates the loan, tells them on '
        'WhatsApp and lands on it', (tester) async {
      final semantics = tester.ensureSemantics();
      final (:router, :loans) = await _pump(tester);
      await _tap(tester, find.byTooltip('New loan'));
      expect(find.byType(NewLoanSheet), findsOne);
      expect(tester.widget<FilledButton>(create()).onPressed, isNull);

      await fill(tester);
      expect(find.text('ten lakh rupees'), findsOne);
      expect(find.text('+91 98200 11223'), findsOne);
      expect(
        find.textContaining(
          'Arjun gets a WhatsApp message. Ends Jul 2029 at this pace.',
        ),
        findsOne,
      );
      expect(find.text('5th'), findsOne);
      expect(find.text('Mar 2026'), findsOne);

      await _tap(tester, create());
      final key = loans.calls.single.split(' ').last;
      expect(loans.calls.single, startsWith('create_loan '));
      expect(loans.created, (
        youLent: true,
        counterpartyPhone: '+919820011223',
        principal: const Paise.rupees(1000000),
        installment: const Paise.rupees(25000),
        dueDay: 5,
        startOn: _today,
      ));
      // No amount or terms before they verify.
      final whatsApp = _opened.single;
      expect((whatsApp.host, whatsApp.path), ('wa.me', '/919820011223'));
      expect(
        whatsApp.queryParameters['text'],
        'Hi, this is Sana. I recorded a loan between us on Settlo. You will '
        'see it in Settlo once you verify this number. '
        'settlo://join/loan-token',
      );
      expect(whatsApp.queryParameters['text'], isNot(contains('10,00,000')));
      expect(router.state.uri.toString(), SettloRoutes.loan(key));
      expect(find.byType(LoanDetailScreen), findsOne);

      router.go(SettloRoutes.loans);
      await tester.pumpAndSettle();
      expect(find.text('+919820011223 · interest free'), findsOne);
      expect(find.text('0 of 40 · next 5 Dec'), findsNothing);
      semantics.dispose();
    });

    // Whatever is typed as their name, the message is the same: nothing
    // typed about them can carry an amount or terms; only the server link is
    // added.
    testWidgets('the WhatsApp text never carries the label typed', (
      tester,
    ) async {
      final texts = <String?>[];
      for (final label in [
        'Arjun Mehta',
        '₹10,00,000',
        'https://example.com',
        '5% a month, due 5th',
        '',
      ]) {
        await _pump(tester, location: SettloRoutes.newLoan);
        await tester.enterText(find.byType(TextField).first, '10,00,000');
        await tester.enterText(field('Phone number'), '98200 11223');
        await tester.enterText(field('Their name'), label);
        await _tap(tester, find.text('Add person'));
        await _tap(tester, create());
        texts.add(_opened.single.queryParameters['text']);
      }
      expect(texts.toSet(), hasLength(1));
      expect(texts.first, startsWith('Hi, this is Sana. '));
      expect(texts.first, endsWith('settlo://join/loan-token'));
      expect(texts.first, isNot(contains('₹10,00,000')));
    });

    test('without a profile name the greeting is fixed', () {
      expect(
        loanInviteText(null, Uri.parse('settlo://join/t')),
        startsWith('Hi. I recorded a loan between us on Settlo.'),
      );
      expect(
        loanInviteText('  ', Uri.parse('settlo://join/t')),
        loanInviteText(null, Uri.parse('settlo://join/t')),
      );
    });

    testWidgets('borrowed with no monthly amount is flexible', (tester) async {
      final (router: _, :loans) = await _pump(
        tester,
        location: SettloRoutes.newLoan,
      );
      await _tap(tester, find.text('I borrowed'));
      await fill(tester, installment: '');
      expect(find.text('FROM'), findsOne);
      expect(find.textContaining('No monthly schedule'), findsOne);
      await _tap(tester, create());
      expect(
        (
          loans.created?.youLent,
          loans.created?.installment,
          loans.created?.dueDay,
        ),
        (false, null, null),
      );
    });

    testWidgets('a monthly amount over the principal cannot be saved', (
      tester,
    ) async {
      await _pump(tester, location: SettloRoutes.newLoan);
      await fill(tester, installment: '10,00,001');
      expect(find.textContaining('at most the principal'), findsOne);
      expect(tester.widget<FilledButton>(create()).onPressed, isNull);
    });

    testWidgets('your own number or a bad one is refused', (tester) async {
      await _pump(tester, location: SettloRoutes.newLoan);
      await tester.enterText(field('Phone number'), '12345');
      await _tap(tester, find.text('Add person'));
      expect(find.text('Enter a mobile number, like 98765 43210'), findsOne);
      await tester.enterText(field('Phone number'), '98765 43210');
      await _tap(tester, find.text('Add person'));
      expect(
        find.text("That's your number. A loan is with someone else."),
        findsOne,
      );
    });

    testWidgets('a retry after a dropped connection reuses the key', (
      tester,
    ) async {
      final repo = FakeLoansRepository(loansList())
        ..error = Exception('offline');
      final (:router, loans: _) = await _pump(
        tester,
        location: SettloRoutes.newLoan,
        loans: repo,
      );
      await fill(tester);
      await _tap(tester, create());
      expect(find.textContaining("won't be created twice"), findsOne);
      expect(_opened, isEmpty);
      await _tap(tester, create());
      expect(repo.calls, hasLength(2));
      expect(repo.calls.first, repo.calls.last);
      expect(router.state.uri.toString(), startsWith('/loans/'));
      expect(find.byType(LoanDetailScreen), findsOne);
    });

    testWidgets('a refusal shows plain copy and stays open', (tester) async {
      await _pump(
        tester,
        location: SettloRoutes.newLoan,
        loans: FakeLoansRepository(loansList())
          ..error = const LoanRejected(LoanRejection.invalid),
      );
      await fill(tester);
      await _tap(tester, create());
      expect(
        find.text("That didn't go through. Check it and try again."),
        findsOne,
      );
      expect(find.byType(NewLoanSheet), findsOne);
    });

    testWidgets('without WhatsApp it says so and still shows the loan', (
      tester,
    ) async {
      await _pump(tester, location: SettloRoutes.newLoan);
      _canOpen = false;
      await fill(tester);
      await _tap(tester, create());
      expect(find.text("Couldn't open WhatsApp"), findsOne);
      expect(find.byType(LoanDetailScreen), findsOne);
    });

    testWidgets('close goes back to Loans', (tester) async {
      final (:router, loans: _) = await _pump(
        tester,
        location: SettloRoutes.newLoan,
      );
      await _tap(tester, find.bySemanticsLabel('Close'));
      expect(router.state.uri.toString(), SettloRoutes.loans);
    });

    testWidgets('interest is off, with the later path shown', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, location: SettloRoutes.newLoan);
      await tester.scrollUntilVisible(
        find.byType(Switch),
        100,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect((toggle.value, toggle.onChanged), (false, null));
      expect(
        tester.getSemantics(find.byType(Switch)),
        matchesSemantics(
          label: 'Interest\nInterest free · add simple or reducing later',
          hasToggledState: true,
          hasEnabledState: true,
        ),
      );
      semantics.dispose();
    });

    test('ends in the month of the last instalment', () {
      const lakh = Paise.rupees(100000);
      expect(
        loanEndMonth(
          DateTime(2026, 3, 5),
          const Paise.rupees(1000000),
          const Paise.rupees(25000),
        ),
        DateTime(2029, 7),
      );
      // A part instalment still takes a month.
      expect(
        loanEndMonth(DateTime(2026, 11, 30), lakh, const Paise.rupees(30000)),
        DateTime(2027, 3),
      );
      expect(loanEndMonth(DateTime(2026, 12), lakh, lakh), DateTime(2027));
    });
  });

  testWidgets('Home opens New loan, and shows the loan once created', (
    tester,
  ) async {
    _opened.clear();
    await loadSettloFonts();
    tester.view
      ..physicalSize = SettloGoldenDevices.canvas390.size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loans = FakeLoansRepository(LoansData(today: _today));
    await tester.pumpWidget(
      fakeSessionApp(
        fakeSession,
        home: _HomeOverLoans(loans),
        loans: loans,
        overrides: [
          indiaTodayProvider.overrideWithValue(_today),
          openUrlProvider.overrideWithValue(_open),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Record a loan'));
    expect(find.byType(NewLoanSheet), findsOne);

    await tester.enterText(find.byType(TextField).first, '50,000');
    await tester.enterText(
      find.ancestor(
        of: find.text('Phone number'),
        matching: find.byType(TextField),
      ),
      '98200 11223',
    );
    await _tap(tester, find.text('Add person'));
    await _tap(
      tester,
      find.widgetWithText(FilledButton, 'Create loan and share'),
    );
    expect(find.byType(LoanDetailScreen), findsOne);

    await _tap(tester, find.text('Home'));
    expect(find.text('+919820011223 · interest free'), findsOne);
  });

  group('Confirm repayment', () {
    testWidgets('shows a spoken receipt and routes from the pending row', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (:router, loans: _) = await _pump(
        tester,
        location: SettloRoutes.loan('l1'),
      );

      await _tap(tester, find.text('awaiting you'));
      expect(router.state.uri.toString(), SettloRoutes.confirmRepayment('r3'));
      expect(find.text('Arjun says they paid you'), findsOne);
      expect(find.textContaining('on 5 Oct · UPI'), findsOne);
      expect(find.text('Outstanding after'), findsOne);
      expect(find.text('₹6,50,000'), findsOne);
      expect(_said('twenty-five thousand rupees'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Confirm ₹25,000 received'),
        findsOne,
      );
      await tester.scrollUntilVisible(
        find.text("Didn't receive this"),
        100,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text("Didn't receive this"), findsOne);
      expect(find.textContaining('Confirming is final'), findsOne);
      semantics.dispose();
    });

    testWidgets('borrower copy names the lender and describes money paid', (
      tester,
    ) async {
      final repayment = LoanRepayment(
        id: 'borrower-review',
        amount: const Paise.rupees(5000),
        paidOn: DateTime(2026, 10, 5),
        method: RepaymentMethod.bank,
        status: RepaymentStatus.pending,
        recordedByYou: false,
      );
      final loan = Loan(
        id: 'borrowed',
        counterparty: 'Meera',
        youLent: false,
        principal: const Paise.rupees(40000),
        repaid: const Paise.rupees(15000),
        startOn: DateTime(2026, 9),
        repayments: [repayment],
      );
      await _pump(
        tester,
        location: SettloRoutes.confirmRepayment(repayment.id),
        loans: FakeLoansRepository(
          LoansData(today: DateTime(2026, 11, 9), loans: [loan]),
        ),
      );

      expect(find.text('Meera says you paid ₹5,000'), findsOne);
      expect(find.textContaining('₹5,000 paid to Meera'), findsOne);
      expect(
        find.widgetWithText(FilledButton, 'Confirm ₹5,000 paid'),
        findsOne,
      );
      await tester.scrollUntilVisible(
        find.text("Didn't pay this"),
        100,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text("Didn't pay this"), findsOne);
      expect(find.textContaining(' says he '), findsNothing);

      await _tap(tester, find.text("Didn't pay this"));
      expect(find.text("Didn't pay ₹5,000 to Meera?"), findsOne);
      expect(find.widgetWithText(FilledButton, 'Mark as not paid'), findsOne);
    });

    testWidgets('primary no-pump double tap sends once', (tester) async {
      final (router: _, :loans) = await _pump(
        tester,
        location: SettloRoutes.confirmRepayment('r3'),
      );
      final hold = loans.hold = Completer<void>();
      final confirm = find.widgetWithText(
        FilledButton,
        'Confirm ₹25,000 received',
      );

      await tester.tap(confirm);
      await tester.tap(confirm);
      hold.complete();
      await tester.pumpAndSettle();

      expect(loans.calls, [startsWith('confirm_repayment ')]);
      expect(
        find.text('This repayment has already been answered and is read-only.'),
        findsOne,
      );
      expect(find.text('₹6,50,000'), findsOne);
    });

    testWidgets('overpayment warns, clamps to zero and cannot confirm', (
      tester,
    ) async {
      final repayment = LoanRepayment(
        id: 'too-much',
        amount: const Paise.rupees(25000),
        paidOn: DateTime(2026, 10, 5),
        status: RepaymentStatus.pending,
        recordedByYou: false,
      );
      final loan = Loan(
        id: 'nearly-closed',
        counterparty: 'Arjun',
        youLent: true,
        principal: const Paise.rupees(100000),
        repaid: const Paise.rupees(90000),
        startOn: DateTime(2026),
        repayments: [repayment],
      );
      await _pump(
        tester,
        location: SettloRoutes.confirmRepayment(repayment.id),
        loans: FakeLoansRepository(
          LoansData(today: DateTime(2026, 11, 9), loans: [loan]),
        ),
      );

      expect(find.text('₹0'), findsOne);
      expect(find.textContaining('Confirming will be refused'), findsOne);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm ₹25,000 received'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the recording party sees a read-only receipt', (tester) async {
      final loan = arjunLoan(
        repayments: [
          LoanRepayment(
            id: 'mine',
            amount: const Paise.rupees(25000),
            paidOn: DateTime(2026, 10, 5),
            method: RepaymentMethod.upi,
            status: RepaymentStatus.pending,
            recordedByYou: true,
          ),
        ],
      );
      await _pump(
        tester,
        location: SettloRoutes.confirmRepayment('mine'),
        loans: FakeLoansRepository(
          LoansData(today: DateTime(2026, 11, 9), loans: [loan]),
        ),
      );

      expect(find.text('You recorded this payment'), findsOne);
      expect(
        find.textContaining('Only the person who did not record'),
        findsOne,
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text("Didn't receive this"), findsNothing);
    });

    testWidgets('controls and receipt rows meet accessibility guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, location: SettloRoutes.confirmRepayment('r3'));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
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

    testWidgets('create', (tester) async {
      final (router: _, :loans) = await _pump(
        tester,
        location: SettloRoutes.newLoan,
      );
      await tester.enterText(find.byType(TextField).first, '10,00,000');
      await tester.enterText(
        find.ancestor(
          of: find.text('Phone number'),
          matching: find.byType(TextField),
        ),
        '98200 11223',
      );
      await _tap(tester, find.text('Add person'));
      await twice(
        tester,
        loans,
        find.widgetWithText(FilledButton, 'Create loan and share'),
      );
      expect(loans.calls, [startsWith('create_loan ')]);
      expect(_opened, hasLength(1));
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
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        semantics.dispose();
      });
    }

    testWidgets('new loan sheet', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, location: SettloRoutes.newLoan);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.enterText(find.byType(TextField).at(1), '98200 11223');
      await _tap(tester, find.text('Add person'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('record repayment sheet', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, location: SettloRoutes.loan('l1'));
      await _tap(tester, find.text('Record repayment'));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      semantics.dispose();
    });
  });
}

/// Home as the server builds it: the open loans in [loans].
class _HomeOverLoans extends FakeHomeRepository {
  new(this.loans) : super(homeEmpty);

  final FakeLoansRepository loans;

  @override
  Future<HomeData> load() async => HomeData(
    phone: homePhone,
    month: DateTime(2026, 11),
    loans: [
      for (final l in loans.data.loans)
        if (!l.closed)
          HomeLoan(
            id: l.id,
            counterparty: l.counterparty,
            youLent: l.youLent,
            outstanding: l.outstanding,
            installment: l.installment,
            installmentsPaid: l.installmentsPaid,
            installmentsTotal: l.installmentsTotal,
            nextDueOn: l.nextDueOn,
          ),
    ],
  );
}
