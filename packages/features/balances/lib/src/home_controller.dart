import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

/// Home's data, loaded through [homeRepositoryProvider].
final AsyncNotifierProvider<HomeController, HomeData> homeProvider =
    AsyncNotifierProvider<HomeController, HomeData>(HomeController.new);

/// Loads Home and settles claims. A settled claim reloads Home, so an
/// accepted one moves into the balances and a rejected one disappears.
/// Home also reloads when another tab bumps [ledgerRevisionProvider].
class HomeController extends AsyncNotifier<HomeData> {
  @override
  Future<HomeData> build() {
    ref.watch(ledgerRevisionProvider);
    return ref.watch(homeRepositoryProvider).load();
  }

  /// Accepts [claim]. Throws if the server refuses; Home is unchanged. A
  /// retry must pass the same [idempotencyKey].
  Future<void> accept(Claim claim, {required String idempotencyKey}) => _settle(
    () => ref
        .read(homeRepositoryProvider)
        .acceptClaim(claim, idempotencyKey: idempotencyKey),
  );

  /// 'This isn't me' for [claim]. Throws if the server refuses. A retry
  /// must pass the same [idempotencyKey].
  Future<void> reject(Claim claim, {required String idempotencyKey}) => _settle(
    () => ref
        .read(homeRepositoryProvider)
        .rejectClaim(claim, idempotencyKey: idempotencyKey),
  );

  Future<void> _settle(Future<void> Function() call) async {
    await call();
    ref.invalidateSelf();
    await future;
  }
}
