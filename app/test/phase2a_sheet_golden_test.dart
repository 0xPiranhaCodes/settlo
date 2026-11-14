import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

import 'sheet_hit_test.dart' show pumpTaskGolden, tapTaskControl;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final channels = <MethodChannel>[];
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            final args = call.arguments as Map<Object?, Object?>;
            final channel = MethodChannel('app.settlo/tab_bar/${args['id']}');
            channels.add(channel);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, (_) async => null);
          }
          return null;
        });
  });
  tearDown(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    channels.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });
  for (final device in [
    SettloGoldenDevices.canvas390,
    const GoldenDevice(name: 'se375x667', size: Size(375, 667)),
    const GoldenDevice(
      name: 'se375x667_text200',
      size: Size(375, 667),
      textScale: 2,
    ),
  ]) {
    for (final dark in [false, true]) {
      for (final (name, location, open)
          in <(String, String, Finder Function()?)>[
            ('loan', SettloRoutes.loan('l1'), null),
            ('profile', SettloRoutes.profile, null),
            ('new_expense', SettloRoutes.addExpenseIn('s1'), null),
            ('settle', SettloRoutes.settleWith('s2'), null),
            ('payment', SettloRoutes.settlePayTo('s2', 'm5'), null),
            ('new_loan', SettloRoutes.newLoan, null),
            ('confirm_repayment', SettloRoutes.confirmRepayment('r3'), null),
            (
              'create_space',
              SettloRoutes.spaces,
              () => find.bySemanticsLabel('New space'),
            ),
            (
              'members',
              SettloRoutes.space('s1'),
              () => find.bySemanticsLabel('Members of Flat 402'),
            ),
            (
              'resend_invite',
              SettloRoutes.spaces,
              () => find.text("Kabir hasn't joined yet"),
            ),
            ('export', SettloRoutes.profile, () => find.text('Export')),
            ('appearance', SettloRoutes.profile, () => find.text('Appearance')),
            (
              'delete_account',
              SettloRoutes.profile,
              () => find.text('Delete account'),
            ),
          ]) {
        testWidgets('phase2a $name ${device.name} dark=$dark', (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            await pumpTaskGolden(
              tester,
              device,
              location,
              theme: (dark ? SettloTheme.dark() : SettloTheme.light()).copyWith(
                platform: TargetPlatform.iOS,
              ),
            );
            if (open != null) await tapTaskControl(tester, open());
            expect(tester.takeException(), isNull);
            if (name == 'loan') {
              final header = tester.widget<SSheetHeader>(
                find.byType(SSheetHeader),
              );
              expect(header.title, 'Arjun');
              expect(header.leading, isA<SAvatar>());
              expect(
                find.descendant(
                  of: find.byType(SSheetHeader),
                  matching: find.text('A'),
                ),
                findsOneWidget,
              );
              final download = find.byWidgetPredicate(
                (widget) =>
                    widget is GlassAction &&
                    widget.label == 'Download statement',
              );
              expect(
                find.descendant(
                  of: find.byType(SSheetHeader),
                  matching: download,
                ),
                findsOneWidget,
              );
              expect(
                tester.getRect(download).bottom,
                lessThanOrEqualTo(
                  tester.getRect(find.byType(SSheetHeader)).bottom,
                ),
              );
            }
            if ([
              'new_expense',
              'settle',
              'new_loan',
              'create_space',
              'export',
            ].contains(name)) {
              final header = find.byType(SSheetHeader).last;
              expect(
                find.descendant(of: header, matching: find.byType(SAvatar)),
                findsNothing,
              );
              expect(
                find.descendant(of: header, matching: find.byType(SettloMark)),
                findsNothing,
              );
            }
            for (final element in find.byType(SSheetHeader).evaluate()) {
              final header = element.widget as SSheetHeader;
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: find.byWidget(header),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is RichText &&
                        widget.text.toPlainText() == header.title,
                  ),
                ),
              );
              final full = TextPainter(
                text: paragraph.text,
                textDirection: paragraph.textDirection,
                textScaler: paragraph.textScaler,
              )..layout(maxWidth: paragraph.size.width);
              expect(
                full.height,
                lessThanOrEqualTo(paragraph.size.height + .1),
                reason: 'The complete sheet title must fit at ${device.name}',
              );
              full.dispose();
            }
            await expectLater(
              find.byKey(settloGoldenSurfaceKey),
              matchesGoldenFile(
                'goldens/phase2a_${name}_${device.name}_${dark ? 'dark' : 'light'}.png',
              ),
            );
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
