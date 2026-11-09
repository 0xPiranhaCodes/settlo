import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

/// Feed entries per page.
const activityPageSize = 30;

/// What waits for your answer, reloaded whenever [ledgerRevisionProvider]
/// is bumped, such as by a confirmed settle-up or repayment.
final FutureProvider<List<PendingAnswer>> needsYouProvider =
    FutureProvider.autoDispose<List<PendingAnswer>>((ref) {
      ref.watch(ledgerRevisionProvider);
      return ref.watch(activityRepositoryProvider).needsYou();
    });

/// The feed loaded so far, newest first.
@immutable
final class ActivityFeed {
  /// [entries], and whether older ones remain.
  const new(this.entries, {required this.hasMore});

  /// Loaded entries, newest first.
  final List<ActivityEntry> entries;

  /// Whether a full page came back last time, so there may be older ones.
  final bool hasMore;
}

/// The feed, a page at a time; starts over whenever
/// [ledgerRevisionProvider] is bumped.
final AsyncNotifierProvider<ActivityFeedController, ActivityFeed>
activityFeedProvider = AsyncNotifierProvider.autoDispose(
  ActivityFeedController.new,
);

/// Loads the first page, then older pages on demand (keyset on time and
/// id).
class ActivityFeedController extends AsyncNotifier<ActivityFeed> {
  bool _loadingMore = false;

  @override
  Future<ActivityFeed> build() async {
    ref.watch(ledgerRevisionProvider);
    final page = await ref
        .watch(activityRepositoryProvider)
        .feed(limit: activityPageSize);
    return ActivityFeed(page, hasMore: page.length == activityPageSize);
  }

  /// Appends the page after the last entry, once at a time.
  Future<void> loadMore() async {
    final feed = state.value;
    if (_loadingMore || feed == null || !feed.hasMore || state.isLoading) {
      return;
    }
    _loadingMore = true;
    try {
      final page = await ref
          .read(activityRepositoryProvider)
          .feed(before: feed.entries.last, limit: activityPageSize);
      // A reload started meanwhile replaces the feed; drop this page.
      if (!ref.mounted || !identical(state.value, feed)) return;
      state = AsyncData(
        ActivityFeed([
          ...feed.entries,
          ...page,
        ], hasMore: page.length == activityPageSize),
      );
    } on Exception {
      // Pulling down reloads; the next scroll to the end tries again.
    } finally {
      _loadingMore = false;
    }
  }
}

/// Now, which dates the feed's sections. Tests override this.
final Provider<DateTime> activityNowProvider = Provider.autoDispose(
  (ref) => DateTime.now(),
);
