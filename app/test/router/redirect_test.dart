import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/router/redirect.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  group('signed out', () {
    String? redirect(String location) =>
        authRedirect(signedIn: false, location: location);

    test('sign-in steps and invite links stay put', () {
      for (final path in [
        SettloRoutes.welcome,
        SettloRoutes.phone,
        SettloRoutes.otp,
        SettloRoutes.join('abc'),
      ]) {
        expect(redirect(path), isNull, reason: path);
      }
    });

    test('everything else goes to Welcome', () {
      for (final path in [
        SettloRoutes.splash,
        SettloRoutes.home,
        SettloRoutes.profile,
        SettloRoutes.spaces,
        SettloRoutes.space('s1'),
        SettloRoutes.spaceBalances('s1'),
        SettloRoutes.loans,
        SettloRoutes.newLoan,
        SettloRoutes.confirmRepayment('r1'),
        SettloRoutes.activity,
        SettloRoutes.addExpense,
        SettloRoutes.settle,
        SettloRoutes.settlePay,
      ]) {
        expect(redirect(path), SettloRoutes.welcome, reason: path);
      }
    });
  });

  group('signed in', () {
    String? redirect(String location) =>
        authRedirect(signedIn: true, location: location);

    test('Splash and sign-in steps go to Home', () {
      for (final path in [
        SettloRoutes.splash,
        SettloRoutes.welcome,
        SettloRoutes.phone,
        SettloRoutes.otp,
      ]) {
        expect(redirect(path), SettloRoutes.home, reason: path);
      }
    });

    test('app screens and invite links stay put', () {
      for (final path in [
        SettloRoutes.home,
        SettloRoutes.spaces,
        SettloRoutes.space('s1'),
        SettloRoutes.loans,
        SettloRoutes.activity,
        SettloRoutes.settle,
        SettloRoutes.join('abc'),
      ]) {
        expect(redirect(path), isNull, reason: path);
      }
    });
  });
}
