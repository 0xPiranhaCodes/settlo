import 'package:settlo_core/settlo_core.dart';

/// A [PhoneAuth] that records calls and fails with [failure] when set.
class FakePhoneAuth implements PhoneAuth {
  /// The identity returned by a successful verification.
  String? verifiedUserId = '00000000-0000-0000-0000-000000000001';

  /// The next calls fail with this, until cleared.
  PhoneAuthFailure? failure;

  /// Numbers codes were sent to, in order.
  final sent = <String>[];

  /// Codes verified, as (phone, code).
  final verified = <(String, String)>[];

  @override
  Future<void> sendCode(String phone) async {
    if (failure case final f?) throw PhoneAuthException(f);
    sent.add(phone);
  }

  @override
  Future<String?> verifyCode({
    required String phone,
    required String code,
  }) async {
    if (failure case final f?) throw PhoneAuthException(f);
    verified.add((phone, code));
    return verifiedUserId;
  }
}
