-- Two-sided settle-ups (#78): confirm_settlement, dispute_settlement, pending_settlements.
-- Callers: A owns space S; B and C are accepted members; P has an account but is still a pending
-- member; O is an outsider; D has an unverified phone; anon has no session.
-- E0: A paid 9000 for A, B and C (3000 each). Then, payer -> payee:
--   S1 B -> A 3000 by B, confirmed by A.   S2 C -> A 3000 by A (the payee), confirmed at once.
--   S3 C -> B 1000 by C, disputed by B.    S4 B -> A 500 by B, corrected to 600 by A, so confirmed.
--   S5 B -> A 100 by C, deleted pending.   S6 B -> P 100 by B, P cannot answer.
--   S7 C -> A 200 by C, pending when C leaves; it can no longer be confirmed.
begin;
create extension if not exists pgtap with schema extensions;

select plan(76);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000007801', '919780000001', now()),
  ('00000000-0000-0000-0000-000000007802', '919780000002', now()),
  ('00000000-0000-0000-0000-000000007803', '919780000003', now()),
  ('00000000-0000-0000-0000-000000007804', '919780000004', now()),
  ('00000000-0000-0000-0000-000000007805', '919780000005', null),
  ('00000000-0000-0000-0000-000000007806', '919780000006', now());
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000007801', '+919780000001', 'Asha'),
  ('00000000-0000-0000-0000-000000007802', '+919780000002', 'Bilal'),
  ('00000000-0000-0000-0000-000000007803', '+919780000003', 'Chitra'),
  ('00000000-0000-0000-0000-000000007804', '+919780000004', 'Priya'),
  ('00000000-0000-0000-0000-000000007806', '+919780000006', 'Omar');
insert into public.spaces (id, name, kind, created_by) values
  ('00000000-0000-0000-0000-000000007810', 'Flat 78', 'flat', '00000000-0000-0000-0000-000000007801');
insert into public.space_members (id, space_id, phone, user_id, role) values
  ('00000000-0000-0000-0000-000000007821', '00000000-0000-0000-0000-000000007810', '+919780000001', '00000000-0000-0000-0000-000000007801', 'owner'),
  ('00000000-0000-0000-0000-000000007822', '00000000-0000-0000-0000-000000007810', '+919780000002', '00000000-0000-0000-0000-000000007802', 'member'),
  ('00000000-0000-0000-0000-000000007823', '00000000-0000-0000-0000-000000007810', '+919780000003', '00000000-0000-0000-0000-000000007803', 'member'),
  ('00000000-0000-0000-0000-000000007824', '00000000-0000-0000-0000-000000007810', '+919780000004', null, 'member');

create function pg_temp.login(u text) returns text language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true)
$$;
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
-- A settle-up in S: payer pays payee `amount`, recorded by whoever is logged in.
create function pg_temp.settle(key text, payer text, payee text, amount int) returns text language sql as $$
  select format('select public.add_expense(%L)', jsonb_build_object(
    'space_id', '00000000-0000-0000-0000-000000007810', 'idempotency_key', key, 'description', 'Settle up',
    'amount_minor', amount, 'split_type', 'exact', 'is_settlement', true,
    'payers', jsonb_build_array(jsonb_build_object('member_id', payer, 'amount_minor', amount)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', payee, 'amount_minor', amount))))
$$;
create function pg_temp.confirm(expense uuid, key text) returns text language sql as $$
  select format('select public.confirm_settlement(%L, %L)', expense, key)
$$;
create function pg_temp.dispute(expense uuid, reason text, key text) returns text language sql as $$
  select format('select public.dispute_settlement(%L, %L, %L)', expense, reason, key)
$$;
-- Read as postgres, so the checks do not depend on who is logged in.
create function pg_temp.id(key text) returns uuid language sql security definer as $$
  select id from public.expenses where idempotency_key = key::uuid
$$;
create function pg_temp.status(key text) returns text language sql security definer as $$
  select settlement_status from public.expenses where idempotency_key = key::uuid
$$;
create function pg_temp.balances() returns text language sql security definer as $$
  select string_agg(format('%s=%s', p.name, b.balance_minor), ' ' order by b.phone)
    from public.space_member_balances b join public.profiles p on p.phone = b.phone
   where b.space_id = '00000000-0000-0000-0000-000000007810' and b.member_id <> '00000000-0000-0000-0000-000000007824'
$$;
create function pg_temp.last_action(key text) returns text language sql security definer as $$
  select action from public.activity where expense_id = pg_temp.id(key) order by id desc limit 1
$$;
grant execute on all functions in schema pg_temp to public;

-- Hardening.
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('confirm_settlement', 'dispute_settlement')
      and (not coalesce(p.proconfig @> array['search_path=""'], false)
           or has_function_privilege('anon', p.oid, 'execute')
           or not has_function_privilege('authenticated', p.oid, 'execute'))),
  null,
  'settlement RPCs have a fixed search_path and are executable by authenticated only');
select ok(not has_function_privilege('authenticated', 'private.answer_settlement(text, uuid, boolean, text)', 'execute')
          and not has_function_privilege('anon', 'private.answer_settlement(text, uuid, boolean, text)', 'execute')
          and not has_function_privilege('authenticated', 'public.guard_settlement()', 'execute'),
  'private.answer_settlement and the settlement guard are not executable by clients');
select ok(not has_table_privilege('anon', 'public.pending_settlements', 'select')
          and has_table_privilege('authenticated', 'public.pending_settlements', 'select'),
  'pending_settlements is readable by authenticated only');
select ok(not has_column_privilege('authenticated', 'public.expenses', 'confirmed_by', 'update')
          and not has_column_privilege('authenticated', 'public.expenses', 'confirmed_at', 'insert')
          and not has_column_privilege('authenticated', 'public.expenses', 'disputed_at', 'update'),
  'clients cannot write the confirmation columns');

set local role anon;
select throws_ok(pg_temp.confirm(gen_random_uuid(), '00000000-0000-0000-0000-000000007901'), '42501', null,
  'anon cannot call confirm_settlement');
select throws_ok(pg_temp.dispute(gen_random_uuid(), 'No', '00000000-0000-0000-0000-000000007901'), '42501', null,
  'anon cannot call dispute_settlement');
reset role;
set local role authenticated;

-- E0.
select pg_temp.login('00000000-0000-0000-0000-000000007801');
select isnt(public.add_expense(jsonb_build_object(
    'space_id', '00000000-0000-0000-0000-000000007810', 'idempotency_key', '00000000-0000-0000-0000-000000007a00',
    'description', 'Groceries', 'amount_minor', 9000,
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007821', 'amount_minor', 9000)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007821'),
                                jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007822'),
                                jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007823')))),
  null, 'fixture: A pays 9000 for A, B and C');
select is(pg_temp.balances(), 'Asha=6000 Bilal=-3000 Chitra=-3000', 'E0: balances');
select is(pg_temp.status('00000000-0000-0000-0000-000000007a00'), null, 'spending has no settlement status');

-- Shape.
select pg_temp.login('00000000-0000-0000-0000-000000007802');
select is(pg_temp.hint_of(format('select public.add_expense(%L)', jsonb_build_object(
    'space_id', '00000000-0000-0000-0000-000000007810', 'idempotency_key', '00000000-0000-0000-0000-000000007a09',
    'description', 'Settle up', 'amount_minor', 3000, 'split_type', 'exact', 'is_settlement', true,
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007822', 'amount_minor', 3000)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007821', 'amount_minor', 2000),
                                jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007823', 'amount_minor', 1000))))),
  'settlement_shape', 'add_expense: a settle-up has one payee');
select is(pg_temp.hint_of(pg_temp.settle('00000000-0000-0000-0000-000000007a09', '00000000-0000-0000-0000-000000007822',
    '00000000-0000-0000-0000-000000007822', 3000)),
  'settlement_shape', 'add_expense: a settle-up is between two members');

-- S1: B records paying A. Pending, so balances do not move.
select lives_ok(pg_temp.settle('00000000-0000-0000-0000-000000007a01', '00000000-0000-0000-0000-000000007822',
    '00000000-0000-0000-0000-000000007821', 3000), 'S1: B records paying A 3000');
select is(pg_temp.status('00000000-0000-0000-0000-000000007a01'), 'pending', 'S1: recorded by the payer, it is pending');
select is(pg_temp.balances(), 'Asha=6000 Bilal=-3000 Chitra=-3000', 'S1 pending: balances do not count it');
select is(pg_temp.last_action('00000000-0000-0000-0000-000000007a01'), 'created', 'S1: logs created');
select results_eq(
  $$select payer_member_id, payee_member_id, amount_minor, awaiting_me from public.pending_settlements
     where expense_id = pg_temp.id('00000000-0000-0000-0000-000000007a01')$$,
  $$values ('00000000-0000-0000-0000-000000007822'::uuid, '00000000-0000-0000-0000-000000007821'::uuid, 3000::bigint, false)$$,
  'pending_settlements: B sees S1, not awaiting B');
select pg_temp.login('00000000-0000-0000-0000-000000007801');
select is((select awaiting_me from public.pending_settlements where expense_id = pg_temp.id('00000000-0000-0000-0000-000000007a01')),
  true, 'pending_settlements: S1 is awaiting A, the payee');

-- S1: denied.
select pg_temp.login('00000000-0000-0000-0000-000000007805');
select throws_ok(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a01'), '00000000-0000-0000-0000-000000007b01'),
  '42501', null, 'confirm_settlement: unverified D is refused');
select pg_temp.login('00000000-0000-0000-0000-000000007806');
select throws_ok(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a01'), '00000000-0000-0000-0000-000000007b01'),
  '42501', null, 'confirm_settlement: outsider O is refused');
select is((select count(*)::int from public.pending_settlements), 0, 'pending_settlements: O sees nothing');
select pg_temp.login('00000000-0000-0000-0000-000000007804');
select throws_ok(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a01'), '00000000-0000-0000-0000-000000007b01'),
  '42501', null, 'confirm_settlement: pending claimant P is refused');
select pg_temp.login('00000000-0000-0000-0000-000000007802');
select is(pg_temp.hint_of(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a01'), '00000000-0000-0000-0000-000000007b01')),
  'not_payee', 'confirm_settlement: B, the payer, cannot confirm their own payment');
select is(pg_temp.hint_of(pg_temp.dispute(pg_temp.id('00000000-0000-0000-0000-000000007a01'), 'No', '00000000-0000-0000-0000-000000007b02')),
  'not_payee', 'dispute_settlement: nor dispute it');
select pg_temp.login('00000000-0000-0000-0000-000000007803');
select is(pg_temp.hint_of(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a01'), '00000000-0000-0000-0000-000000007b01')),
  'not_payee', 'confirm_settlement: C, another member, cannot confirm it');
select throws_ok(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a00'), '00000000-0000-0000-0000-000000007b03'),
  '42501', null, 'confirm_settlement: spending is not a settle-up');
select pg_temp.login('00000000-0000-0000-0000-000000007801');
select throws_ok(pg_temp.confirm(null, '00000000-0000-0000-0000-000000007b01'), '22023', null,
  'confirm_settlement: the expense id is required');
select throws_ok(pg_temp.dispute(pg_temp.id('00000000-0000-0000-0000-000000007a01'), '  ', '00000000-0000-0000-0000-000000007b01'),
  '22023', null, 'dispute_settlement: a reason is required');
select is(pg_temp.status('00000000-0000-0000-0000-000000007a01'), 'pending', 'S1: still pending after the refusals');
select is(pg_temp.balances(), 'Asha=6000 Bilal=-3000 Chitra=-3000', 'S1 refused: balances unchanged');

-- S1: A confirms.
select lives_ok(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a01'), '00000000-0000-0000-0000-000000007b01'),
  'confirm_settlement: A, the payee, confirms S1');
select ok((select settlement_status = 'confirmed' and confirmed_by = '00000000-0000-0000-0000-000000007801'
                  and confirmed_at is not null and disputed_at is null
             from public.expenses where id = pg_temp.id('00000000-0000-0000-0000-000000007a01')),
  'S1: confirmed by A');
select is(pg_temp.balances(), 'Asha=3000 Bilal=0 Chitra=-3000', 'S1 confirmed: balances count it');
select is(pg_temp.last_action('00000000-0000-0000-0000-000000007a01'), 'confirmed', 'S1: logs confirmed');
select is((select count(*)::int from public.pending_settlements
            where expense_id = pg_temp.id('00000000-0000-0000-0000-000000007a01')), 0,
  'pending_settlements: S1 is gone once confirmed');
select lives_ok(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a01'), '00000000-0000-0000-0000-000000007b01'),
  'confirm_settlement: a replay succeeds after S1 is confirmed');
select is((select count(*)::int from public.activity where expense_id = pg_temp.id('00000000-0000-0000-0000-000000007a01')
            and action = 'confirmed'), 1, 'confirm_settlement: the replay writes nothing');
select throws_ok(pg_temp.dispute(pg_temp.id('00000000-0000-0000-0000-000000007a01'), 'No', '00000000-0000-0000-0000-000000007b01'),
  'PT409', null, 'dispute_settlement: the confirm key is a conflict');
select is(pg_temp.hint_of(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a01'), '00000000-0000-0000-0000-000000007b04')),
  'not_pending', 'confirm_settlement: a new key on a confirmed settle-up is not_pending');
select is(pg_temp.hint_of(pg_temp.dispute(pg_temp.id('00000000-0000-0000-0000-000000007a01'), 'No', '00000000-0000-0000-0000-000000007b05')),
  'not_pending', 'dispute_settlement: confirmed is final');

-- Confirmed is final: no edit, delete or kind change.
select pg_temp.login('00000000-0000-0000-0000-000000007802');
select is(pg_temp.hint_of(format('select public.update_expense(%L)', jsonb_build_object(
    'expense_id', pg_temp.id('00000000-0000-0000-0000-000000007a01'), 'idempotency_key', '00000000-0000-0000-0000-000000007b06',
    'description', 'Settle up', 'amount_minor', 1, 'split_type', 'exact', 'is_settlement', true,
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007822', 'amount_minor', 1)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007821', 'amount_minor', 1))))),
  'settlement_final', 'update_expense: B cannot edit a confirmed settle-up');
select is(pg_temp.hint_of(format('select public.delete_expense(%L, %L)', pg_temp.id('00000000-0000-0000-0000-000000007a01'),
    '00000000-0000-0000-0000-000000007b07')),
  'settlement_final', 'delete_expense: B cannot delete it');
select is(pg_temp.hint_of(format('update public.expenses set deleted_at = now() where id = %L',
    pg_temp.id('00000000-0000-0000-0000-000000007a01'))),
  'settlement_final', 'expenses: nor by updating deleted_at directly');
select pg_temp.login('00000000-0000-0000-0000-000000007801');
select is(pg_temp.hint_of(format('update public.expenses set is_settlement = false where id = %L',
    pg_temp.id('00000000-0000-0000-0000-000000007a01'))),
  'settlement_kind', 'expenses: a settle-up cannot become spending');
select is(pg_temp.hint_of(format('update public.expenses set is_settlement = true where id = %L',
    pg_temp.id('00000000-0000-0000-0000-000000007a00'))),
  'settlement_kind', 'expenses: nor spending a settle-up');
select is(pg_temp.balances(), 'Asha=3000 Bilal=0 Chitra=-3000', 'after the refusals: balances unchanged');

-- S2: A, the payee, records C paying A; confirmed at once.
select lives_ok(pg_temp.settle('00000000-0000-0000-0000-000000007a02', '00000000-0000-0000-0000-000000007823',
    '00000000-0000-0000-0000-000000007821', 3000), 'S2: A records C paying A 3000');
select ok((select settlement_status = 'confirmed' and confirmed_by = '00000000-0000-0000-0000-000000007801'
             from public.expenses where id = pg_temp.id('00000000-0000-0000-0000-000000007a02')),
  'S2: recorded by the payee, it is confirmed at once');
select is(pg_temp.balances(), 'Asha=0 Bilal=0 Chitra=0', 'S2: balances count it');
select is(pg_temp.last_action('00000000-0000-0000-0000-000000007a02'), 'confirmed', 'S2: logs created, then confirmed');

-- S3: C records paying B; B disputes it.
select pg_temp.login('00000000-0000-0000-0000-000000007803');
select lives_ok(pg_temp.settle('00000000-0000-0000-0000-000000007a03', '00000000-0000-0000-0000-000000007823',
    '00000000-0000-0000-0000-000000007822', 1000), 'S3: C records paying B 1000');
select pg_temp.login('00000000-0000-0000-0000-000000007802');
select lives_ok(pg_temp.dispute(pg_temp.id('00000000-0000-0000-0000-000000007a03'), ' Not received ',
    '00000000-0000-0000-0000-000000007b08'), 'dispute_settlement: B disputes S3');
select ok((select settlement_status = 'disputed' and disputed_by = '00000000-0000-0000-0000-000000007802'
                  and dispute_reason = 'Not received' and confirmed_at is null
             from public.expenses where id = pg_temp.id('00000000-0000-0000-0000-000000007a03')),
  'S3: disputed by B with the trimmed reason');
select is(pg_temp.balances(), 'Asha=0 Bilal=0 Chitra=0', 'S3 disputed: balances never count it');
select is(pg_temp.last_action('00000000-0000-0000-0000-000000007a03'), 'disputed', 'S3: logs disputed');
select lives_ok(pg_temp.dispute(pg_temp.id('00000000-0000-0000-0000-000000007a03'), 'Not received',
    '00000000-0000-0000-0000-000000007b08'), 'dispute_settlement: a replay succeeds');
select throws_ok(pg_temp.dispute(pg_temp.id('00000000-0000-0000-0000-000000007a03'), 'Something else',
    '00000000-0000-0000-0000-000000007b08'), 'PT409', null, 'dispute_settlement: the same key with another reason is a conflict');
select is(pg_temp.hint_of(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a03'), '00000000-0000-0000-0000-000000007b09')),
  'not_pending', 'confirm_settlement: disputed is final');
select pg_temp.login('00000000-0000-0000-0000-000000007803');
select is(pg_temp.hint_of(format('select public.delete_expense(%L, %L)', pg_temp.id('00000000-0000-0000-0000-000000007a03'),
    '00000000-0000-0000-0000-000000007b10')),
  'settlement_final', 'delete_expense: a disputed settle-up stays visible');

-- S4: B records paying A 500; A, the payee and an owner, corrects it to 600, which confirms it.
select pg_temp.login('00000000-0000-0000-0000-000000007802');
select lives_ok(pg_temp.settle('00000000-0000-0000-0000-000000007a04', '00000000-0000-0000-0000-000000007822',
    '00000000-0000-0000-0000-000000007821', 500), 'S4: B records paying A 500');
select lives_ok(format('select public.update_expense(%L)', jsonb_build_object(
    'expense_id', pg_temp.id('00000000-0000-0000-0000-000000007a04'), 'idempotency_key', '00000000-0000-0000-0000-000000007b11',
    'description', 'Settle up', 'amount_minor', 500, 'split_type', 'exact', 'is_settlement', true, 'category', 'x',
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007822', 'amount_minor', 500)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007821', 'amount_minor', 500)))),
  'update_expense: B, the payer, may still edit a pending settle-up');
select is(pg_temp.status('00000000-0000-0000-0000-000000007a04'), 'pending', 'S4: the payer''s edit leaves it pending');
select pg_temp.login('00000000-0000-0000-0000-000000007801');
select lives_ok(format('select public.update_expense(%L)', jsonb_build_object(
    'expense_id', pg_temp.id('00000000-0000-0000-0000-000000007a04'), 'idempotency_key', '00000000-0000-0000-0000-000000007b12',
    'description', 'Settle up', 'amount_minor', 600, 'split_type', 'exact', 'is_settlement', true,
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007822', 'amount_minor', 600)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000007821', 'amount_minor', 600)))),
  'update_expense: A corrects S4 to 600');
select is(pg_temp.status('00000000-0000-0000-0000-000000007a04'), 'confirmed', 'S4: the payee''s correction confirms it');
select is(pg_temp.balances(), 'Asha=-600 Bilal=600 Chitra=0', 'S4 confirmed: balances count 600');

-- S5: C records B paying A 100, then deletes it while pending.
select pg_temp.login('00000000-0000-0000-0000-000000007803');
select lives_ok(pg_temp.settle('00000000-0000-0000-0000-000000007a05', '00000000-0000-0000-0000-000000007822',
    '00000000-0000-0000-0000-000000007821', 100), 'S5: C records B paying A 100');
select is(pg_temp.status('00000000-0000-0000-0000-000000007a05'), 'pending', 'S5: recorded by a third member, it is pending');
select lives_ok(format('select public.delete_expense(%L, %L)', pg_temp.id('00000000-0000-0000-0000-000000007a05'),
    '00000000-0000-0000-0000-000000007b13'), 'delete_expense: C deletes S5 while pending');
select pg_temp.login('00000000-0000-0000-0000-000000007801');
select is(pg_temp.hint_of(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a05'), '00000000-0000-0000-0000-000000007b14')),
  'not_pending', 'confirm_settlement: a deleted settle-up is not_pending');

-- S6: B records paying P, who has not accepted the space: P can read it but not answer.
select pg_temp.login('00000000-0000-0000-0000-000000007802');
select lives_ok(pg_temp.settle('00000000-0000-0000-0000-000000007a06', '00000000-0000-0000-0000-000000007822',
    '00000000-0000-0000-0000-000000007824', 100), 'S6: B records paying P 100');
select pg_temp.login('00000000-0000-0000-0000-000000007804');
select is((select awaiting_me from public.pending_settlements where expense_id = pg_temp.id('00000000-0000-0000-0000-000000007a06')),
  false, 'pending_settlements: P sees S6 but it is not awaiting P until P accepts');
select throws_ok(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a06'), '00000000-0000-0000-0000-000000007b15'),
  '42501', null, 'confirm_settlement: P, a pending claimant, cannot confirm a payment to P');
select throws_ok(pg_temp.dispute(pg_temp.id('00000000-0000-0000-0000-000000007a06'), 'No', '00000000-0000-0000-0000-000000007b16'),
  '42501', null, 'dispute_settlement: nor dispute it');

-- S7: C records paying A 200 and leaves while it is pending (C's balance is zero without it).
select pg_temp.login('00000000-0000-0000-0000-000000007803');
select lives_ok(pg_temp.settle('00000000-0000-0000-0000-000000007a07', '00000000-0000-0000-0000-000000007823',
    '00000000-0000-0000-0000-000000007821', 200), 'S7: C records paying A 200');
select lives_ok(format('select public.leave_space(%L, %L)', '00000000-0000-0000-0000-000000007810',
    '00000000-0000-0000-0000-000000007b17'), 'leave_space: C leaves at a zero balance');
select pg_temp.login('00000000-0000-0000-0000-000000007801');
select is(pg_temp.hint_of(pg_temp.confirm(pg_temp.id('00000000-0000-0000-0000-000000007a07'), '00000000-0000-0000-0000-000000007b18')),
  'departed_member', 'confirm_settlement: a departed payer''s balance cannot change');
select is(pg_temp.balances(), 'Asha=-600 Bilal=600 Chitra=0', 'end: balances');

select * from finish();
rollback;
