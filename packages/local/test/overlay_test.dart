import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/settlo_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = 'u-me';
final _today = DateTime(2026, 11, 10, 9);

Map<String, dynamic> _expense(
  String id,
  int amount,
  String spentOn, {
  required Map<String, int> payers,
  required Map<String, int> splits,
  String? category,
  String? status,
}) => {
  'id': id,
  'space_id': 's1',
  'description': id,
  'category': category,
  'amount_minor': amount,
  'spent_on': spentOn,
  'is_settlement': status != null,
  'settlement_status': status,
  'dispute_reason': null,
  'created_by': _me,
  'deleted_at': null,
  'expense_payers': [
    for (final MapEntry(:key, :value) in payers.entries)
      {'member_id': key, 'amount_minor': value},
  ],
  'expense_splits': [
    for (final MapEntry(:key, :value) in splits.entries)
      {
        'member_id': key,
        'split_type': 'exact',
        'amount_minor': value,
        'space_members': {'created_at': key},
      },
  ],
};

/// Flat s1: Asha (m1, you), Rahul (m2), Priya (m3). Groceries (e1) and a
/// settle-up Rahul paid you (e2, pending) this month; Gas (e0) last month.
Tables _tables() => {
  'space_members': [
    for (final (id, user) in [('m1', _me), ('m2', 'u-r'), ('m3', null)])
      {'id': id, 'space_id': 's1', 'user_id': user, 'created_at': id},
    {'id': 'n1', 'space_id': 's2', 'user_id': _me, 'created_at': 'n1'},
    {'id': 'n2', 'space_id': 's2', 'user_id': null, 'created_at': 'n2'},
  ],
  'expenses': [
    _expense(
      'e2',
      500,
      '2026-11-06',
      payers: {'m2': 500},
      splits: {'m1': 500},
      status: 'pending',
    ),
    _expense(
      'e1',
      3000,
      '2026-11-05',
      category: 'food',
      payers: {'m1': 3000},
      splits: {'m1': 1000, 'm2': 1000, 'm3': 1000},
    ),
    _expense(
      'e0',
      600,
      '2026-10-20',
      payers: {'m2': 600},
      splits: {'m1': 300, 'm2': 300},
    ),
  ],
  'space_member_balances': [
    {'member_id': 'm1', 'paid_minor': 3000, 'balance_minor': 1700},
    {'member_id': 'm2', 'paid_minor': 600, 'balance_minor': -700},
    {'member_id': 'm3', 'paid_minor': 0, 'balance_minor': -1000},
  ],
  'space_monthly_fairness': [
    for (final (m, paid) in [('m1', 3000), ('m2', 0), ('m3', 0)])
      {
        'space_id': 's1',
        'member_id': m,
        'month': '2026-11-01',
        'paid_minor': paid,
        'fair_share_minor': 1000,
        'month_total_minor': 3000,
      },
  ],
  'space_monthly_categories': [
    {
      'space_id': 's1',
      'month': '2026-11-01',
      'category': 'food',
      'total_minor': 3000,
      'expense_count': 1,
    },
  ],
  'pending_settlements': [
    {
      'expense_id': 'e2',
      'space_id': 's1',
      'payer_member_id': 'm2',
      'payee_member_id': 'm1',
      'amount_minor': 500,
    },
  ],
};

Mutation _m(String kind, Map<String, dynamic> params, {String key = 'k'}) => (
  id: 1,
  key: key,
  kind: kind,
  params: params,
  createdAt: _today,
  attempts: 0,
  applied: false,
  result: const {},
);

Tables _apply(List<Mutation> queue) =>
    applyQueue(_tables(), queue, userId: _me, today: _today);

Map<Object?, (Object?, Object?)> _balances(Tables t) => {
  for (final b in t['space_member_balances']!)
    b['member_id']: (b['paid_minor'], b['balance_minor']),
};

Map<Object?, (Object?, Object?, Object?)> _fairness(Tables t) => {
  for (final f in t['space_monthly_fairness']!)
    f['member_id']: (
      f['paid_minor'],
      f['fair_share_minor'],
      f['month_total_minor'],
    ),
};

Map<Object?, (Object?, Object?)> _categories(Tables t) => {
  for (final c in t['space_monthly_categories']!)
    c['category']: (c['total_minor'], c['expense_count']),
};

Map<String, dynamic> _add(
  String space,
  int amount, {
  required Map<String, int> payers,
  required List<String> splits,
  String? spentOn,
  bool settlement = false,
}) => {
  'p': {
    'idempotency_key': 'k',
    'space_id': space,
    'description': 'New',
    'amount_minor': amount,
    'spent_on': ?spentOn,
    'split_type': settlement ? 'exact' : 'equal',
    if (settlement) 'is_settlement': true,
    'payers': [
      for (final MapEntry(:key, :value) in payers.entries)
        {'member_id': key, 'amount_minor': value},
    ],
    'splits': [
      for (final s in splits) {'member_id': s, 'amount_minor': amount},
    ],
  },
};

void main() {
  test('an edit takes the old expense out and puts the new one in', () {
    final t = _apply([
      _m('update_expense', {
        'p': {
          'expense_id': 'e1',
          'description': 'Rent',
          'category': 'rent',
          'amount_minor': 4000,
          'split_type': 'exact',
          'payers': [
            {'member_id': 'm2', 'amount_minor': 4000},
          ],
          'splits': [
            {'member_id': 'm1', 'amount_minor': 2000},
            {'member_id': 'm3', 'amount_minor': 2000},
          ],
        },
      }),
    ]);
    expect(_balances(t), {
      'm1': (0, -2300),
      'm2': (4600, 4300),
      'm3': (0, -2000),
    });
    expect(_fairness(t), {
      'm1': (0, 2000, 4000),
      'm2': (4000, 0, 4000),
      'm3': (0, 2000, 4000),
    });
    expect(_categories(t), {'rent': (4000, 1)});
    final rent = t['expenses']!.firstWhere((e) => e['id'] == 'e1');
    expect(rent['spent_on'], '2026-11-05');
    expect(rent['description'], 'Rent');
  });

  test('a delete stops an expense counting; last month leaves fairness', () {
    final t = _apply([
      _m('delete_expense', {'p_expense_id': 'e0'}),
    ]);
    expect(_balances(t), {
      'm1': (3000, 2000),
      'm2': (0, -1000),
      'm3': (0, -1000),
    });
    expect(_fairness(t), _fairness(_tables()));
    expect([for (final e in t['expenses']!) e['id']], ['e2', 'e1']);
  });

  test('a confirmed settle-up counts and is no longer pending', () {
    final t = _apply([
      _m('confirm_settlement', {'p_expense_id': 'e2'}),
    ]);
    expect(_balances(t)['m1'], (3000, 1200));
    expect(_balances(t)['m2'], (1100, -200));
    expect(t['pending_settlements'], isEmpty);
    expect(t['expenses']!.first['settlement_status'], 'confirmed');
  });

  test('a disputed settle-up never counts and keeps its reason', () {
    final t = _apply([
      _m('dispute_settlement', {
        'p_expense_id': 'e2',
        'p_reason': 'Not received',
      }),
    ]);
    expect(_balances(t), _balances(_tables()));
    expect(t['pending_settlements'], isEmpty);
    expect(t['expenses']!.first['settlement_status'], 'disputed');
    expect(t['expenses']!.first['dispute_reason'], 'Not received');
  });

  test('changes to what is gone or already answered change nothing', () {
    final t = _apply([
      _m('confirm_settlement', {'p_expense_id': 'e1'}),
      _m('dispute_settlement', {'p_expense_id': 'nope'}),
      _m('delete_expense', {'p_expense_id': 'nope'}),
      _m('update_expense', {
        'p': {'expense_id': 'nope'},
      }),
      _m('accept_claim', {}),
    ]);
    expect(t, _tables());
  });

  test('a settle-up you receive counts at once; one you pay waits', () {
    final t = _apply([
      _m(
        'add_expense',
        _add('s1', 200, payers: {'m2': 200}, splits: ['m1'], settlement: true),
        key: 'a',
      ),
      _m(
        'add_expense',
        _add('s1', 300, payers: {'m1': 300}, splits: ['m2'], settlement: true),
        key: 'b',
      ),
    ]);
    expect(_balances(t)['m1'], (3000, 1500));
    expect(_balances(t)['m2'], (800, -500));
    expect(
      [
        for (final p in t['pending_settlements']!)
          (p['expense_id'], p['payer_member_id'], p['amount_minor']),
      ],
      [('e2', 'm2', 500), ('local:b', 'm1', 300)],
    );
    expect(_fairness(t), _fairness(_tables()));
  });

  test('a first expense this month makes everyone a fairness row', () {
    final t = _apply([
      _m('add_expense', {
        'p': {
          'idempotency_key': 'k',
          'space_id': 's2',
          'description': 'Taxi',
          'amount_minor': 1001,
          'payers': [
            {'member_id': 'n2', 'amount_minor': 1001},
          ],
          'splits': [
            {'member_id': 'n1'},
            {'member_id': 'n2'},
          ],
        },
      }),
    ]);
    final s2 = {
      for (final f in t['space_monthly_fairness']!)
        if (f['space_id'] == 's2')
          f['member_id']: (
            f['paid_minor'],
            f['fair_share_minor'],
            f['month_total_minor'],
          ),
    };
    // Equal splits are recomputed: the odd paisa goes to the payer.
    expect(s2, {'n1': (0, 500, 1001), 'n2': (1001, 501, 1001)});
    expect(_categories(t)[null], (1001, 1));
    expect(t['expenses']!.first['spent_on'], '2026-11-10');
  });

  test('an expense from an earlier month lands in date order only', () {
    final t = _apply([
      _m(
        'add_expense',
        _add(
          's1',
          900,
          payers: {'m1': 900},
          splits: ['m1', 'm2', 'm3'],
          spentOn: '2026-09-01',
        ),
      ),
    ]);
    expect(
      [for (final e in t['expenses']!) e['id']],
      ['e2', 'e1', 'e0', 'local:k'],
    );
    expect(_fairness(t), _fairness(_tables()));
    expect(_balances(t)['m1'], (3900, 2300));
  });

  test('the refusal copy names the write and the reason', () {
    String copy(
      String kind,
      Map<String, dynamic> params,
      String? code, [
      String? hint,
    ]) => rejection(
      _m(kind, params),
      PostgrestException(message: '', code: code, hint: hint),
    );
    final expense = {
      'p': {'description': 'Dinner', 'amount_minor': 123456},
    };
    expect(
      copy('add_expense', expense, 'PT409'),
      '“Dinner” (₹1,234.56) couldn’t be saved because a different version of '
      'it was already saved. We’ve undone it on this phone.',
    );
    expect(
      copy('update_expense', expense, '22023', 'settlement_pending'),
      contains(
        'Your edit to “Dinner” couldn’t be saved because a settle-up '
        'between you is already waiting.',
      ),
    );
    expect(
      copy('confirm_settlement', {}, '22023', 'settlement_changed'),
      startsWith(
        'Your confirmation of that settle-up couldn’t be saved '
        'because the settle-up changed since you saw it.',
      ),
    );
    expect(
      copy('dispute_settlement', {}, '22023', 'settlement_final'),
      startsWith(
        'Your dispute of that settle-up couldn’t be saved because '
        'the settle-up was already answered.',
      ),
    );
    expect(
      copy('set_member_role', {}, '23514'),
      startsWith(
        'A change couldn’t be saved because the details didn’t '
        'match the space.',
      ),
    );
  });
}
