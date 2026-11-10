import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';

/// Mirrors the newest settle-up awaiting you into the Live Activity (iOS)
/// or ongoing notification (Android), and ends it once nothing waits, you
/// sign out or another user signs in. No push in v1: it follows
/// [needsYouProvider], which reloads after your own answers and whenever
/// the app comes back.
final Provider<void> liveActivitySyncProvider = Provider.autoDispose<void>((
  ref,
) {
  final activities = ref.watch(liveActivitiesProvider);
  // A new user (or none) ends the last one's activity before anything else
  // shows, so A's settle-up never sits on B's lock screen.
  unawaited(activities.show(null));
  if (ref.watch(sessionProvider.select((s) => s?.user.id)) == null) return;
  final lifecycle = AppLifecycleListener(
    onResume: () => ref.invalidate(needsYouProvider),
  );
  ref
    ..onDispose(lifecycle.dispose)
    ..listen(needsYouProvider, (_, next) {
      // On an error keep showing what was last known.
      if (next case AsyncData(:final value)) {
        unawaited(activities.show(settleUpActivityFor(value)));
      }
    }, fireImmediately: true);
});

/// Feed entries per page.
const activityPageSize = 30;

/// What waits for your answer, reloaded whenever [ledgerRevisionProvider]
/// is bumped, such as by a confirmed settle-up or repayment, and whenever
/// the signed-in user changes.
final FutureProvider<List<PendingAnswer>> needsYouProvider =
    FutureProvider.autoDispose<List<PendingAnswer>>((ref) {
      ref
        ..watch(ledgerRevisionProvider)
        // Another user's answers are never served from this cache.
        ..watch(sessionProvider.select((s) => s?.user.id));
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
