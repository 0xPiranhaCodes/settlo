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

  /// Profile over Home, for deep links and notifications.
  static const profile = '/home/profile';

  /// Profile over the current tab: `push` it, as `go` would leave nothing
  /// behind the sheet.
  static const profileSheet = '/profile';

  /// Spaces tab.
  static const spaces = '/spaces';

  /// A space's expenses; pattern for [space].
  static const spacePattern = '/spaces/:spaceId';

  /// A space's activity; pattern for [spaceActivity].
  static const spaceActivityPattern = '/spaces/:spaceId/activity';

  /// A space's balances; pattern for [spaceBalances].
  static const spaceBalancesPattern = '/spaces/:spaceId/balances';

  /// Confirm a settle-up as its payee; pattern for [confirmSettlement].
  static const confirmSettlementPattern =
      '/spaces/:spaceId/settle-ups/:expenseId';

  /// Loans tab.
  static const loans = '/loans';

  /// A loan's detail; pattern for [loan].
  static const loanPattern = '/loans/:loanId';

  /// New loan.
  static const newLoan = '/loans/new';

  /// Confirm a repayment; pattern for [confirmRepayment].
  static const confirmRepaymentPattern = '/loans/repayments/:repaymentId';

  /// Activity tab.
  static const activity = '/activity';

  /// Add expense.
  static const addExpense = '/expenses/new';

  /// Settle up: the simplified payments that involve you, and with
  /// `?space=&member=` the side that is owed ([settleWith]).
  static const settle = '/settle';

  /// Settle up, the side that pays ([settlePayTo]).
  static const settlePay = '/settle/pay';

  /// Paths a signed-out user may open.
  static const Set<String> signedOut = {welcome, phone, otp};

  /// The invite link for [token].
  static String join(String token) => '/join/$token';

  /// A space's expenses.
  static String space(String spaceId) => '/spaces/$spaceId';

  /// Add expense in the space [spaceId]. Without a space, [addExpense]
  /// asks which one when you have more than one.
  static String addExpenseIn(String spaceId) =>
      '$addExpense?space=${Uri.encodeQueryComponent(spaceId)}';

  /// Settle up: your payments in [spaceId] only, or with [memberId] the
  /// request to them (they pay you).
  static String settleWith(String spaceId, {String? memberId}) => Uri(
    path: settle,
    queryParameters: {'space': spaceId, 'member': ?memberId},
  ).toString();

  /// Paying [memberId] what you owe them in [spaceId].
  static String settlePayTo(String spaceId, String memberId) => Uri(
    path: settlePay,
    queryParameters: {'space': spaceId, 'member': memberId},
  ).toString();

  /// A space's activity.
  static String spaceActivity(String spaceId) => '/spaces/$spaceId/activity';

  /// A space's balances.
  static String spaceBalances(String spaceId) => '/spaces/$spaceId/balances';

  /// The pending settle-up [expenseId] in [spaceId], for its payee to
  /// confirm or dispute.
  static String confirmSettlement(String spaceId, String expenseId) =>
      '/spaces/$spaceId/settle-ups/$expenseId';

  /// Loan [loanId]: its progress, schedule and repayments.
  static String loan(String loanId) => '/loans/$loanId';

  /// The repayment [repaymentId], for the other party to confirm.
  static String confirmRepayment(String repaymentId) =>
      '/loans/repayments/$repaymentId';
}
