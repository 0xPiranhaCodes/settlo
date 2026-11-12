import 'dart:ui' show SemanticsFlag;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

const TargetPlatform _ios = TargetPlatform.iOS;
const TargetPlatform _android = TargetPlatform.android;

Widget _app(TargetPlatform platform, Widget child, {bool light = false}) =>
    MaterialApp(
      theme: (light ? SettloTheme.light() : SettloTheme.dark()).copyWith(
        platform: platform,
      ),
      home: Scaffold(body: Center(child: child)),
    );

/// A button that runs [open] with its context and records the answer.
Widget _opener(
  TargetPlatform platform,
  Future<Object?> Function(BuildContext) open,
  List<Object?> answers,
) => _app(
  platform,
  Builder(
    builder: (context) => TextButton(
      onPressed: () async => answers.add(await open(context)),
      child: const Text('Open'),
    ),
  ),
);

void main() {
  group('SSwitch', () {
    for (final light in [false, true]) {
      testWidgets('is a CupertinoSwitch on iOS, tinted primary action, '
          '${light ? 'light' : 'dark'}', (tester) async {
        var value = false;
        await tester.pumpWidget(
          _app(
            _ios,
            StatefulBuilder(
              builder: (context, setState) => SSwitch(
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
            light: light,
          ),
        );
        final colors = light ? SettloColors.light : SettloColors.dark;
        final control = tester.widget<CupertinoSwitch>(
          find.byType(CupertinoSwitch),
        );
        expect(control.activeTrackColor, colors.action);
        expect(control.activeTrackColor, isNot(CupertinoColors.systemGreen));
        expect(find.byType(Switch), findsNothing);

        await tester.tap(find.byType(CupertinoSwitch));
        await tester.pumpAndSettle();
        expect(value, isTrue);
        expect(
          tester
              .widget<CupertinoSwitch>(find.byType(CupertinoSwitch))
              .thumbColor,
          colors.onAction,
          reason: 'the thumb uses the high-contrast action label pair',
        );
      });
    }

    testWidgets('stays a Material Switch on Android', (tester) async {
      await tester.pumpWidget(
        _app(_android, const SSwitch(value: false, onChanged: null)),
      );
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsNothing);
    });
  });

  group('showSettloDatePicker', () {
    final first = DateTime(2026);
    final last = DateTime(2026, 11, 11);

    Future<Object?> open(BuildContext context) => showSettloDatePicker(
      context: context,
      initialDate: DateTime(2026, 11, 10),
      firstDate: first,
      lastDate: last,
    );

    testWidgets('is a Cupertino wheel with Done on iOS', (tester) async {
      final answers = <Object?>[];
      await tester.pumpWidget(_opener(_ios, open, answers));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.byType(DatePickerDialog), findsNothing);
      final picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(picker.mode, CupertinoDatePickerMode.date);
      expect(picker.maximumDate, last);
      // Figtree, not SF.
      expect(
        CupertinoTheme.of(tester.element(find.byType(CupertinoDatePicker)))
            .textTheme
            .dateTimePickerTextStyle
            .fontFamily,
        contains(SettloTypography.figtreeFamily),
      );

      // The day column: 10 → 9.
      await tester.drag(find.text('10'), const Offset(0, 40));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(answers, [DateTime(2026, 11, 9)]);
    });

    testWidgets('a tap outside on iOS answers null', (tester) async {
      final answers = <Object?>[];
      await tester.pumpWidget(_opener(_ios, open, answers));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(answers, [null]);
    });

    testWidgets('stays the Material calendar on Android', (tester) async {
      final answers = <Object?>[];
      await tester.pumpWidget(_opener(_android, open, answers));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(find.byType(CupertinoDatePicker), findsNothing);
    });
  });

  testWidgets('showSettloPicker picks from a wheel on iOS', (tester) async {
    final answers = <Object?>[];
    await tester.pumpWidget(
      _opener(
        _ios,
        (context) => showSettloPicker<int>(
          context: context,
          values: const [1, 2, 3, 4, 5],
          selected: 2,
          label: (d) => 'Day $d',
        ),
        answers,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPicker), findsOneWidget);

    await tester.drag(find.byType(CupertinoPicker), const Offset(0, -50));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(answers, [3]);
  });

  group('SSegmentedControl', () {
    Widget control(TargetPlatform platform, ValueChanged<String> onChanged) =>
        _app(
          platform,
          SSegmentedControl<String>(
            segments: const [
              (value: 'equal', label: 'Equally'),
              (value: 'exact', label: 'Exact'),
            ],
            selected: 'equal',
            onChanged: onChanged,
          ),
        );

    testWidgets('is a sliding Cupertino control on iOS', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(control(_ios, picked.add));
      final sliding = find.byType(CupertinoSlidingSegmentedControl<String>);
      expect(sliding, findsOneWidget);
      expect(
        tester
            .widget<CupertinoSlidingSegmentedControl<String>>(sliding)
            .thumbColor,
        SettloColors.dark.surfaceHighest,
      );
      expect(tester.getSize(sliding).height, greaterThanOrEqualTo(44));

      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      expect(picked, ['exact']);
    });

    testWidgets('keeps the Settlo control on Android', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(control(_android, picked.add));
      expect(
        find.byType(CupertinoSlidingSegmentedControl<String>),
        findsNothing,
      );
      await tester.tap(find.text('Exact'));
      expect(picked, ['exact']);
    });
  });

  testWidgets('SSearchField reports each edit, in Figtree', (tester) async {
    final queries = <String>[];
    await tester.pumpWidget(_app(_ios, SSearchField(onChanged: queries.add)));
    expect(find.text('Search'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoSearchTextField), 'flat');
    expect(queries, ['flat']);
    final field = tester.widget<CupertinoSearchTextField>(
      find.byType(CupertinoSearchTextField),
    );
    expect(field.style?.fontFamily, contains(SettloTypography.figtreeFamily));
  });

  test('searchMatches finds every word, anywhere, ignoring case', () {
    expect(searchMatches('', 'Flat 402'), isTrue);
    expect(searchMatches('flat', 'Flat 402'), isTrue);
    expect(searchMatches(' 402  FL ', 'Flat 402'), isTrue);
    expect(searchMatches('goa', 'Flat 402'), isFalse);
    expect(searchMatches('flat goa', 'Flat 402'), isFalse);
  });

  group('showSettloNotice', () {
    Widget noticing(TargetPlatform platform) => _app(
      platform,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showSettloNotice(context, "Couldn't open WhatsApp"),
          child: const Text('Notify'),
        ),
      ),
    );

    testWidgets('is a top banner on iOS that leaves by itself', (tester) async {
      await tester.pumpWidget(noticing(_ios));
      await tester.tap(find.text('Notify'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      final banner = find.text("Couldn't open WhatsApp");
      expect(banner, findsOneWidget);
      expect(tester.getTopLeft(banner).dy, lessThan(100), reason: 'top');

      await tester.pump(const Duration(seconds: 4));
      expect(banner, findsNothing);
    });

    testWidgets('a tap dismisses the iOS banner; a second replaces it', (
      tester,
    ) async {
      await tester.pumpWidget(noticing(_ios));
      await tester.tap(find.text('Notify'));
      await tester.pump();
      await tester.tap(find.text('Notify'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't open WhatsApp"), findsOneWidget);

      await tester.tap(find.text("Couldn't open WhatsApp"));
      await tester.pump();
      expect(find.text("Couldn't open WhatsApp"), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('stays a snackbar on Android', (tester) async {
      await tester.pumpWidget(noticing(_android));
      await tester.tap(find.text('Notify'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('showSettloPageSheet', () {
    for (final platform in [_ios, _android]) {
      testWidgets('is a Cupertino sheet only on ${platform.name}', (
        tester,
      ) async {
        var fellBack = false;
        await tester.pumpWidget(
          _opener(
            platform,
            (context) => showSettloPageSheet<void>(
              context: context,
              builder: (_) => const Text('Sheet body'),
              fallback: () async => fellBack = true,
            ),
            [],
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final ios = platform == _ios;
        expect(fellBack, !ios);
        if (ios) {
          expect(
            ModalRoute.of(tester.element(find.text('Sheet body'))),
            isA<CupertinoSheetRoute<void>>(),
          );
        }
      });
    }
  });

  group('the keyboard Done bar', () {
    Widget sheet(TargetPlatform platform, FocusNode focus) => MaterialApp(
      theme: SettloTheme.dark().copyWith(platform: platform),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          viewInsets: EdgeInsets.only(bottom: 300),
        ),
        // No Scaffold: it would take the inset off, as the sheets do not.
        child: Material(
          child: SAmountSheet(
            title: 'New expense',
            onClose: () {},
            amount: SizedBox(
              width: 80,
              child: TextField(focusNode: focus, autofocus: true),
            ),
          ),
        ),
      ),
    );

    testWidgets('closes the decimal keypad on iOS', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(sheet(_ios, focus));
      await tester.pump();
      expect(focus.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey('keyboard-done')));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    });

    testWidgets('is not shown on Android', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(sheet(_android, focus));
      expect(find.byKey(const ValueKey('keyboard-done')), findsNothing);
    });
  });

  group('an amount sheet shown with showSAmountSheet', () {
    Future<void> open(WidgetTester tester, TargetPlatform platform) async {
      await tester.pumpWidget(
        _opener(
          platform,
          (context) => showSAmountSheet<void>(
            context: context,
            builder: (sheet) => SAmountSheet(
              title: 'Edit expense',
              amount: const Text('420'),
              dirty: true,
              onClose: () => Navigator.of(sheet).pop(),
            ),
          ),
          [],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks before a drag down drops edits on iOS', (tester) async {
      await open(tester, _ios);
      await tester.fling(find.text('Edit expense'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edit expense'), findsOneWidget);

      await tester.fling(find.text('Edit expense'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Edit expense'), findsNothing);
    });

    testWidgets('closes straight away on Android', (tester) async {
      await open(tester, _android);
      await tester.fling(find.text('Edit expense'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Edit expense'), findsNothing);
    });
  });

  group('wheel selection band', () {
    for (final light in [false, true]) {
      final colors = light ? SettloColors.light : SettloColors.dark;
      final pickers = <String, Future<Object?> Function(BuildContext)>{
        'date': (context) => showSettloDatePicker(
          context: context,
          initialDate: DateTime(2026, 11, 10),
          firstDate: DateTime(2026),
          lastDate: DateTime(2026, 11, 11),
        ),
        'value': (context) => showSettloPicker<int>(
          context: context,
          values: const [1, 2, 3],
          selected: 2,
          label: (d) => 'Day $d',
        ),
      };
      for (final MapEntry(key: name, value: open) in pickers.entries) {
        testWidgets('is a Settlo surface on the $name wheel, '
            '${light ? 'light' : 'dark'}', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: (light ? SettloTheme.light() : SettloTheme.dark())
                  .copyWith(platform: _ios),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => open(context),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final bands = tester
              .widgetList<CupertinoPickerDefaultSelectionOverlay>(
                find.byType(CupertinoPickerDefaultSelectionOverlay),
              );
          expect(bands, isNotEmpty);
          for (final band in bands) {
            expect(band.background, colors.surfaceHighest);
          }
        });
      }
    }
  });

  group('VoiceOver can activate', () {
    testWidgets('a switch, a segment and the wheel Done', (tester) async {
      final semantics = tester.ensureSemantics();
      var on = false;
      String? segment;
      final answers = <Object?>[];
      await tester.pumpWidget(
        _app(
          _ios,
          Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatefulBuilder(
                  builder: (context, setState) => SSwitch(
                    value: on,
                    onChanged: (v) => setState(() => on = v),
                  ),
                ),
                SSegmentedControl<String>(
                  segments: const [
                    (value: 'equal', label: 'Equally'),
                    (value: 'exact', label: 'Exact'),
                  ],
                  selected: 'equal',
                  onChanged: (v) => segment = v,
                ),
                TextButton(
                  onPressed: () async => answers.add(
                    await showSettloPicker<int>(
                      context: context,
                      values: const [1, 2],
                      selected: 2,
                      label: (d) => 'Day $d',
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ),
      );
      tester.semantics.tap(
        find.semantics.byFlag(SemanticsFlag.hasToggledState),
      );
      await tester.pumpAndSettle();
      expect(on, isTrue);
      tester.semantics.tap(find.semantics.byLabel('Exact'));
      await tester.pumpAndSettle();
      expect(segment, 'exact');
      tester.semantics.tap(find.semantics.byLabel('Open'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('Done'));
      await tester.pumpAndSettle();
      expect(answers, [2]);
      semantics.dispose();
    });

    testWidgets('the notice banner, to dismiss it', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          _ios,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showSettloNotice(context, 'Saved'),
              child: const Text('Notify'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Notify'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('Saved'));
      await tester.pump();
      expect(find.text('Saved'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      semantics.dispose();
    });
  });
}
