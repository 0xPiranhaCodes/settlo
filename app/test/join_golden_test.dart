import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

final class _Invites implements InvitesRepository {
  @override
  Future<InvitePreview?> inspect(String token) async => const InvitePreview(
    kind: 'space',
    inviterName: 'Satheesh',
    subjectName: 'Flat 402',
    maskedPhone: '+91 98111 ••• 44',
  );

  @override
  Future<void> decline(String token, {required String idempotencyKey}) async {}
  @override
  Future<void> redeem(String token, {required String idempotencyKey}) async {}
  @override
  Future<String> issueLoan(String loanId, {required String idempotencyKey}) =>
      throw UnimplementedError();
  @override
  Future<String> issueSpace(
    String memberId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

void main() {
  for (final device in SettloGoldenDevices.all) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      testWidgets('${device.name} $themeName Join golden', (tester) async {
        await pumpSettloGolden(
          tester,
          device: device,
          theme: theme,
          child: ProviderScope(
            overrides: [
              invitesRepositoryProvider.overrideWithValue(_Invites()),
            ],
            child: const JoinScreen(
              token:
                  'dddddddddddddddddddddddddddddddd'
                  'dddddddddddddddddddddddddddddddd',
            ),
          ),
        );

        await expectLater(
          find.byKey(settloGoldenSurfaceKey),
          matchesGoldenFile('goldens/join_${device.name}_$themeName.png'),
        );
      });
    }
  }
}
