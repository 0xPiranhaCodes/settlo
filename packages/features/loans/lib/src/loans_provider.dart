import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

/// Your loans, reloaded whenever [ledgerRevisionProvider] is bumped, such
/// as by a recorded, confirmed or disputed repayment.
final FutureProvider<LoansData> loansProvider =
    FutureProvider.autoDispose<LoansData>((ref) {
      ref.watch(ledgerRevisionProvider);
      return ref.watch(loansRepositoryProvider).load();
    });

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `5 Dec`.
String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// `Jul 2029`.
String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

/// `5th`, `21st`, `22nd`, `23rd`.
String ordinal(int n) =>
    '$n${switch (n % 100) {
      11 || 12 || 13 => 'th',
      _ => switch (n % 10) {
        1 => 'st',
        2 => 'nd',
        3 => 'rd',
        _ => 'th',
      },
    }}';

/// Today's date in India, where loans are dated (docs/api.md). Tests
/// override this.
final Provider<DateTime> indiaTodayProvider = Provider.autoDispose<DateTime>((
  ref,
) {
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(ist.year, ist.month, ist.day);
});

/// The month of a monthly loan's last instalment: instalment k falls in
/// the k-th month after [start]'s, and there are principal ÷ instalment
/// of them, rounded up (`loan_summaries.ends_on`).
DateTime loanEndMonth(DateTime start, Paise principal, Paise installment) =>
    DateTime(
      start.year,
      start.month +
          (principal.value + installment.value - 1) ~/ installment.value,
    );
