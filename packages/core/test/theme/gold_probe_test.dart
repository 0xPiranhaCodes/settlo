import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

/// How many pixels of the boundary around [finder] are gold, within a
/// small tolerance for blending.
Future<int> _goldPixels(WidgetTester tester, Finder finder) async {
  final data = (await tester.runAsync(() async {
    final image = await captureImage(tester.element(finder));
    return await image.toByteData();
  }))!;
  final gold = SettloColors.dark.action;
  int channel(double v) => (v * 255).round();
  var count = 0;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    if ((data.getUint8(i) - channel(gold.r)).abs() <= 4 &&
        (data.getUint8(i + 1) - channel(gold.g)).abs() <= 4 &&
        (data.getUint8(i + 2) - channel(gold.b)).abs() <= 4) {
      count++;
    }
  }
  return count;
}

Future<void> _pump(WidgetTester tester, ThemeData theme, Widget child) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: RepaintBoundary(key: _probe, child: child),
      ),
    ),
  );
}

const _probe = Key('probe');

void main() {
  // Gold means a tappable primary action (ov2). Material tints many widgets
  // with `colorScheme.primary` by default; this probe pins the theme's
  // neutral overrides so gold cannot leak back in.
  for (final (name, theme) in [
    ('dark', SettloTheme.dark),
    ('light', SettloTheme.light),
  ]) {
    group(name, () {
      testWidgets('progress, toggles, sliders, text buttons and focused '
          'inputs never paint the action colour', (tester) async {
        final controller = TextEditingController(text: 'Dinner')
          ..selection = const TextSelection(baseOffset: 0, extentOffset: 3);
        addTearDown(controller.dispose);
        await _pump(
          tester,
          theme(),
          Column(
            children: [
              const LinearProgressIndicator(value: 0.4),
              const CircularProgressIndicator(value: 0.4),
              Switch(value: true, onChanged: (_) {}),
              Switch(value: false, onChanged: (_) {}),
              RadioGroup<int>(
                groupValue: 1,
                onChanged: (_) {},
                child: const Row(children: [Radio(value: 1), Radio(value: 2)]),
              ),
              Slider(value: 0.5, onChanged: (_) {}),
              TextButton(onPressed: () {}, child: const Text('See all')),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );

        // Gold is dark's action colour; light's action (ink) is also its
        // primary text, so in both themes the probe forbids gold itself.
        final gold = SettloColors.dark.action;
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.cursorColor, isNot(gold));
        expect(field.selectionColor, isNot(gold));
        // Thin lines at fractional offsets blend with the background, so
        // the focused border is checked as resolved rather than by pixel.
        final decorator = tester.widget<InputDecorator>(
          find.byType(InputDecorator),
        );
        final decoration = decorator.decoration.applyDefaults(
          Theme.of(tester.element(find.byType(TextField))).inputDecorationTheme,
        );
        expect(decoration.focusedBorder?.borderSide.color, isNotNull);
        expect(decoration.focusedBorder!.borderSide.color, isNot(gold));
        expect(await _goldPixels(tester, find.byKey(_probe)), 0);
      });

      testWidgets('primary actions are gold; checked checkboxes are not', (
        tester,
      ) async {
        const button = Key('button');
        const checkbox = Key('checkbox');
        await _pump(
          tester,
          theme(),
          Column(
            children: [
              RepaintBoundary(
                key: button,
                child: FilledButton(onPressed: () {}, child: const Text('Add')),
              ),
              RepaintBoundary(
                key: checkbox,
                child: Checkbox(value: true, onChanged: (_) {}),
              ),
            ],
          ),
        );
        // Light's button is ink, so no gold at all.
        final expected = name == 'dark' ? greaterThan(50) : equals(0);
        expect(await _goldPixels(tester, find.byKey(button)), expected);
        expect(await _goldPixels(tester, find.byKey(checkbox)), 0);
      });

      testWidgets('no Settlo component but the primary button is gold', (
        tester,
      ) async {
        const tabs = [
          (icon: SizedBox.square(dimension: 22), label: 'Home'),
          (icon: SizedBox.square(dimension: 22), label: 'Activity'),
        ];
        const primary = Key('primary');
        await _pump(
          tester,
          theme(),
          Column(
            children: [
              const SCard(child: Text('Flat 402')),
              SSecondaryButton(label: 'Settle up', onPressed: () {}),
              Row(
                children: [
                  SChip(label: 'All', selected: true, onSelected: (_) {}),
                  SChip(label: 'Loans', selected: false, onSelected: (_) {}),
                  const SAvatar('Arjun'),
                ],
              ),
              SSegmentedControl<int>(
                segments: const [
                  (value: 0, label: 'Equally'),
                  (value: 1, label: '%'),
                ],
                selected: 0,
                onChanged: (_) {},
              ),
              SGlassTabBar(tabs: tabs, currentIndex: 0, onTap: (_) {}),
              SGlassTabBar(
                tabs: tabs,
                currentIndex: 1,
                lowEndBlur: true,
                onTap: (_) {},
              ),
              SizedBox(
                height: 300,
                child: SAmountSheet(
                  title: 'New expense',
                  amount: const Text('1,800'),
                  onClose: () {},
                  body: const Text('Paid by'),
                ),
              ),
            ],
          ),
        );
        expect(await _goldPixels(tester, find.byKey(_probe)), 0);

        // The same frame with a primary button: the probe sees its gold.
        await _pump(
          tester,
          theme(),
          RepaintBoundary(
            key: primary,
            child: SPrimaryButton(label: 'Save expense', onPressed: () {}),
          ),
        );
        final expected = name == 'dark' ? greaterThan(50) : equals(0);
        expect(await _goldPixels(tester, find.byKey(primary)), expected);
      });

      testWidgets('an unchecked checkbox is neutral', (tester) async {
        await _pump(tester, theme(), Checkbox(value: false, onChanged: (_) {}));
        expect(await _goldPixels(tester, find.byKey(_probe)), 0);
      });
    });
  }
}
