import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/supabase/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The owner's verified HTTPS host. Empty uses the custom-scheme fallback.
// shortcut: set SETTLO_INVITE_HOST to the owner's domain, then add
// universal/app-link entitlements.
const inviteHttpsHost = String.fromEnvironment('SETTLO_INVITE_HOST');

/// Builds the link put in WhatsApp. Until [inviteHttpsHost] is configured it
/// is `settlo://join/<token>`.
Uri inviteLink(String token) => inviteHttpsHost.isEmpty
    ? Uri(scheme: 'settlo', host: 'join', path: '/$token')
    : Uri.https(inviteHttpsHost, '/join/$token');

/// The only facts a bearer token exposes before phone verification.
@immutable
final class InvitePreview {
  /// Creates the minimal pre-verification copy.
  const new({
    required this.kind,
    required this.inviterName,
    required this.subjectName,
    required this.maskedPhone,
  });

  /// `space` or `loan`.
  final String kind;

  /// The profile name of the person who issued the invite.
  final String inviterName;

  /// The space name or privacy-safe loan label.
  final String subjectName;

  /// The target with only a prefix and final digits visible.
  final String maskedPhone;
}

/// Invite capability operations. Widgets depend on this seam, not Supabase.
abstract interface class InvitesRepository {
  /// Returns privacy-safe copy, or null when the token is unavailable.
  Future<InvitePreview?> inspect(String token);

  /// Issues a capability for a pending space member.
  Future<String> issueSpace(String memberId, {required String idempotencyKey});

  /// Issues a capability for the pending opposite side of a loan.
  Future<String> issueLoan(String loanId, {required String idempotencyKey});

  /// Accepts the targeted claim and consumes the capability.
  Future<void> redeem(String token, {required String idempotencyKey});

  /// Rejects the targeted claim and consumes the capability.
  Future<void> decline(String token);
}

/// [InvitesRepository] implemented by the invite RPCs.
final class SupabaseInvitesRepository implements InvitesRepository {
  /// Creates an adapter over [_db].
  const new(this._db);

  final SupabaseClient _db;

  @override
  Future<InvitePreview?> inspect(String token) async {
    final rows = await _db.rpc<List<dynamic>>(
      'inspect_invite',
      params: {'p_token': token},
    );
    if (rows.isEmpty) return null;
    final row = rows.single as Map<String, dynamic>;
    return InvitePreview(
      kind: row['kind'] as String,
      inviterName: row['inviter_name'] as String,
      subjectName: row['subject_name'] as String,
      maskedPhone: row['masked_phone'] as String,
    );
  }

  Future<String> _issue(String kind, String subjectId, String idempotencyKey) =>
      _db.rpc<String>(
        'issue_invite',
        params: {
          'p_kind': kind,
          'p_subject_id': subjectId,
          'p_idempotency_key': idempotencyKey,
        },
      );

  @override
  Future<String> issueSpace(
    String memberId, {
    required String idempotencyKey,
  }) => _issue('space', memberId, idempotencyKey);

  @override
  Future<String> issueLoan(String loanId, {required String idempotencyKey}) =>
      _issue('loan', loanId, idempotencyKey);

  @override
  Future<void> redeem(String token, {required String idempotencyKey}) =>
      _db.rpc<void>(
        'redeem_invite',
        params: {'p_token': token, 'p_idempotency_key': idempotencyKey},
      );

  @override
  Future<void> decline(String token) =>
      _db.rpc<void>('decline_invite', params: {'p_token': token});
}

/// Invite operations through the configured Supabase client.
final invitesRepositoryProvider = Provider<InvitesRepository>(
  (ref) => SupabaseInvitesRepository(ref.watch(supabaseClientProvider)),
);

/// An invite waiting for phone verification, including its stable replay key.
@immutable
final class PendingInvite {
  /// Creates a pending invite.
  const new({required this.token, required this.idempotencyKey});

  /// The bearer token from the incoming link.
  final String token;

  /// The key reused if OTP completion retries after an ambiguous response.
  final String idempotencyKey;
}

/// The invite that led into phone verification, consumed after OTP success.
final pendingInviteTokenProvider =
    NotifierProvider<PendingInviteToken, PendingInvite?>(
      PendingInviteToken.new,
    );

/// Remembers an invite while phone and OTP screens replace Join.
final class PendingInviteToken extends Notifier<PendingInvite?> {
  /// Starts without an invite.
  @override
  PendingInvite? build() => null;

  /// Remembers a token and the idempotency key for its eventual redemption.
  void remember(String token, {required String idempotencyKey}) =>
      state = PendingInvite(token: token, idempotencyKey: idempotencyKey);

  /// Clears the pending invite after successful redemption.
  void clear() => state = null;
}
