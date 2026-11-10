import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  test('builds the custom-scheme fallback until a host is configured', () {
    expect(inviteHttpsHost, isEmpty);
    expect(inviteLink('abc').toString(), 'settlo://join/abc');
  });
}
