import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  tearDown(() => iosMajorVersion = 0);
  for (final dark in [false, true]) {
    for (final native in [false, true]) {
      testWidgets('shared pushed header, dark=$dark native=$native', (
        tester,
      ) async {
        iosMajorVersion = native ? 26 : 18;
        final created = <int, Map<Object?, Object?>>{};
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call.method == 'create') {
            final args = call.arguments as Map<Object?, Object?>;
            final id = args['id']! as int;
            created[id] = const StandardMessageCodec().decodeMessage(
              ByteData.sublistView(args['params']! as Uint8List),
            ) as Map<Object?, Object?>;
            messenger.setMockMethodCallHandler(
              MethodChannel(glassActionChannel(id)),
              (_) async => null,
            );
          }
          return null;
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
        });
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: (dark ? SettloTheme.dark() : SettloTheme.light()).copyWith(
              platform: TargetPlatform.iOS,
            ),
            home: const Scaffold(body: Text('Root')),
          ),
        );
        void push() => navigator.currentState!.push(
          CupertinoPageRoute<void>(
            builder: (_) => const Scaffold(
              body: SettloScrollScaffold(
                title: 'Detail',
                largeTitle: 'Detail',
                previousPageTitle: 'Spaces',
                children: [Text('Unused header'), Text('Content')],
              ),
            ),
          ),
        );
        push();
        await tester.pumpAndSettle();
        expect(find.byType(GlassAction), findsOneWidget);
        expect(find.byType(CupertinoNavigationBarBackButton), findsNothing);
        final size = tester.getSize(find.byType(GlassAction));
        expect(size.height, 44);
        expect(size.width, greaterThanOrEqualTo(44));
        if (native) {
          expect(created.values.last['label'], 'Back to Spaces');
          expect(created.values.last['symbol'], 'chevron.left');
          expect(created.values.last['title'], 'Spaces');
          expect(created.values.last['dark'], dark);
          await messenger.handlePlatformMessage(
            glassActionChannel(created.keys.last),
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('tap'),
            ),
            (_) {},
          );
        } else {
          await tester.tap(find.bySemanticsLabel('Back to Spaces'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Root'), findsOneWidget);
        push();
        await tester.pumpAndSettle();
        await tester.dragFrom(const Offset(1, 250), const Offset(700, 0));
        await tester.pumpAndSettle();
        expect(find.text('Root'), findsOneWidget);
      });
    }
  }

  testWidgets('root has no back; pushed header infers the route destination', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: SettloTheme.light().copyWith(platform: TargetPlatform.iOS),
        onGenerateRoute: (_) => CupertinoPageRoute<void>(
          title: 'Spaces',
          builder: (_) => const Scaffold(
            body: SettloScrollScaffold(
              title: 'Spaces',
              largeTitle: 'Spaces',
              children: [SizedBox()],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(GlassAction), findsNothing);
    nav.currentState!.push(
      CupertinoPageRoute<void>(
        builder: (_) => const Scaffold(
          body: SettloScrollScaffold(
            title: 'Detail',
            largeTitle: 'Detail',
            children: [SizedBox()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Back to Spaces'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('back fallback RTL and 200% long destination on $platform', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark().copyWith(platform: platform),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 667),
              textScaler: TextScaler.linear(2),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: GlassAction.back(
                  destination: 'A very long destination name',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Back to A very long destination name'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(GlassAction)).height, 44);
      expect(find.byType(UiKitView), findsNothing);
      semantics.dispose();
    });
  }
}
