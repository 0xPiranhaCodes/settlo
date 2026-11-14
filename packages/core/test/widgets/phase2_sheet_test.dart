import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  testWidgets('Reduce Transparency makes the scrolled sheet opaque', (
    tester,
  ) async {
    const channel = MethodChannel('app.settlo/accessibility');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'reduceTransparency',
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.light(),
        home: Scaffold(
          body: SSheetHeader(
            title: 'New expense',
            onClose: () {},
            scrolledUnder: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final filter = tester.widget<BackdropFilter>(
      find.descendant(
        of: find.byType(SSheetHeader),
        matching: find.byType(BackdropFilter),
      ),
    );
    expect(filter.enabled, isFalse);
    final fill = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(SSheetHeader),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(fill.color.a, 1);
    expect(find.byType(SAvatar), findsNothing);
    expect(find.byType(SettloMark), findsNothing);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('reduceTransparencyChanged', false),
      ),
      (_) {},
    );
    await tester.pump();
    expect(
      tester
          .widget<BackdropFilter>(
            find.descendant(
              of: find.byType(SSheetHeader),
              matching: find.byType(BackdropFilter),
            ),
          )
          .enabled,
      isTrue,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAccessibilityFeaturesChanged();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BackdropFilter>(
            find.descendant(
              of: find.byType(SSheetHeader),
              matching: find.byType(BackdropFilter),
            ),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('a short trailing amount leaves the title room', (tester) async {
    tester.view
      ..physicalSize = const Size(375, 667)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.light(),
        home: const Scaffold(
          body: SGroup(
            children: [
              SRow(
                title: 'Weekly food',
                subtitle:
                    'A very long second line that must end with an ellipsis',
                trailing: Text('₹50'),
              ),
            ],
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('Weekly food'),
        matching: find.byType(RichText),
      ),
    );
    expect(paragraph.size.height, lessThan(25));
    final subtitle = tester.widget<Text>(
      find.text('A very long second line that must end with an ellipsis'),
    );
    expect(subtitle.maxLines, 1);
    expect(subtitle.overflow, TextOverflow.ellipsis);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform nested task stays in its sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.light().copyWith(platform: platform),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => pushSettloSheet<void>(
                context,
                (context) => SSheetScaffold(
                  title: 'Root',
                  onClose: () => Navigator.of(context).pop(),
                  children: [
                    TextButton(
                      onPressed: () => pushSettloSheet<void>(
                        context,
                        (context) => SSheetScaffold(
                          title: 'Step',
                          onClose: () => Navigator.of(context).pop(),
                          children: const [Text('Nested content')],
                        ),
                      ),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final navigator = Navigator.of(tester.element(find.text('Next')));
      final sheet = ModalRoute.of(navigator.context);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(
        Navigator.of(tester.element(find.text('Nested content'))),
        same(navigator),
      );
      expect(ModalRoute.of(navigator.context), same(sheet));
      expect(find.byType(GlassAction).evaluate().length, 2);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Next'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform Reduce Motion opens and dismisses instantly', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.light().copyWith(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () => pushSettloSheet<void>(
                context,
                (context) => SSheetScaffold(
                  title: 'Instant sheet',
                  onClose: () => finishSettloSheet(context),
                  children: const [],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Instant sheet').hitTestable(), findsOneWidget);
      final navigator = Navigator.of(
        tester.element(find.text('Instant sheet')),
      );
      final route = ModalRoute.of(navigator.context)!;
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Instant sheet'), findsNothing);
      expect(find.text('Open').hitTestable(), findsOneWidget);
    });
  }
}
