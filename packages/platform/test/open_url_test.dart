import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

final class _Launcher extends UrlLauncherPlatform {
  bool installed = true;
  final checked = <String>[];
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    checked.add(url);
    return installed;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final launcher = _Launcher();
  UrlLauncherPlatform.instance = launcher;

  setUp(() {
    launcher
      ..installed = true
      ..checked.clear()
      ..launched.clear();
  });

  Future<bool> open(String phone, String text) =>
      ProviderContainer().read(openWhatsAppProvider)(phone, text);

  test('opens a WhatsApp chat with the number and encoded text', () async {
    expect(await open('919900000010', 'Hi Priya, you owe ₹1,200 & more'), true);
    expect(
      launcher.launched.single,
      'whatsapp://send?phone=919900000010'
      '&text=Hi%20Priya%2C%20you%20owe%20%E2%82%B91%2C200%20%26%20more',
    );
  });

  test('without WhatsApp it says so and opens nothing', () async {
    launcher.installed = false;
    expect(await open('919900000010', 'Hi'), false);
    expect(launcher.checked, hasLength(1));
    expect(launcher.launched, isEmpty);
  });
}
