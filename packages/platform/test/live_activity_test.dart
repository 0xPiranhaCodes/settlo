import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';

PendingAnswer _settleUp(String id, DateTime at, {String payer = 'Priya'}) =>
    PendingAnswer(
      id: id,
      isRepayment: false,
      counterparty: payer,
      amount: const Paise(210000),
      paidOn: DateTime.utc(2026, 11, 10),
      recordedAt: at,
      spaceId: 'space-1',
      spaceName: 'Flat 402',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final early = DateTime.utc(2026, 11, 10, 8);
  final late = DateTime.utc(2026, 11, 10, 9);

  group('settleUpActivityFor', () {
    test('null when nothing waits for you', () {
      expect(settleUpActivityFor(const []), isNull);
    });

    test('repayments are not a Live Activity state', () {
      final repayment = PendingAnswer(
        id: 'r1',
        isRepayment: true,
        counterparty: 'Kabir',
        amount: const Paise(500000),
        paidOn: DateTime.utc(2026, 11, 10),
        recordedAt: late,
        loanId: 'loan-1',
      );
      expect(settleUpActivityFor([repayment]), isNull);
    });

    test('the newest settle-up, whatever the order', () {
      final shown = settleUpActivityFor([
        _settleUp('old', early, payer: 'Rahul'),
        _settleUp('new', late),
      ]);
      expect(
        shown,
        SettleUpActivity(
          id: 'new',
          spaceId: 'space-1',
          spaceName: 'Flat 402',
          payer: 'Priya',
          amount: const Paise(210000),
          recordedAt: late,
        ),
      );
      expect(shown!.confirmPath, '/spaces/space-1/settle-ups/new');
    });

    test('sends the native side formatted, ready-to-draw fields', () {
      expect(settleUpActivityFor([_settleUp('s1', late)])!.toChannel(), {
        'id': 's1',
        'space': 'Flat 402',
        'payer': 'Priya',
        'amount': '₹2,100',
        'recordedAtMs': late.millisecondsSinceEpoch,
        'path': '/spaces/space-1/settle-ups/s1',
      });
    });
  });

  group('LiveActivities', () {
    const activities = LiveActivities();
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(liveActivityChannel, (call) async {
        calls.add(call);
        return call.method == 'requestPermission' ? false : null;
      });
    });
    tearDown(
      () => messenger.setMockMethodCallHandler(liveActivityChannel, null),
    );

    test('shows a settle-up, then ends when it resolves', () async {
      final shown = settleUpActivityFor([_settleUp('s1', late)]);
      await activities.show(shown);
      await activities.show(null);

      expect(calls.map((c) => c.method), ['show', 'end']);
      expect(calls.first.arguments, shown!.toChannel());
      expect(calls.last.arguments, isNull);
    });

    test('passes on the permission answer', () async {
      expect(await activities.requestPermission(), isFalse);
      expect(calls.single.method, 'requestPermission');
    });

    test('no native side is a no-op, not an error', () async {
      messenger.setMockMethodCallHandler(liveActivityChannel, null);
      await activities.show(null);
      expect(await activities.requestPermission(), isTrue);
    });
  });

  group('prefersFlatChrome', () {
    tearDown(() => messenger.setMockMethodCallHandler(deviceChannel, null));

    test("follows Android's answer", () async {
      messenger.setMockMethodCallHandler(deviceChannel, (call) async {
        expect(call.method, 'prefersFlatChrome');
        return true;
      });
      expect(await prefersFlatChrome(), isTrue);
    });

    test('glass where there is no native side (iOS)', () async {
      expect(await prefersFlatChrome(), isFalse);
    });
  });
}
