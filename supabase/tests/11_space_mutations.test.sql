-- Space and expense mutations (#59): update_expense, delete_expense, add_space_members,
-- leave_space, update_profile, and the tightened expense policies.
-- Callers: A owns space S, B is a member who creates expense E1, E is a plain member, C is an
-- outsider, D has an unverified phone. X is a number on S with no account.
begin;
create extension if not exists pgtap with schema extensions;

select plan(68);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000005901', '919590000001', now()),
  ('00000000-0000-0000-0000-000000005902', '919590000002', now()),
  ('00000000-0000-0000-0000-000000005903', '919590000003', now()),
  ('00000000-0000-0000-0000-000000005904', '919590000004', null),
  ('00000000-0000-0000-0000-000000005905', '919590000005', now());
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000005901', '+919590000001', 'Asha'),
  ('00000000-0000-0000-0000-000000005902', '+919590000002', 'Bilal'),
  ('00000000-0000-0000-0000-000000005903', '+919590000003', 'Chitra'),
  ('00000000-0000-0000-0000-000000005905', '+919590000005', 'Esha');
insert into public.spaces (id, name, kind, created_by) values
  ('00000000-0000-0000-0000-000000005910', 'Flat 9', 'flat', '00000000-0000-0000-0000-000000005901');
insert into public.space_members (id, space_id, phone, user_id, role) values
  ('00000000-0000-0000-0000-000000005921', '00000000-0000-0000-0000-000000005910', '+919590000001', '00000000-0000-0000-0000-000000005901', 'owner'),
  ('00000000-0000-0000-0000-000000005922', '00000000-0000-0000-0000-000000005910', '+919590000002', '00000000-0000-0000-0000-000000005902', 'member'),
  ('00000000-0000-0000-0000-000000005923', '00000000-0000-0000-0000-000000005910', '+919590000009', null, 'member'),
  ('00000000-0000-0000-0000-000000005925', '00000000-0000-0000-0000-000000005910', '+919590000005', '00000000-0000-0000-0000-000000005905', 'member');

create function pg_temp.login(u text) returns text language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true)
$$;
-- The SQLSTATE hint an RPC raises, for the codes clients branch on.
create function pg_temp.hint_of(q text) returns text language plpgsql as $$
declare
  h text;
begin
  execute q;
  return null;
exception when others then
  get stacked diagnostics h = pg_exception_hint;
  return h;
end $$;
create function pg_temp.affected(q text) returns int language plpgsql as $$
declare
  n int;
begin
  execute q;
  get diagnostics n = row_count;
  return n;
end $$;
-- E1's id, filled in once B has created it; readable by every caller.
create temp table e1 (id uuid);
grant select on e1 to public;
-- update_expense payload for E1.
create function pg_temp.edit(key text, amount bigint, description text, payers jsonb, splits jsonb,
                             split_type text default 'exact') returns jsonb language sql as $$
  select jsonb_build_object('expense_id', (select id from pg_temp.e1), 'idempotency_key', key,
                            'description', description, 'amount_minor', amount, 'split_type', split_type,
                            'payers', payers, 'splits', splits)
$$;
create function pg_temp.balances() returns table (member_id uuid, balance_minor bigint) language sql as $$
  select member_id, balance_minor from public.space_member_balances
   where space_id = '00000000-0000-0000-0000-000000005910' order by member_id
$$;
grant execute on all functions in schema pg_temp to public;

-- Hardening.
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('update_expense', 'delete_expense', 'add_space_members', 'leave_space', 'update_profile',
                        'claim_idempotency_key', 'normalise_expense', 'resolve_allocations', 'store_allocations',
                        'can_edit_expense')
      and (not coalesce(p.proconfig @> array['search_path=""'], false)
           or has_function_privilege('anon', p.oid, 'execute')
           or not has_function_privilege('authenticated', p.oid, 'execute'))),
  null,
  'new RPCs and helpers have a fixed search_path and are executable by authenticated only');
select ok(
  not exists (select from pg_proc p, aclexplode(p.proacl) a
               where p.pronamespace = 'public'::regnamespace and a.grantee = 0
                 and p.proname in ('update_expense', 'delete_expense', 'add_space_members', 'leave_space',
                                   'update_profile', 'claim_idempotency_key', 'normalise_expense',
                                   'resolve_allocations', 'store_allocations', 'can_edit_expense')),
  'new RPCs and helpers are revoked from public');
select ok(
  not has_table_privilege('authenticated', 'private.idempotency_keys', 'select, insert, update, delete'),
  'clients have no access to the idempotency keys');

set local role anon;
select throws_ok($$select public.update_expense('{}')$$, '42501', null, 'anon cannot call update_expense');
select throws_ok($$select public.leave_space(gen_random_uuid(), gen_random_uuid())$$, '42501', null,
  'anon cannot call leave_space');
select throws_ok($$select public.update_profile('x', null)$$, '42501', null, 'anon cannot call update_profile');
reset role;

-- B adds E1: 9000 paid by B, split equally between A, B and X.
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000005902');
select isnt(public.add_expense('{"space_id": "00000000-0000-0000-0000-000000005910",
  "idempotency_key": "00000000-0000-0000-0000-000000005931", "description": "Groceries", "amount_minor": 9000,
  "payers": [{"member_id": "00000000-0000-0000-0000-000000005922", "amount_minor": 9000}],
  "splits": [{"member_id": "00000000-0000-0000-0000-000000005921"}, {"member_id": "00000000-0000-0000-0000-000000005922"},
             {"member_id": "00000000-0000-0000-0000-000000005923"}]}'), null, 'fixture: B adds E1 through add_expense');
reset role;
insert into e1 select id from public.expenses where idempotency_key = '00000000-0000-0000-0000-000000005931';
set local role authenticated;

-- update_expense
select pg_temp.login('00000000-0000-0000-0000-000000005901');
select is(
  public.update_expense(pg_temp.edit('00000000-0000-0000-0000-000000005941', 12000, 'Groceries and gas',
    '[{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 12000}]',
    '[{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 6000},
      {"member_id": "00000000-0000-0000-0000-000000005922", "amount_minor": 6000}]')),
  (select id from e1), 'update_expense: owner A edits B''s expense and gets its id back');
select results_eq(
  $$select e.description, e.amount_minor, (select array_agg(s.amount_minor order by s.member_id) from public.expense_splits s
                                           where s.expense_id = e.id)
      from public.expenses e where e.id = (select id from pg_temp.e1)$$,
  $$values ('Groceries and gas', 12000::bigint, array[6000, 6000]::bigint[])$$,
  'update_expense: fields, payers and splits are replaced');
select results_eq('select * from pg_temp.balances()',
  $$values ('00000000-0000-0000-0000-000000005921'::uuid, 6000::bigint), ('00000000-0000-0000-0000-000000005922', -6000),
           ('00000000-0000-0000-0000-000000005923', 0), ('00000000-0000-0000-0000-000000005925', 0)$$,
  'update_expense: balances follow the edit and sum to zero');
select results_eq(
  $$select action, (before ->> 'amount_minor')::bigint, jsonb_array_length(before -> 'splits'), (after ->> 'amount_minor')::bigint
      from public.activity where expense_id = (select id from pg_temp.e1) order by id desc limit 1$$,
  $$values ('edited', 9000::bigint, 3, 12000::bigint)$$,
  'update_expense: activity keeps the prior expense with its three splits');
select is(
  public.update_expense(pg_temp.edit('00000000-0000-0000-0000-000000005941', 12000, ' Groceries and gas',
    '[{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 12000}]',
    '[{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 6000},
      {"member_id": "00000000-0000-0000-0000-000000005922", "amount_minor": 6000}]')),
  (select id from e1), 'update_expense: a replay of the same payload returns the id');
select is((select count(*)::int from public.activity where expense_id = (select id from e1) and action = 'edited'),
  1, 'update_expense: a replay writes nothing');
select throws_ok(format('select public.update_expense(%L)', pg_temp.edit('00000000-0000-0000-0000-000000005941', 12000,
    'Changed', '[{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 12000}]',
    '[{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 12000}]')),
  'PT409', null, 'update_expense: the same key with a different payload is a conflict');
select throws_ok(format('select public.update_expense(%L)', pg_temp.edit('00000000-0000-0000-0000-000000005942', 12000,
    'Bad', '[{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 12000}]',
    '[{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 5000}]')),
  '22023', null, 'update_expense: splits that do not sum to the amount are rejected');
select throws_ok(format('select public.update_expense(%L)', pg_temp.edit('00000000-0000-0000-0000-000000005942', 12000,
    'Bad', '[{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 12000}]',
    '[{"member_id": "00000000-0000-0000-0000-000000005903", "amount_minor": 12000}]')),
  '22023', null, 'update_expense: a split on someone outside the space is rejected');
select is((select description from public.expenses where id = (select id from e1)), 'Groceries and gas',
  'update_expense: rejected calls changed nothing');

select pg_temp.login('00000000-0000-0000-0000-000000005902');
select lives_ok(format('select public.update_expense(%L)', pg_temp.edit('00000000-0000-0000-0000-000000005943', 9000,
    'Groceries', '[{"member_id": "00000000-0000-0000-0000-000000005922", "amount_minor": 9000}]',
    '[{"member_id": "00000000-0000-0000-0000-000000005921"}, {"member_id": "00000000-0000-0000-0000-000000005922"},
      {"member_id": "00000000-0000-0000-0000-000000005923"}]', 'equal')),
  'update_expense: creator B edits E1 back to an equal split');
select results_eq('select * from pg_temp.balances()',
  $$values ('00000000-0000-0000-0000-000000005921'::uuid, -3000::bigint), ('00000000-0000-0000-0000-000000005922', 6000),
           ('00000000-0000-0000-0000-000000005923', -3000), ('00000000-0000-0000-0000-000000005925', 0)$$,
  'update_expense: balances follow the second edit');
select is(pg_temp.affected($$update public.expenses set category = 'food' where id = (select id from pg_temp.e1)$$),
  1, 'expenses_update: creator B may still edit E1 directly');

select pg_temp.login('00000000-0000-0000-0000-000000005905');
select throws_ok(format('select public.update_expense(%L)', pg_temp.edit('00000000-0000-0000-0000-000000005944', 100,
    'Mine now', '[{"member_id": "00000000-0000-0000-0000-000000005925", "amount_minor": 100}]',
    '[{"member_id": "00000000-0000-0000-0000-000000005925", "amount_minor": 100}]')),
  '42501', null, 'update_expense: member E, neither creator nor owner, cannot edit E1');
select is(pg_temp.affected($$update public.expenses set description = 'x' where id = (select id from pg_temp.e1)$$),
  0, 'expenses_update: E cannot edit E1 directly either');
select is(pg_temp.affected($$delete from public.expense_payers where expense_id = (select id from pg_temp.e1)$$),
  0, 'expense_payers_delete: E cannot remove E1''s payers');
select is(pg_temp.affected($$update public.expense_splits set amount_minor = 0 where expense_id = (select id from pg_temp.e1)$$),
  0, 'expense_splits_update: E cannot change E1''s splits');
select throws_ok(format($$insert into public.expense_splits (expense_id, member_id, split_type, amount_minor)
    values (%L, '00000000-0000-0000-0000-000000005925', 'equal', 0)$$, (select id from e1)),
  '42501', null, 'expense_splits_insert: E cannot add a split to E1');
select pg_temp.login('00000000-0000-0000-0000-000000005903');
select throws_ok(format('select public.update_expense(%L)', pg_temp.edit('00000000-0000-0000-0000-000000005945', 100,
    'x', '[]', '[]')), '42501', null, 'update_expense: outsider C cannot edit E1');
select pg_temp.login('00000000-0000-0000-0000-000000005904');
select throws_ok(format('select public.update_expense(%L)', pg_temp.edit('00000000-0000-0000-0000-000000005946', 100,
    'x', '[]', '[]')), '42501', null, 'update_expense: unverified D cannot edit');

-- delete_expense
select pg_temp.login('00000000-0000-0000-0000-000000005905');
select throws_ok(format('select public.delete_expense(%L, %L)', (select id from e1), '00000000-0000-0000-0000-000000005951'),
  '42501', null, 'delete_expense: member E cannot delete B''s expense');
select pg_temp.login('00000000-0000-0000-0000-000000005902');
select lives_ok(format('select public.delete_expense(%L, %L)', (select id from e1), '00000000-0000-0000-0000-000000005951'),
  'delete_expense: creator B deletes E1');
select ok((select deleted_at is not null from public.expenses where id = (select id from e1)),
  'delete_expense: the expense is soft-deleted');
select results_eq('select * from pg_temp.balances()',
  $$values ('00000000-0000-0000-0000-000000005921'::uuid, 0::bigint), ('00000000-0000-0000-0000-000000005922', 0),
           ('00000000-0000-0000-0000-000000005923', 0), ('00000000-0000-0000-0000-000000005925', 0)$$,
  'delete_expense: a deleted expense no longer counts toward balances');
select results_eq(
  $$select action, jsonb_array_length(before -> 'payers'), jsonb_array_length(before -> 'splits')
      from public.activity where expense_id = (select id from pg_temp.e1) order by id desc limit 1$$,
  $$values ('deleted', 1, 3)$$,
  'delete_expense: activity keeps the deleted expense with its payers and splits');
select lives_ok(format('select public.delete_expense(%L, %L)', (select id from e1), '00000000-0000-0000-0000-000000005951'),
  'delete_expense: a replay succeeds');
select is((select count(*)::int from public.activity where expense_id = (select id from e1) and action = 'deleted'),
  1, 'delete_expense: a replay writes nothing');
select throws_ok(format('select public.delete_expense(%L, %L)', gen_random_uuid(), '00000000-0000-0000-0000-000000005951'),
  '42501', null, 'delete_expense: an unknown expense is refused');
select throws_ok(format('select public.delete_expense(%L, %L)', (select id from e1), '00000000-0000-0000-0000-000000005941'),
  'PT409', null, 'delete_expense: a key used for another mutation is a conflict');
select throws_ok(format('select public.delete_expense(%L, %L)', (select id from e1), '00000000-0000-0000-0000-000000005952'),
  '22023', null, 'delete_expense: deleting again with a new key is rejected');
select throws_ok(format('select public.update_expense(%L)', pg_temp.edit('00000000-0000-0000-0000-000000005953', 100,
    'Revive', '[{"member_id": "00000000-0000-0000-0000-000000005922", "amount_minor": 100}]',
    '[{"member_id": "00000000-0000-0000-0000-000000005922", "amount_minor": 100}]')),
  '22023', null, 'update_expense: a deleted expense cannot be edited');

-- add_space_members
select lives_ok($$select public.add_space_members('00000000-0000-0000-0000-000000005910',
    '[{"phone": "+919590000077", "name": "Yash"}, {"phone": "+919590000078"}]', '00000000-0000-0000-0000-000000005961')$$,
  'add_space_members: member B adds two numbers');
select results_eq(
  $$select phone::text, name, role::text, user_id from public.space_members
     where space_id = '00000000-0000-0000-0000-000000005910' and phone::text in ('+919590000077', '+919590000078') order by phone$$,
  $$values ('+919590000077', 'Yash', 'member', null::uuid), ('+919590000078', null, 'member', null)$$,
  'add_space_members: new members are pending rows by phone');
select lives_ok($$select public.add_space_members('00000000-0000-0000-0000-000000005910',
    '[{"phone": "+919590000078"}, {"phone": "+919590000077", "name": " Yash "}]', '00000000-0000-0000-0000-000000005961')$$,
  'add_space_members: a replay with the members reordered succeeds');
select is((select count(*)::int from public.space_members where space_id = '00000000-0000-0000-0000-000000005910'),
  6, 'add_space_members: a replay writes nothing');
select throws_ok($$select public.add_space_members('00000000-0000-0000-0000-000000005910',
    '[{"phone": "+919590000079"}]', '00000000-0000-0000-0000-000000005961')$$,
  'PT409', null, 'add_space_members: the same key with other members is a conflict');
select throws_ok($$select public.add_space_members('00000000-0000-0000-0000-000000005910',
    '[{"phone": "+919590000001"}]', '00000000-0000-0000-0000-000000005962')$$,
  '22023', null, 'add_space_members: an existing member''s phone is rejected');
select throws_ok($$select public.add_space_members('00000000-0000-0000-0000-000000005910', '[]',
    '00000000-0000-0000-0000-000000005963')$$,
  '22023', null, 'add_space_members: an empty list is rejected');
select pg_temp.login('00000000-0000-0000-0000-000000005903');
select throws_ok($$select public.add_space_members('00000000-0000-0000-0000-000000005910',
    '[{"phone": "+919590000080"}]', '00000000-0000-0000-0000-000000005964')$$,
  '42501', null, 'add_space_members: outsider C cannot add members');

-- leave_space. A adds E2: 1000 paid by A, split equally with E, so E owes 500.
select pg_temp.login('00000000-0000-0000-0000-000000005901');
select isnt(public.add_expense('{"space_id": "00000000-0000-0000-0000-000000005910",
  "idempotency_key": "00000000-0000-0000-0000-000000005932", "description": "Milk", "amount_minor": 1000,
  "payers": [{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 1000}],
  "splits": [{"member_id": "00000000-0000-0000-0000-000000005921"}, {"member_id": "00000000-0000-0000-0000-000000005925"}]}'),
  null, 'fixture: A adds E2, E owes 500');
select pg_temp.login('00000000-0000-0000-0000-000000005905');
select is(pg_temp.hint_of($$select public.leave_space('00000000-0000-0000-0000-000000005910', '00000000-0000-0000-0000-000000005971')$$),
  'balance_not_zero', 'leave_space: E cannot leave while owing 500');
select throws_ok($$update public.space_members set left_at = now() where id = '00000000-0000-0000-0000-000000005925'$$,
  '22023', null, 'space_members_update: nor by updating left_at directly');
select pg_temp.login('00000000-0000-0000-0000-000000005901');
select throws_ok($$select public.leave_space('00000000-0000-0000-0000-000000005910', '00000000-0000-0000-0000-000000005972',
    '00000000-0000-0000-0000-000000005925')$$,
  '22023', null, 'leave_space: owner A cannot remove E while E has a balance');
select lives_ok($$select public.leave_space('00000000-0000-0000-0000-000000005910', '00000000-0000-0000-0000-000000005973',
    '00000000-0000-0000-0000-000000005923')$$,
  'leave_space: owner A removes X, whose balance is zero');
select ok((select left_at is not null from public.space_members where id = '00000000-0000-0000-0000-000000005923'),
  'leave_space: X has left');
select pg_temp.login('00000000-0000-0000-0000-000000005902');
select throws_ok($$select public.leave_space('00000000-0000-0000-0000-000000005910', '00000000-0000-0000-0000-000000005974',
    (select id from public.space_members where phone = '+919590000077'))$$,
  '42501', null, 'leave_space: member B cannot remove another member');

select pg_temp.login('00000000-0000-0000-0000-000000005905');
select isnt(public.add_expense('{"space_id": "00000000-0000-0000-0000-000000005910",
  "idempotency_key": "00000000-0000-0000-0000-000000005933", "description": "Settle", "amount_minor": 500,
  "is_settlement": true, "split_type": "exact",
  "payers": [{"member_id": "00000000-0000-0000-0000-000000005925", "amount_minor": 500}],
  "splits": [{"member_id": "00000000-0000-0000-0000-000000005921", "amount_minor": 500}]}'),
  null, 'fixture: E settles 500 with A');
select lives_ok($$select public.leave_space('00000000-0000-0000-0000-000000005910', '00000000-0000-0000-0000-000000005971')$$,
  'leave_space: E leaves at a zero balance');
select ok(not public.is_space_member('00000000-0000-0000-0000-000000005910'), 'leave_space: E is no longer a member');
select lives_ok($$select public.leave_space('00000000-0000-0000-0000-000000005910', '00000000-0000-0000-0000-000000005971')$$,
  'leave_space: a replay succeeds after E has left');
select throws_ok($$select public.leave_space('00000000-0000-0000-0000-000000005910', '00000000-0000-0000-0000-000000005971',
    '00000000-0000-0000-0000-000000005921')$$,
  'PT409', null, 'leave_space: the same key with another member is a conflict');
select throws_ok($$select public.leave_space('00000000-0000-0000-0000-000000005910', '00000000-0000-0000-0000-000000005975')$$,
  '42501', null, 'leave_space: a departed member cannot leave again');

-- update_profile
select pg_temp.login('00000000-0000-0000-0000-000000005901');
select lives_ok($$select public.update_profile(' Asha K ', 'asha.k@okaxis')$$, 'update_profile: A sets name and UPI id');
select results_eq($$select name, upi_id from public.profiles where id = '00000000-0000-0000-0000-000000005901'$$,
  $$values ('Asha K', 'asha.k@okaxis')$$, 'update_profile: the profile is updated');
select is(pg_temp.hint_of($$select public.update_profile('Asha', 'not-a-vpa')$$), 'invalid_vpa',
  'update_profile: a malformed UPI id is rejected with hint invalid_vpa');
select throws_ok($$select public.update_profile('Asha', 'asha@ok axis')$$, '22023', null,
  'update_profile: a UPI id with a space is rejected');
select throws_ok($$select public.update_profile(' ', null)$$, '22023', null, 'update_profile: a blank name is rejected');
select lives_ok($$select public.update_profile('Asha', '')$$, 'update_profile: a blank UPI id clears it');
select is((select upi_id from public.profiles where id = '00000000-0000-0000-0000-000000005901'), null,
  'update_profile: the UPI id is cleared');
select throws_ok($$update public.profiles set upi_id = 'bad' where id = '00000000-0000-0000-0000-000000005901'$$,
  '23514', null, 'profiles: a direct write of a malformed UPI id is refused');
select pg_temp.login('00000000-0000-0000-0000-000000005904');
select throws_ok($$select public.update_profile('Dev', null)$$, '42501', null, 'update_profile: unverified D is refused');

select * from finish();
rollback;
