import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/settlo_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_server.dart';

const _me = 'u-me';

final class _Session extends SessionNotifier {
  @override
  Session? build() => _session(_me);

  void signOut() => state = null;

  void signIn(String id) => state = _session(id);

  static Session _session(String id) => Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-11-01T00:00:00Z',
    ),
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding fakes HTTP; these tests talk to a loopback server.
  HttpOverrides.global = null;

  late FakeServer server;
  late LocalDb db;
  late ProviderContainer container;
  late int reads;

  setUp(() async {
    reads = 0;
    server = FakeServer()..onRead = () => reads++;
    await server.start();
    server.tables['profiles'] = [
      {'id': _me, 'name': 'Asha', 'phone': '+919000000001'},
    ];
    db = LocalDb(NativeDatabase.memory());
    await db.enqueue(
      'u-before',
      'k0',
      'delete_expense',
      const {},
      DateTime(2026),
    );
    container = ProviderContainer(
      overrides: [
        localDbProvider.overrideWithValue(db),
        supabaseClientProvider.overrideWithValue(server.client),
        sessionProvider.overrideWith(_Session.new),
        ...offlineRepositories,
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await server.stop();
  });

  test('the signed-in user syncs on start, with the mirror behind every '
      'repository', () async {
    final engine = container.read(syncEngineProvider)!;
    await engine.sync();
    expect(await db.mutations('u-before'), isEmpty);
    expect(container.read(ledgerRevisionProvider), greaterThan(0));
    expect(container.read(homeRepositoryProvider), isA<DriftHomeRepository>());
    expect(
      container.read(spacesRepositoryProvider),
      isA<DriftSpacesRepository>(),
    );
    expect(
      container.read(expensesRepositoryProvider),
      isA<DriftExpensesRepository>(),
    );
    expect(
      container.read(loansRepositoryProvider),
      isA<DriftLoansRepository>(),
    );
    expect(
      container.read(activityRepositoryProvider),
      isA<DriftActivityRepository>(),
    );
    expect(
      container.read(spaceLedgerRepositoryProvider),
      isA<DriftSpaceLedgerRepository>(),
    );
    expect((await container.read(homeRepositoryProvider).load()).name, 'Asha');
  });

  test('a refusal reaches the notices', () async {
    final notices = <String>[];
    container.listen(
      syncNoticesProvider,
      (_, next) => notices.add(next.requireValue),
    );
    final engine = container.read(syncEngineProvider)!;
    server.rpc = (_, _) => const Refuse(null, status: 503);
    await container
        .read(spaceLedgerRepositoryProvider)
        .deleteExpense('e1', idempotencyKey: 'k1');
    server.rpc = (_, _) => const Refuse('22023', hint: 'departed_member');
    await engine.sync();
    await pumpEventQueue();
    expect(
      notices.single,
      'Deleting that expense couldn’t be saved because someone in it has '
      'left the space. We’ve undone it on this phone.',
    );
  });

  test('coming back to the app syncs', () async {
    final engine = container.read(syncEngineProvider)!;
    await engine.sync();
    final before = reads;
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await engine.sync();
    expect(reads, greaterThan(before));
  });

  test('a write made online elsewhere refreshes the mirror', () async {
    final engine = container.read(syncEngineProvider)!;
    await engine.sync();
    final revision = container.read(ledgerRevisionProvider);
    server.tables['profiles']!.first['name'] = 'Asha K';
    container.read(ledgerRevisionProvider.notifier).bump();
    await engine.sync();
    expect(
      (await container.read(homeRepositoryProvider).load()).name,
      'Asha K',
    );
    // One bump from the write, one back from the changed mirror, and no
    // more: an unchanged refresh does not bump.
    await engine.sync();
    expect(container.read(ledgerRevisionProvider), revision + 2);
  });

  test(
    'unsent changes are counted and can be sent before signing out',
    () async {
      final engine = container.read(syncEngineProvider)!;
      await engine.sync();
      server.rpc = (_, _) => const Refuse(null, status: 503);
      await db.enqueue(_me, 'k1', 'delete_expense', const {
        'p_expense_id': 'e1',
        'p_idempotency_key': 'k1',
      }, DateTime(2026));
      final unsent = container.read(unsentChangesProvider)!;
      expect(await unsent.count(), 1);

      server.rpc = (_, _) => null;
      await unsent.drain();
      expect(server.calls.last.$1, 'delete_expense');
      expect(await unsent.count(), 0);

      // Signed out, nothing is queued and nothing asks.
      (container.read(sessionProvider.notifier) as _Session).signOut();
      expect(container.read(unsentChangesProvider), isNull);
      await pumpEventQueue();
    },
  );

  // A `create_space` of [_me]'s whose answer the server holds until the
  // returned completer completes; the sync that sent it is in flight.
  Future<(Completer<Object?>, Future<void>)> heldReplay() async {
    final engine = container.read(syncEngineProvider)!;
    await engine.sync();
    final held = Completer<Object?>();
    final sent = Completer<void>();
    server
      ..tables['space_members'] = [
        {'id': 'member-server', 'space_id': 'k1', 'user_id': _me},
      ]
      ..rpc = (_, _) {
        sent.complete();
        return held.future;
      };
    await db.enqueue(_me, 'k1', 'create_space', const {
      'p_name': 'Flat 7C',
    }, DateTime(2026));
    final replay = engine.sync();
    await sent.future;
    return (held, replay);
  }

  Future<int> rows(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  test('a replay answered after signing out writes nothing', () async {
    final (held, replay) = await heldReplay();
    (container.read(sessionProvider.notifier) as _Session).signOut();
    expect(container.read(syncEngineProvider), isNull);
    await pumpEventQueue();
    held.complete('k1');
    await replay;
    await pumpEventQueue();
    expect(await db.localIds(_me), isEmpty);
    for (final table in ['local_ids', 'pending_mutations', 'mirror']) {
      expect(await rows(table), 0, reason: table);
    }
  });

  test('a replay answered after another user signed in leaves them none of '
      'the last user’s rows', () async {
    final (held, replay) = await heldReplay();
    final session = container.read(sessionProvider.notifier) as _Session
      ..signOut();
    expect(container.read(syncEngineProvider), isNull);
    session.signIn('u-b');
    final next = container.read(syncEngineProvider)!;
    expect(next.owner, 'u-b');
    await db.keepOnly('u-b');
    await pumpEventQueue();
    held.complete('k1');
    await replay;
    await next.sync();
    await pumpEventQueue();
    expect(await db.localIds(_me), isEmpty);
    expect(await db.mutations(_me), isEmpty);
    expect(await db.mirror(_me), isEmpty);
    expect(await rows('local_ids'), 0);
  });

  test('signing out deletes everything and stops syncing', () async {
    await container.read(syncEngineProvider)!.sync();
    expect(await db.mirror(_me), isNotEmpty);
    (container.read(sessionProvider.notifier) as _Session).signOut();
    expect(container.read(syncEngineProvider), isNull);
    await pumpEventQueue();
    expect(await db.mirror(_me), isEmpty);
    expect(
      () => container.read(homeRepositoryProvider),
      throwsA(predicate((e) => '$e'.contains('needs a signed-in user'))),
    );
    expect(
      await container
          .read(syncNoticesProvider.future)
          .timeout(Duration.zero, onTimeout: () => 'none'),
      'none',
    );
  });
}
