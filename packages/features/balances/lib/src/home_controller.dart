import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

/// Home's data, loaded through [homeRepositoryProvider].
final AsyncNotifierProvider<HomeController, HomeData> homeProvider =
    AsyncNotifierProvider<HomeController, HomeData>(HomeController.new);

/// Loads Home and settles claims. A settled claim reloads Home, so an
/// accepted one moves into the balances and a rejected one disappears.
class HomeController extends AsyncNotifier<HomeData> {
  @override
  Future<HomeData> build() => ref.watch(homeRepositoryProvider).load();

  /// Accepts [claim]. Throws if the server refuses; Home is unchanged.
  Future<void> accept(Claim claim) =>
      _settle(() => ref.read(homeRepositoryProvider).acceptClaim(claim));

  /// 'This isn't me' for [claim]. Throws if the server refuses.
  Future<void> reject(Claim claim) =>
      _settle(() => ref.read(homeRepositoryProvider).rejectClaim(claim));

  Future<void> _settle(Future<void> Function() call) async {
    await call();
    ref.invalidateSelf();
    await future;
  }
}
