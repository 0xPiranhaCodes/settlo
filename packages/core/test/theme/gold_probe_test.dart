import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

/// How many pixels of the boundary around [finder] use the action hue, within a
/// small tolerance for blending.
Future<int> _actionPixels(WidgetTester tester, Finder finder) async {
  final data = (await tester.runAsync(() async {
    final image = await captureImage(tester.element(finder));
    return await image.toByteData();
  }))!;
  final action = SettloColors.of(tester.element(finder)).action;
  int channel(double v) => (v * 255).round();
  var count = 0;
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    if ((data.getUint8(i) - channel(action.r)).abs() <= 4 &&
        (data.getUint8(i + 1) - channel(action.g)).abs() <= 4 &&
        (data.getUint8(i + 2) - channel(action.b)).abs() <= 4) {
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
  // Probe rendered pixels so Material and custom controls really paint the
  // supplied action hue; checking ThemeData alone would miss overrides.
  for (final (name, theme) in [
    ('dark', SettloTheme.dark),
    ('light', SettloTheme.light),
  ]) {
    group(name, () {
      testWidgets('progress, toggles, sliders, text buttons and focused '
          'inputs use the semantic palette', (tester) async {
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

        // Editing chrome retains primary-text focus and selection colors.
        final action = theme().extension<SettloColors>()!.action;
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.cursorColor, isNot(action));
        expect(field.selectionColor, isNot(action));
        // Thin lines at fractional offsets blend with the background, so
        // the focused border is checked as resolved rather than by pixel.
        final decorator = tester.widget<InputDecorator>(
          find.byType(InputDecorator),
        );
        final decoration = decorator.decoration.applyDefaults(
          Theme.of(tester.element(find.byType(TextField))).inputDecorationTheme,
        );
        expect(decoration.focusedBorder?.borderSide.color, isNotNull);
        expect(decoration.focusedBorder!.borderSide.color, isNot(action));
        expect(
          await _actionPixels(tester, find.byKey(_probe)),
          greaterThan(50),
        );
      });

      testWidgets(
        'primary actions and checked checkboxes use the action colour',
        (tester) async {
          const button = Key('button');
          const checkbox = Key('checkbox');
          await _pump(
            tester,
            theme(),
            Column(
              children: [
                RepaintBoundary(
                  key: button,
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Add'),
                  ),
                ),
                RepaintBoundary(
                  key: checkbox,
                  child: Checkbox(value: true, onChanged: (_) {}),
                ),
              ],
            ),
          );
          // Both appearances paint their supplied action hue.
          final expected = greaterThan(50);
          expect(await _actionPixels(tester, find.byKey(button)), expected);
          expect(
            await _actionPixels(tester, find.byKey(checkbox)),
            greaterThan(50),
          );
        },
      );

      testWidgets(
        'selected chips, tabs and primary buttons use the action colour',
        (tester) async {
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
          expect(
            await _actionPixels(tester, find.byKey(_probe)),
            greaterThan(50),
          );

          // The same frame with a primary button exposes the action hue.
          await _pump(
            tester,
            theme(),
            RepaintBoundary(
              key: primary,
              child: SPrimaryButton(label: 'Save expense', onPressed: () {}),
            ),
          );
          final expected = greaterThan(50);
          expect(await _actionPixels(tester, find.byKey(primary)), expected);
        },
      );

      testWidgets('an unchecked checkbox is neutral', (tester) async {
        await _pump(tester, theme(), Checkbox(value: false, onChanged: (_) {}));
        expect(await _actionPixels(tester, find.byKey(_probe)), 0);
      });
    });
  }
}
