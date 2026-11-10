import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

/// The channel the iOS Live Activity and the Android ongoing notification
/// answer on (ADR 0012).
const liveActivityChannel = MethodChannel('app.settlo/live_activity');

/// A settle-up waiting for you to confirm it, as the Dynamic Island, the
/// lock screen and the Android notification show it (canvas LiveActivity).
@immutable
final class SettleUpActivity {
  /// The settle-up [id] in [spaceId], paid by [payer].
  const new({
    required this.id,
    required this.spaceId,
    required this.spaceName,
    required this.payer,
    required this.amount,
    required this.recordedAt,
  });

  /// The settle-up's expense id.
  final String id;

  /// Its space.
  final String spaceId;

  /// Its space's name.
  final String spaceName;

  /// Who says they paid you: their name or number.
  final String payer;

  /// How much.
  final Paise amount;

  /// When it was recorded.
  final DateTime recordedAt;

  /// The confirm sheet; the Confirm button deep-links here.
  String get confirmPath => SettloRoutes.confirmSettlement(spaceId, id);

  /// What the native side draws; amounts arrive formatted.
  Map<String, Object> toChannel() => {
    'id': id,
    'space': spaceName,
    'payer': payer,
    'amount': formatInr(amount),
    'recordedAtMs': recordedAt.millisecondsSinceEpoch,
    'path': confirmPath,
  };

  @override
  bool operator ==(Object other) =>
      other is SettleUpActivity &&
      other.id == id &&
      other.spaceId == spaceId &&
      other.spaceName == spaceName &&
      other.payer == payer &&
      other.amount == amount &&
      other.recordedAt == recordedAt;

  @override
  int get hashCode =>
      Object.hash(id, spaceId, spaceName, payer, amount, recordedAt);
}

/// The settle-up to show from what waits for your answer: the newest one,
/// or null when none does. Repayments are not a Live Activity state (n32).
SettleUpActivity? settleUpActivityFor(Iterable<PendingAnswer> pending) {
  PendingAnswer? newest;
  for (final p in pending) {
    if (p.isRepayment || p.spaceId == null) continue;
    if (newest == null || p.recordedAt.isAfter(newest.recordedAt)) newest = p;
  }
  if (newest == null) return null;
  return SettleUpActivity(
    id: newest.id,
    spaceId: newest.spaceId!,
    spaceName: newest.spaceName ?? '',
    payer: newest.counterparty,
    amount: newest.amount,
    recordedAt: newest.recordedAt,
  );
}

/// Starts, updates and ends the one Live Activity (iOS) or ongoing
/// notification (Android). Driven from app state; no push in v1.
class LiveActivities {
  /// Talks to the native side over [channel].
  const new({this.channel = liveActivityChannel});

  /// The native side.
  final MethodChannel channel;

  /// Shows [activity], replacing whatever was shown, or ends it when null.
  Future<void> show(SettleUpActivity? activity) =>
      _call(activity == null ? 'end' : 'show', activity?.toChannel());

  /// Asks for permission to post notifications where the OS needs it
  /// (Android 13+). True when allowed.
  Future<bool> requestPermission() async =>
      await _call<bool>('requestPermission') ?? true;

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // No native side on this platform (or in widget tests).
      return null;
    }
  }
}

/// The app's [LiveActivities]. Tests override this.
final liveActivitiesProvider = Provider<LiveActivities>(
  (ref) => const LiveActivities(),
);
