import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_platform/settlo_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final uri = Uri.parse('upi://pay?pa=kabir%40oksbi&pn=Kabir&am=1.00&cu=INR');

  tearDown(() => messenger.setMockMethodCallHandler(upiChooserChannel, null));

  test('asks Android for the chooser with the encoded URI', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(upiChooserChannel, (call) async {
      calls.add(call);
      return true;
    });

    expect(await openUpiChooser(uri), isTrue);
    expect(calls.single.method, 'openWithChooser');
    expect(calls.single.arguments, {'uri': '$uri', 'title': 'Pay with'});
  });

  test('false when no UPI app is installed', () async {
    messenger.setMockMethodCallHandler(upiChooserChannel, (_) async => false);
    expect(await openUpiChooser(uri), isFalse);

    messenger.setMockMethodCallHandler(upiChooserChannel, (_) async => null);
    expect(await openUpiChooser(uri), isFalse);
  });
}
