import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_auth/src/phone_number.dart';
import 'package:settlo_core/settlo_core.dart';

/// Length of a Supabase SMS code.
const otpLength = 6;

/// Something the person can fix on the Phone or OTP screen.
enum SignInError {
  /// The number cannot be a mobile number in the chosen country.
  invalidNumber,

  /// Fewer than [otpLength] digits.
  incompleteCode,

  /// The server would not text this number.
  sendRejected,

  /// The code was wrong or has expired.
  codeRejected,

  /// Too many tries in a short time.
  rateLimited,

  /// The server could not be reached.
  network;

  /// What to tell the person, for numbers in [country]. Plain and warm,
  /// sentence case, no exclamation marks; never says whether the number
  /// already has an account or anything recorded against it.
  String message(Country country) => switch (this) {
    invalidNumber when country == Country.india =>
      'Enter a 10-digit mobile number starting with 6, 7, 8 or 9.',
    invalidNumber =>
      'That number looks too short or too long. Check it and try again.',
    incompleteCode => 'Enter all six digits of the code.',
    sendRejected =>
      "We couldn't send a code to that number. Check it and try again.",
    codeRejected =>
      "That code didn't work. It may have expired, so check it or ask for "
          'a new one.',
    rateLimited =>
      "That's a lot of tries in a short time. Wait a minute, "
          'then try again.',
    network => "We couldn't reach Settlo. Check your connection and try again.",
  };
}

/// Where the sign-in flow is: the number being entered, where the code
/// went, whether a call is in flight and the last error.
@immutable
final class SignInState {
  /// A state; the default is India with no number entered.
  const new({
    this.country = Country.india,
    this.national = '',
    this.sentTo,
    this.busy = false,
    this.error,
  });

  /// The selected country.
  final Country country;

  /// National digits as typed, without grouping.
  final String national;

  /// The E.164 number the current code was sent to, once sent.
  final String? sentTo;

  /// Whether a send or verify call is in flight.
  final bool busy;

  /// The last error, until the person changes something.
  final SignInError? error;

  /// A copy with the given fields; [error] is cleared unless passed.
  SignInState _next({
    Country? country,
    String? national,
    String? sentTo,
    bool? busy,
    SignInError? error,
  }) => SignInState(
    country: country ?? this.country,
    national: national ?? this.national,
    sentTo: sentTo ?? this.sentTo,
    busy: busy ?? this.busy,
    error: error,
  );
}

/// The Welcome → Phone → OTP flow. Lives while any sign-in screen is shown;
/// a verified code changes the session and the router leaves the flow.
final NotifierProvider<SignInController, SignInState> signInProvider =
    NotifierProvider.autoDispose<SignInController, SignInState>(
      SignInController.new,
    );

/// Drives [signInProvider] through [phoneAuthProvider].
class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  /// Switches to [country]; the typed digits stay.
  void selectCountry(Country country) => state = state._next(country: country);

  /// Records the field's text as [input].
  void updateNumber(String input) {
    final national = state.country.nationalDigits(input);
    if (national != state.national) {
      state = state._next(national: national);
    }
  }

  /// Validates the number and texts a code to it. True when sent.
  Future<bool> sendCode() async {
    if (state.busy) return false;
    final phone = state.country.e164(state.national);
    if (phone == null) {
      state = state._next(error: SignInError.invalidNumber);
      return false;
    }
    return await _send(phone);
  }

  /// Texts a new code to the number the last one went to. True when sent.
  Future<bool> resendCode() async {
    final phone = state.sentTo;
    if (state.busy || phone == null) return false;
    return await _send(phone);
  }

  /// Signs in with [code]. On success the session changes and the router
  /// moves on; on failure [SignInState.error] says why.
  Future<void> verifyCode(String code) async {
    final phone = state.sentTo;
    if (state.busy || phone == null) return;
    if (!RegExp('^\\d{$otpLength}\$').hasMatch(code)) {
      state = state._next(error: SignInError.incompleteCode);
      return;
    }
    state = state._next(busy: true);
    final error = await _call(
      () => ref.read(phoneAuthProvider).verifyCode(phone: phone, code: code),
      rejected: SignInError.codeRejected,
    );
    if (ref.mounted) state = state._next(busy: false, error: error);
  }

  Future<bool> _send(String phone) async {
    state = state._next(busy: true);
    final error = await _call(
      () => ref.read(phoneAuthProvider).sendCode(phone),
      rejected: SignInError.sendRejected,
    );
    if (!ref.mounted) return false;
    state = error == null
        ? state._next(busy: false, sentTo: phone)
        : state._next(busy: false, error: error);
    return error == null;
  }

  static Future<SignInError?> _call(
    Future<void> Function() call, {
    required SignInError rejected,
  }) async {
    try {
      await call();
      return null;
    } on PhoneAuthException catch (e) {
      return switch (e.failure) {
        PhoneAuthFailure.rejected => rejected,
        PhoneAuthFailure.rateLimited => SignInError.rateLimited,
        PhoneAuthFailure.network => SignInError.network,
      };
    }
  }
}
