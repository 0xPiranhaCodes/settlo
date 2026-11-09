/// Route paths for every screen. Features navigate to each other by these
/// paths through go_router, never by importing another feature's screen
/// (ADR 0002). The app builds the router from them.
abstract final class SettloRoutes {
  /// Splash: shown only until the auth guard sends the user on.
  static const splash = '/splash';

  /// Welcome, the signed-out entry point.
  static const welcome = '/welcome';

  /// Phone number entry.
  static const phone = '/welcome/phone';

  /// OTP entry.
  static const otp = '/welcome/phone/otp';

  /// Invitee joining from a WhatsApp link; pattern for [join].
  static const joinPattern = '/join/:token';

  /// Home tab.
  static const home = '/home';

  /// Profile, reached from Home.
  static const profile = '/home/profile';

  /// Spaces tab.
  static const spaces = '/spaces';

  /// A space's expenses; pattern for [space].
  static const spacePattern = '/spaces/:spaceId';

  /// A space's balances; pattern for [spaceBalances].
  static const spaceBalancesPattern = '/spaces/:spaceId/balances';

  /// Loans tab.
  static const loans = '/loans';

  /// New loan.
  static const newLoan = '/loans/new';

  /// Confirm a repayment; pattern for [confirmRepayment].
  static const confirmRepaymentPattern = '/loans/repayments/:repaymentId';

  /// Activity tab.
  static const activity = '/activity';

  /// Add expense.
  static const addExpense = '/expenses/new';

  /// Settle up, the side that is owed.
  static const settle = '/settle';

  /// Settle up, the side that pays.
  static const settlePay = '/settle/pay';

  /// Paths a signed-out user may open.
  static const Set<String> signedOut = {welcome, phone, otp};

  /// The invite link for [token].
  static String join(String token) => '/join/$token';

  /// A space's expenses.
  static String space(String spaceId) => '/spaces/$spaceId';

  /// A space's balances.
  static String spaceBalances(String spaceId) => '/spaces/$spaceId/balances';

  /// The repayment [repaymentId], for the other party to confirm.
  static String confirmRepayment(String repaymentId) =>
      '/loans/repayments/$repaymentId';
}
