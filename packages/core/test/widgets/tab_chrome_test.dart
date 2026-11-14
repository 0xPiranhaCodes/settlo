import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('tabs share inset, collapse and material $platform $scale', (
        tester,
      ) async {
        await loadSettloFonts();
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        double? contentTop;
        for (final title in ['Home', 'Spaces', 'Loans', 'Activity']) {
          final controller = ScrollController();
          var taps = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: SettloTheme.light().copyWith(platform: platform),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(375, 667),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: SettloTabScaffold(
                    key: ValueKey(title),
                    title: title,
                    controller: controller,
                    children: [
                      SettloNavigationHeader(
                        title: title,
                        trailing: GestureDetector(
                          key: const ValueKey('action'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => taps++,
                          child: SizedBox(
                            width: title == 'Spaces' || title == 'Loans'
                                ? 148
                                : title == 'Home'
                                ? 96
                                : 44,
                            height: 44,
                          ),
                        ),
                      ),
                      const SizedBox(key: ValueKey('first'), height: 48),
                      const SizedBox(height: 1800),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final first = tester.getRect(find.byKey(const ValueKey('first')));
          expect(first.left, 16);
          expect(first.right, 359);
          contentTop ??= first.top;
          expect(first.top, contentTop);
          expect(
            tester.getRect(find.byKey(const ValueKey('action'))).right,
            359,
          );
          expect(tester.widget<Text>(find.text(title)).style!.fontSize, 34);
          expect(
            tester.widget<Text>(find.text(title)).style!.fontWeight,
            FontWeight.w700,
          );
          final blur = find
              .ancestor(
                of: find.byKey(const ValueKey('tab-header-material')),
                matching: find.byType(BackdropFilter),
              )
              .first;
          expect(tester.widget<BackdropFilter>(blur).enabled, isFalse);
          controller.jumpTo(16);
          await tester.pump();
          expect(
            tester.widget<BackdropFilter>(blur).enabled,
            isFalse,
            reason: 'Title collapse alone has no content underneath',
          );
          expect(
            tester.widget<Text>(find.text(title)).style!.fontSize,
            allOf(greaterThan(17), lessThan(34)),
          );
          expect(find.text(title), findsOneWidget);
          for (var offset = 1.0; offset <= 90; offset += 1) {
            controller.jumpTo(offset);
            await tester.pump();
            await tester.tap(find.byKey(const ValueKey('action')));
            expect(taps, offset.toInt());
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(title),
                matching: find.byType(RichText),
              ),
            );
            final origin = paragraph.localToGlobal(Offset.zero);
            final action = tester.getRect(find.byKey(const ValueKey('action')));
            for (final box in paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: title.length),
            )) {
              final glyph = box.toRect().shift(origin);
              final header = tester.getRect(
                find.byKey(const ValueKey('tab-header-material')),
              );
              expect(glyph.bottom, lessThanOrEqualTo(header.bottom + .5));
              expect(
                glyph.overlaps(action),
                isFalse,
                reason:
                    '$title at $offset / $scale: ${box.toRect().shift(origin)} vs $action',
              );
            }
          }
          controller.jumpTo(240);
          await tester.pump();
          expect(tester.widget<Text>(find.text(title)).style!.fontSize, 17);
          expect(tester.widget<BackdropFilter>(blur).enabled, isTrue);
          expect(tester.takeException(), isNull);
          controller.jumpTo(0);
          await tester.pump();
          expect(tester.widget<BackdropFilter>(blur).enabled, isFalse);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      });
    }
  }
  testWidgets('tab row avatars cap at 1.5 and amounts wrap below title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark(),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(375, 667),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SGroup(
              children: [
                SRow(
                  title: 'A long name',
                  subtitle: 'A subtitle',
                  scaleLeading: true,
                  leading: SAvatar('Alex', size: 36),
                  trailing: Text('₹2,850'),
                  chevron: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final avatar = tester.getRect(find.byType(SAvatar));
    expect(avatar.width, 54);
    expect(
      tester.getTopLeft(find.text('₹2,850')).dy,
      greaterThan(tester.getBottomLeft(find.text('A long name')).dy),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('iOS tab action sends neutral foreground to native glass', (
    tester,
  ) async {
    iosMajorVersion = 26;
    addTearDown(() => iosMajorVersion = 0);
    final messenger = tester.binding.defaultBinaryMessenger;
    final created = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        created.add(
          const StandardMessageCodec().decodeMessage(
            ByteData.sublistView(args['params']! as Uint8List),
          ) as Map<Object?, Object?>,
        );
      }
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark().copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: SettloTabScaffold(
            title: 'Spaces',
            children: [
              SettloNavigationHeader(
                title: 'Spaces',
                trailing: GlassAction(
                  label: 'New space',
                  symbol: 'plus',
                  onPressed: () {},
                  fallback: const SizedBox(),
                ),
              ),
              const Text('Content'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      created.single['foreground'],
      SettloColors.dark.textPrimary.toARGB32(),
    );
    await tester.pumpWidget(const SizedBox());
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });
}
