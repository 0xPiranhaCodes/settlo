import 'dart:async';

import 'package:settlo_core/settlo_core.dart';

/// The number the canvas shows on HomeFound.
const homePhone = '+919876543210';

/// The Main and HomeLight artboards: two spaces and one loan in November.
final homeMain = HomeData(
  phone: homePhone,
  name: 'Sana',
  month: DateTime(2026, 11),
  monthSpend: const Paise.rupees(18450),
  spaces: const [
    HomeSpace(
      id: 's1',
      name: 'Flat 402',
      kind: SpaceKind.flat,
      balance: Paise.rupees(2850),
      people: ['Rahul', 'Priya'],
    ),
    HomeSpace(
      id: 's2',
      name: 'Goa trip',
      kind: SpaceKind.trip,
      balance: Paise.rupees(-3650),
      people: ['Kabir', 'Meera', 'Dev', 'Isha'],
    ),
  ],
  loans: [
    HomeLoan(
      id: 'l1',
      counterparty: 'Arjun',
      youLent: true,
      outstanding: const Paise.rupees(675000),
      installment: const Paise.rupees(25000),
      installmentsPaid: 13,
      installmentsTotal: 40,
      nextDueOn: DateTime(2026, 12, 5),
      pendingRepaymentId: 'r3',
      pendingRepaymentAmount: const Paise.rupees(25000),
    ),
  ],
);

/// The HomeEmpty artboard: nothing recorded.
final homeEmpty = HomeData(
  phone: homePhone,
  name: 'Sana',
  month: DateTime(2026, 11),
);

/// The HomeFound artboard: two spaces and a loan recorded against the
/// number before it was verified.
final homeFound = HomeData(
  phone: homePhone,
  name: 'Sana',
  month: DateTime(2026, 11),
  claims: const [
    Claim(
      kind: ClaimKind.spaceMember,
      id: 'm1',
      title: 'Flat 402',
      recordedBy: 'Rahul',
      amount: Paise.rupees(-750),
      people: 3,
    ),
    Claim(
      kind: ClaimKind.spaceMember,
      id: 'm2',
      title: 'Goa trip',
      recordedBy: 'Kabir',
      amount: Paise.zero,
      people: 5,
    ),
    Claim(
      kind: ClaimKind.loan,
      id: 'l2',
      title: 'Arjun',
      recordedBy: 'Arjun',
      amount: Paise.rupees(1000000),
      youLent: true,
    ),
  ],
);

/// A [HomeRepository] over [data] that settles claims as the server would:
/// an accepted claim becomes a space or loan, a rejected one goes away.
class FakeHomeRepository implements HomeRepository {
  /// Serves [data].
  new(this.data);

  /// What [load] returns next.
  HomeData data;

  /// When set, every call throws it.
  Exception? failure;

  /// Claim calls, as `accept <id>` or `reject <id>`.
  final calls = <String>[];

  /// The idempotency key of each claim call, in order.
  final keys = <String>[];

  /// Holds every claim call open until completed, when set.
  Completer<void>? gate;

  @override
  Future<HomeData> load() async {
    if (failure case final e?) throw e;
    return data;
  }

  @override
  Future<void> acceptClaim(
    Claim claim, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    await gate?.future;
    if (failure case final e?) throw e;
    calls.add('accept ${claim.id}');
    data = _without(
      claim,
      spaces: [
        ...data.spaces,
        if (claim.kind == ClaimKind.spaceMember)
          HomeSpace(
            id: 's-${claim.id}',
            name: claim.title,
            kind: SpaceKind.flat,
            balance: claim.amount,
            people: [claim.recordedBy],
          ),
      ],
      loans: [
        ...data.loans,
        if (claim.kind == ClaimKind.loan)
          HomeLoan(
            id: claim.id,
            counterparty: claim.title,
            youLent: claim.youLent,
            outstanding: claim.amount,
          ),
      ],
    );
  }

  @override
  Future<void> rejectClaim(
    Claim claim, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    await gate?.future;
    if (failure case final e?) throw e;
    calls.add('reject ${claim.id}');
    data = _without(claim);
  }

  HomeData _without(
    Claim claim, {
    List<HomeSpace>? spaces,
    List<HomeLoan>? loans,
  }) => HomeData(
    phone: data.phone,
    name: data.name,
    month: data.month,
    monthSpend: data.monthSpend,
    spaces: spaces ?? data.spaces,
    loans: loans ?? data.loans,
    claims: [
      for (final c in data.claims)
        if (c.id != claim.id) c,
    ],
  );
}
