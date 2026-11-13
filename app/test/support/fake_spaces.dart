import 'package:settlo_core/settlo_core.dart';

/// The SpacesList artboard: Flat 402 with this month's paid bar, Goa trip
/// with Kabir not joined yet, and a settled 1:1 with Meera.
final spacesList = [
  SpaceSummary(
    id: 's1',
    name: 'Flat 402',
    kind: SpaceKind.flat,
    month: DateTime(2026, 11),
    monthTotal: const Paise.rupees(18450),
    yourFairShare: const Paise.rupees(6150),
    hasExpenses: true,
    members: const [
      SpaceMember(
        id: 'm1',
        name: 'Sana',
        phone: '+919876543210',
        isYou: true,
        isOwner: true,
        balance: Paise.rupees(2850),
        monthPaid: Paise.rupees(9000),
      ),
      SpaceMember(
        id: 'm2',
        name: 'Rahul',
        phone: '+919811100044',
        balance: Paise.rupees(-1400),
        monthPaid: Paise.rupees(5400),
      ),
      SpaceMember(
        id: 'm3',
        name: 'Priya',
        phone: '+919900000010',
        balance: Paise.rupees(-1450),
        monthPaid: Paise.rupees(4050),
      ),
    ],
  ),
  SpaceSummary(
    id: 's2',
    name: 'Goa trip',
    kind: SpaceKind.trip,
    month: DateTime(2026, 11),
    hasExpenses: true,
    members: const [
      SpaceMember(
        id: 'm4',
        name: 'Sana',
        phone: '+919876543210',
        isYou: true,
        balance: Paise.rupees(-3650),
      ),
      SpaceMember(
        id: 'm5',
        name: 'Kabir',
        phone: '+919800002210',
        joined: false,
        balance: Paise.rupees(1200),
      ),
      SpaceMember(id: 'm6', name: 'Meera', phone: '+919100000006'),
      SpaceMember(id: 'm7', name: 'Dev', phone: '+919100000007'),
      SpaceMember(
        id: 'm8',
        name: 'Isha',
        phone: '+919100000008',
        isOwner: true,
        balance: Paise.rupees(2450),
      ),
    ],
  ),
  SpaceSummary(
    id: 's3',
    name: 'Meera',
    kind: SpaceKind.friend,
    month: DateTime(2026, 11),
    hasExpenses: true,
    members: const [
      SpaceMember(
        id: 'm9',
        name: 'Sana',
        phone: '+919876543210',
        isYou: true,
        isOwner: true,
      ),
      SpaceMember(id: 'm10', name: 'Meera', phone: '+919100000006'),
    ],
  ),
];

/// The SpaceEmpty artboard: Flat 402 on its first day, Rahul and Priya
/// not joined yet.
final spaceEmpty = SpaceSummary(
  id: 's9',
  name: 'Flat 402',
  kind: SpaceKind.flat,
  month: DateTime(2026, 11),
  members: const [
    SpaceMember(
      id: 'm1',
      name: 'Sana',
      phone: '+919876543210',
      isYou: true,
      isOwner: true,
    ),
    SpaceMember(id: 'm2', name: 'Rahul', phone: '+919811100044', joined: false),
    SpaceMember(id: 'm3', name: 'Priya', phone: '+919900000010', joined: false),
  ],
);

/// A space whose only payer left this month and you paid nothing: it is
/// not empty, and its paid bar still shows the departed payer.
final spaceDepartedPayer = SpaceSummary(
  id: 's7',
  name: 'Old flat',
  kind: SpaceKind.flat,
  month: DateTime(2026, 11),
  monthTotal: const Paise(100000),
  yourFairShare: const Paise(66667),
  hasExpenses: true,
  members: const [
    SpaceMember(
      id: 'm1',
      name: 'Sana',
      phone: '+919876543210',
      isYou: true,
      isOwner: true,
      balance: Paise(-66667),
    ),
  ],
  departed: const [
    SpaceMember(
      id: 'm2',
      name: 'Arun',
      phone: '+919100000002',
      balance: Paise(66667),
      monthPaid: Paise(100000),
    ),
  ],
);

/// A [SpacesRepository] over [spaces] that creates spaces as the server
/// would: a replayed key returns the first id and adds nothing.
class FakeSpacesRepository implements SpacesRepository {
  /// Serves [spaces].
  new(List<SpaceSummary> spaces) : spaces = [...spaces];

  /// What [load] returns next.
  final List<SpaceSummary> spaces;

  /// When set, [load] and [create] throw it, once.
  Exception? failure;

  /// Every [create] call, as `<key> <name> <phones>`.
  final calls = <String>[];

  final _created = <String, String>{};

  @override
  Future<List<SpaceSummary>> load() async {
    if (failure case final e?) {
      failure = null;
      throw e;
    }
    return List.of(spaces);
  }

  @override
  Future<String> create({
    required String name,
    required SpaceKind kind,
    required List<NewSpaceMember> members,
    required String idempotencyKey,
  }) async {
    calls.add(
      '$idempotencyKey $name ${[for (final m in members) m.phone].join(',')}',
    );
    if (failure case final e?) {
      failure = null;
      throw e;
    }
    if (_created[idempotencyKey] case final id?) return id;
    final id = 's-new-${_created.length}';
    _created[idempotencyKey] = id;
    spaces.add(
      SpaceSummary(
        id: id,
        name: name,
        kind: kind,
        month: DateTime(2026, 11),
        members: [
          const SpaceMember(
            id: 'me',
            name: 'Sana',
            phone: '+919876543210',
            isYou: true,
            isOwner: true,
          ),
          for (final m in members)
            SpaceMember(
              id: m.phone,
              name: m.name,
              phone: m.phone,
              joined: false,
            ),
        ],
      ),
    );
    return id;
  }

  /// Every [addMembers] call, as `<key> <space id> <phones>`.
  final added = <String>[];

  @override
  Future<void> addMembers(
    String spaceId,
    List<NewSpaceMember> members, {
    required String idempotencyKey,
  }) async {
    final phones = [for (final m in members) m.phone];
    added.add('$idempotencyKey $spaceId ${phones.join(',')}');
    if (failure case final e?) {
      failure = null;
      throw e;
    }
    final i = spaces.indexWhere((s) => s.id == spaceId);
    final s = spaces[i];
    spaces[i] = SpaceSummary(
      id: s.id,
      name: s.name,
      kind: s.kind,
      month: s.month,
      monthTotal: s.monthTotal,
      yourFairShare: s.yourFairShare,
      hasExpenses: s.hasExpenses,
      departed: s.departed,
      pendingFromYou: s.pendingFromYou,
      members: [
        ...s.members,
        for (final m in members)
          SpaceMember(id: m.phone, name: m.name, phone: m.phone, joined: false),
      ],
    );
  }
}
