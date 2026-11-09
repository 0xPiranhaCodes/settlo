-- RPCs (#10): create_space, add_expense, lookup_phones.
-- Callers: A creates the space, B is a member by phone, C is an outsider, D has an unverified phone.
-- X is a number with no account. The last block races two sessions over dblink.
-- Includes a test for every probe in the PR #37 review: changed-payload replays (sequential and
-- concurrent), percent/shares allocations that sum but disagree with packages/core, and the
-- lookup_phones daily quota.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(66);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-00000000a001', '919100000001', now()),
  ('00000000-0000-0000-0000-00000000a002', '919100000002', now()),
  ('00000000-0000-0000-0000-00000000a003', '919100000003', now()),
  ('00000000-0000-0000-0000-00000000a004', '919100000004', null);
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-00000000a001', '+919100000001', 'Asha'),
  ('00000000-0000-0000-0000-00000000a002', '+919100000002', 'Bilal'),
  ('00000000-0000-0000-0000-00000000a003', '+919100000003', 'Chitra');

-- Hardening.
select ok(
  (select prosecdef and proconfig @> array['search_path=""'] from pg_proc
    where oid = 'public.lookup_phones(text[])'::regprocedure),
  'lookup_phones is security definer with a fixed empty search_path');
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('create_space', 'add_expense', 'lookup_phones')
      and (not coalesce(p.proconfig @> array['search_path=""'], false)
           or has_function_privilege('anon', p.oid, 'execute')
           or not has_function_privilege('authenticated', p.oid, 'execute'))),
  null,
  'RPCs have a fixed search_path and are executable by authenticated only');
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
grant execute on function pg_temp.hint_of(text) to public;

select ok(
  not exists (select from pg_proc p, aclexplode(p.proacl) a
               where p.pronamespace = 'public'::regnamespace
                 and p.proname in ('create_space', 'add_expense', 'lookup_phones') and a.grantee = 0),
  'RPCs are revoked from public');

set local role anon;
select throws_ok($$select public.lookup_phones(array['00'])$$, '42501', null, 'anon cannot call lookup_phones');
select throws_ok($$select public.create_space('x', 'flat', '[]')$$, '42501', null, 'anon cannot call create_space');
reset role;

-- create_space as A.
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000a001", "role": "authenticated"}';

select is(
  public.create_space('Flat 7C', 'flat',
    '[{"phone": "+919100000002", "name": "Bilal"}, {"phone": "+919800000009", "name": "Xavier"},
      {"phone": "+919100000001", "name": "me"}]',
    '00000000-0000-0000-0000-00000000a100'),
  '00000000-0000-0000-0000-00000000a100'::uuid,
  'create_space: returns the space id (the idempotency key)');
select results_eq(
  $$select phone::text, user_id, role::text, name from public.space_members
     where space_id = '00000000-0000-0000-0000-00000000a100' order by phone$$,
  $$values ('+919100000001', '00000000-0000-0000-0000-00000000a001'::uuid, 'owner', null::text),
           ('+919100000002', null, 'member', 'Bilal'),
           ('+919800000009', null, 'member', 'Xavier')$$,
  'create_space: caller is the owner, members are added by phone, the caller''s own entry is skipped');
select is(
  public.create_space(' Flat 7C', 'flat',
    '[{"phone": "+919800000009", "name": "Xavier"}, {"phone": "+919100000002", "name": "Bilal"}]',
    '00000000-0000-0000-0000-00000000a100'),
  '00000000-0000-0000-0000-00000000a100'::uuid,
  'create_space: the same payload replayed (members reordered, self omitted) returns the same space');
select throws_ok(
  $$select public.create_space('Flat 7C again', 'flat', '[{"phone": "+919100000003"}]', '00000000-0000-0000-0000-00000000a100')$$,
  'PT409', null, 'create_space: the same key with a different payload is an idempotency conflict');
select is(
  pg_temp.hint_of($$select public.create_space('Flat 7C', 'trip', '[]', '00000000-0000-0000-0000-00000000a100')$$),
  'idempotency_conflict', 'create_space: the conflict carries hint idempotency_conflict');
select is((select count(*)::int from public.space_members where space_id = '00000000-0000-0000-0000-00000000a100'),
  3, 'create_space: a replay writes nothing');
select is((select name from public.spaces where id = '00000000-0000-0000-0000-00000000a100'),
  'Flat 7C', 'create_space: a replay does not rename the space');
select throws_ok($$select public.create_space(' ', 'flat', '[]')$$, '22023', null, 'create_space: blank name rejected');
select throws_ok($$select public.create_space('Trip', 'trip', '[{"phone": "+919100000002"}, {"phone": "+919100000002"}]')$$,
  '22023', null, 'create_space: duplicate member phone rejected');
select throws_ok($$select public.create_space('Trip', 'trip', '[{"phone": "9100000002"}]')$$,
  '23514', null, 'create_space: a phone that is not E.164 is rejected');
select isnt(public.create_space('Goa', 'trip'), null, 'create_space: members default to just the caller');

-- add_expense as A. Member ids looked up as postgres so the payloads can name them.
reset role;
create temp table m as
select phone::text as phone, id from public.space_members where space_id = '00000000-0000-0000-0000-00000000a100';
grant select on m to authenticated;
create function pg_temp.mid(p text) returns text language sql as $$ select id::text from pg_temp.m where phone = p $$;
create function pg_temp.expense(key text, amount bigint, payers text, splits text, split_type text default 'equal')
returns text language sql as $$
  select format('{"space_id": "00000000-0000-0000-0000-00000000a100", "idempotency_key": "%s", "description": "Groceries",
                  "amount_minor": %s, "split_type": "%s", "payers": %s, "splits": %s}',
                key, amount, split_type, payers, splits)
$$;
create function pg_temp.call(payload text) returns text language sql as $$
  select format('select public.add_expense(%L::jsonb)', payload)
$$;
set local role authenticated;

select isnt(
  public.add_expense(pg_temp.expense('00000000-0000-0000-0000-00000000a201', 10000,
    format('[{"member_id": "%s", "amount_minor": 10000}]', pg_temp.mid('+919100000002')),
    format('[{"member_id": "%s", "amount_minor": 1}, {"member_id": "%s"}, {"member_id": "%s"}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002'), pg_temp.mid('+919800000009')))::jsonb),
  null,
  'add_expense: returns the new expense id');
select results_eq(
  $$select m.phone, s.amount_minor, s.split_type::text from public.expense_splits s join pg_temp.m m on m.id = s.member_id
     join public.expenses e on e.id = s.expense_id
    where e.idempotency_key = '00000000-0000-0000-0000-00000000a201' order by m.phone$$,
  $$values ('+919100000001', 3333::bigint, 'equal'), ('+919100000002', 3334, 'equal'), ('+919800000009', 3333, 'equal')$$,
  'add_expense: equal split is recomputed on the server, remainder to the payer (client amounts ignored)');
select is(
  public.add_expense(pg_temp.expense('00000000-0000-0000-0000-00000000a201', 10000,
    format('[{"member_id": "%s", "amount_minor": 10000}]', pg_temp.mid('+919100000002')),
    format('[{"member_id": "%s"}, {"member_id": "%s", "amount_minor": 3334}, {"member_id": "%s"}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002'), pg_temp.mid('+919800000009')))::jsonb)::text,
  (select id::text from public.expenses where idempotency_key = '00000000-0000-0000-0000-00000000a201'),
  'add_expense: a replay of the same payload returns the same expense id (client equal amounts do not count)');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a201', 999,
    format('[{"member_id": "%s", "amount_minor": 999}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s"}]', pg_temp.mid('+919100000001')))),
  'PT409', null, 'add_expense: the same key with a different amount, payer and split is an idempotency conflict');
select is(pg_temp.hint_of(pg_temp.call(replace(pg_temp.expense('00000000-0000-0000-0000-00000000a201', 10000,
    format('[{"member_id": "%s", "amount_minor": 10000}]', pg_temp.mid('+919100000002')),
    format('[{"member_id": "%s"}, {"member_id": "%s"}, {"member_id": "%s"}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002'), pg_temp.mid('+919800000009'))),
    'Groceries', 'Vegetables'))),
  'idempotency_conflict', 'add_expense: a changed description alone is a conflict, with hint idempotency_conflict');
select results_eq(
  $$select count(distinct e.id)::int, count(distinct p.member_id)::int, count(distinct s.member_id)::int, min(e.amount_minor)
      from public.expenses e join public.expense_payers p on p.expense_id = e.id join public.expense_splits s on s.expense_id = e.id
     where e.space_id = '00000000-0000-0000-0000-00000000a100'$$,
  $$values (1, 1, 3, 10000::bigint)$$,
  'add_expense: the replay inserted nothing and changed nothing');

select results_eq(
  format($$select s.amount_minor from public.expense_splits s join pg_temp.m m on m.id = s.member_id
           where s.expense_id = %L order by m.phone$$,
    public.add_expense(pg_temp.expense('00000000-0000-0000-0000-00000000a202', 10001,
      format('[{"member_id": "%s", "amount_minor": 5000}, {"member_id": "%s", "amount_minor": 5001}]',
             pg_temp.mid('+919800000009'), pg_temp.mid('+919100000002')),
      format('[{"member_id": "%s"}, {"member_id": "%s"}, {"member_id": "%s"}]',
             pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002'), pg_temp.mid('+919800000009')))::jsonb)),
  $$values (3333::bigint), (3335), (3333)$$,
  'add_expense: with several payers the remainder goes to the first payer in member order');
select results_eq(
  format($$select s.amount_minor, s.percent_bp from public.expense_splits s join pg_temp.m m on m.id = s.member_id
           where s.expense_id = %L order by m.phone$$,
    public.add_expense(pg_temp.expense('00000000-0000-0000-0000-00000000a203', 1000,
      format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
      format('[{"member_id": "%s", "amount_minor": 333, "percent_bp": 3334}, {"member_id": "%s", "amount_minor": 667, "percent_bp": 6666}]',
             pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'percent')::jsonb)),
  $$values (333::bigint, 3334), (667, 6666)$$,
  'add_expense: percent splits matching splitPercent (largest remainder) are stored');
select results_eq(
  format($$select s.amount_minor, s.shares from public.expense_splits s join pg_temp.m m on m.id = s.member_id
           where s.expense_id = %L order by m.phone$$,
    public.add_expense(pg_temp.expense('00000000-0000-0000-0000-00000000a213', 1000,
      format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
      format('[{"member_id": "%s", "amount_minor": 667, "shares": 2}, {"member_id": "%s", "amount_minor": 333, "shares": 1}]',
             pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'shares')::jsonb)),
  $$values (667::bigint, 2), (333, 1)$$,
  'add_expense: shares splits matching splitShares are stored');
select results_eq(
  format($$select s.amount_minor from public.expense_splits s join pg_temp.m m on m.id = s.member_id
           where s.expense_id = %L order by m.phone$$,
    public.add_expense(pg_temp.expense('00000000-0000-0000-0000-00000000a214', 101,
      format('[{"member_id": "%s", "amount_minor": 101}]', pg_temp.mid('+919100000002')),
      format('[{"member_id": "%s", "amount_minor": 50, "percent_bp": 5000}, {"member_id": "%s", "amount_minor": 51, "percent_bp": 5000}]',
             pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'percent')::jsonb)),
  $$values (50::bigint), (51)$$,
  'add_expense: a tied leftover paisa goes to the payer first, even when listed second');

-- Rejections.
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a215', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s", "amount_minor": 500, "percent_bp": 9000}, {"member_id": "%s", "amount_minor": 500, "percent_bp": 1000}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'percent')),
  '22023', null, 'add_expense: 50/50 amounts with 9000/1000 bp (sums fine, allocation wrong) are rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a216', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s", "amount_minor": 500, "shares": 9}, {"member_id": "%s", "amount_minor": 500, "shares": 1}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'shares')),
  '22023', null, 'add_expense: 50/50 amounts with 9:1 shares are rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a217', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s", "amount_minor": 334, "percent_bp": 3334}, {"member_id": "%s", "amount_minor": 666, "percent_bp": 6666}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'percent')),
  '22023', null, 'add_expense: a leftover paisa given to the wrong member is rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a218', 101,
    format('[{"member_id": "%s", "amount_minor": 101}]', pg_temp.mid('+919100000002')),
    format('[{"member_id": "%s", "amount_minor": 51, "percent_bp": 5000}, {"member_id": "%s", "amount_minor": 50, "percent_bp": 5000}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'percent')),
  '22023', null, 'add_expense: a tie broken by list order instead of payer-first is rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a219', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s", "amount_minor": 500, "shares": 0}, {"member_id": "%s", "amount_minor": 500, "shares": 1}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'shares')),
  '22023', null, 'add_expense: a zero share is rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a204', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s", "amount_minor": 500}, {"member_id": "%s", "amount_minor": 400}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'exact')),
  '22023', null, 'add_expense: exact splits that do not sum to the amount are rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a205', 1000,
    format('[{"member_id": "%s", "amount_minor": 900}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s"}]', pg_temp.mid('+919100000001')))),
  '22023', null, 'add_expense: payers that do not sum to the amount are rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a206', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s", "amount_minor": 300, "percent_bp": 3000}, {"member_id": "%s", "amount_minor": 700, "percent_bp": 6000}]',
           pg_temp.mid('+919100000001'), pg_temp.mid('+919100000002')), 'percent')),
  '22023', null, 'add_expense: percent splits whose basis points do not sum to 10000 are rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a207', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s"}, {"member_id": "%s"}]', pg_temp.mid('+919100000001'), pg_temp.mid('+919100000001')))),
  '22023', null, 'add_expense: a member twice in the splits is rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a208', 1000,
    '[{"member_id": "00000000-0000-0000-0000-000000008201", "amount_minor": 1000}]',
    format('[{"member_id": "%s"}]', pg_temp.mid('+919100000001')))),
  '22023', null, 'add_expense: a payer from outside the space is rejected');
select throws_ok(pg_temp.call(
    '{"space_id": "00000000-0000-0000-0000-00000000a100", "description": "x", "amount_minor": 1, "payers": [], "splits": []}'),
  '22023', null, 'add_expense: a missing idempotency_key is rejected');
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a209', 0,
    format('[{"member_id": "%s", "amount_minor": 0}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s"}]', pg_temp.mid('+919100000001')))),
  '22023', null, 'add_expense: a zero amount is rejected');

-- X leaves; they can no longer be on a new expense.
reset role;
update public.space_members set left_at = now() where phone = '+919800000009' and space_id = '00000000-0000-0000-0000-00000000a100';
set local role authenticated;
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a210', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s"}, {"member_id": "%s"}]', pg_temp.mid('+919100000001'), pg_temp.mid('+919800000009')))),
  '22023', null, 'add_expense: a departed member in the splits is rejected');
select is((select count(*)::int from public.expenses where space_id = '00000000-0000-0000-0000-00000000a100'),
  5, 'add_expense: rejected calls wrote nothing');

-- B (member by phone) replaying A's key is refused; C (outsider) is refused outright.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000a002", "role": "authenticated"}';
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a201', 10000,
    format('[{"member_id": "%s", "amount_minor": 10000}]', pg_temp.mid('+919100000002')),
    format('[{"member_id": "%s"}]', pg_temp.mid('+919100000002')))),
  'PT409', null, 'add_expense: another member cannot claim someone else''s idempotency key');
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000a003", "role": "authenticated"}';
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a211', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s"}]', pg_temp.mid('+919100000001')))),
  '42501', null, 'add_expense: a non-member is rejected');
select throws_ok($$select public.create_space('Mine', 'flat', '[]', '00000000-0000-0000-0000-00000000a100')$$,
  '42501', null, 'create_space: someone else''s key is refused (RLS, the space is not theirs)');

-- D's phone is unverified.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000a004", "role": "authenticated"}';
select throws_ok($$select public.create_space('Mine', 'flat', '[]')$$, '42501', null,
  'create_space: an unverified caller is rejected');
select throws_ok($$select * from public.lookup_phones(array[public.phone_hash('+919100000001')])$$, '42501', null,
  'lookup_phones: an unverified caller is rejected');

-- Soft-deleted space: A can no longer add to it.
reset role;
update public.spaces set deleted_at = now() where id = '00000000-0000-0000-0000-00000000a100';
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000a001", "role": "authenticated"}';
select throws_ok(pg_temp.call(pg_temp.expense('00000000-0000-0000-0000-00000000a212', 1000,
    format('[{"member_id": "%s", "amount_minor": 1000}]', pg_temp.mid('+919100000001')),
    format('[{"member_id": "%s"}]', pg_temp.mid('+919100000001')))),
  '42501', null, 'add_expense: a soft-deleted space is rejected');

-- lookup_phones as A. Hashes are computed here independently of public.phone_hash.
select is(public.phone_hash('+919100000001'), encode(sha256('+919100000001'::bytea), 'hex'),
  'phone_hash: SHA-256 hex of the E.164 string');
select results_eq(
  $$select phone_hash, user_id, name from public.lookup_phones(array[
      encode(sha256('+919100000001'::bytea), 'hex'),
      upper(encode(sha256('+919100000002'::bytea), 'hex')),
      encode(sha256('+919100000004'::bytea), 'hex'),
      encode(sha256('+919800000009'::bytea), 'hex')]) order by name$$,
  $$values (encode(sha256('+919100000001'::bytea), 'hex'), '00000000-0000-0000-0000-00000000a001'::uuid, 'Asha'),
           (encode(sha256('+919100000002'::bytea), 'hex'), '00000000-0000-0000-0000-00000000a002'::uuid, 'Bilal')$$,
  'lookup_phones: returns only registered hashes, never unverified or unknown numbers');
select is((select count(*)::int from public.lookup_phones('{}')), 0, 'lookup_phones: an empty batch returns nothing');
select throws_ok($$select * from public.lookup_phones(array_fill(encode(sha256('x'::bytea), 'hex'), array[501]))$$,
  '54000', null, 'lookup_phones: batches over 500 are rejected');
select throws_ok($$select * from public.lookup_phones(array['+919100000001'])$$,
  '22023', null, 'lookup_phones: a raw number is rejected');

-- Quota: every hash sent is charged, matched or not; over the quota fails with PT429, uncharged.
-- Lowered to 5 for the test (as postgres); C has not looked anything up yet.
reset role;
update private.settings set value = '5' where key = 'lookup_phones_daily_hashes';
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000a003", "role": "authenticated"}';
select is((select count(*)::int from public.lookup_phones(array[
    encode(sha256('+919100000001'::bytea), 'hex'), encode(sha256('+919800000001'::bytea), 'hex'),
    encode(sha256('+919800000002'::bytea), 'hex')])),
  1, 'lookup_phones quota: 3 of 5 hashes used, unknown hashes included');
select throws_ok($$select * from public.lookup_phones(array_fill(encode(sha256('y'::bytea), 'hex'), array[3]))$$,
  'PT429', null, 'lookup_phones quota: a call that would pass the daily quota is rejected');
select is(
  pg_temp.hint_of($$select * from public.lookup_phones(array_fill(encode(sha256('y'::bytea), 'hex'), array[3]))$$),
  'lookup_quota_exceeded', 'lookup_phones quota: the rejection carries hint lookup_quota_exceeded');
select is((select count(*)::int from public.lookup_phones(array_fill(encode(sha256('y'::bytea), 'hex'), array[2]))),
  0, 'lookup_phones quota: rejected calls were not charged, so the last 2 still fit');
select throws_ok($$select * from public.lookup_phones(array[encode(sha256('z'::bytea), 'hex')])$$,
  'PT429', null, 'lookup_phones quota: once used up, even one hash is rejected');
select throws_ok($$select * from private.lookup_quota$$, '42501', null,
  'lookup_phones quota: clients cannot read the quota table');
select throws_ok($$delete from private.lookup_quota$$, '42501', null,
  'lookup_phones quota: clients cannot reset their usage');
select throws_ok($$update private.settings set value = '1000000'$$, '42501', null,
  'lookup_phones quota: clients cannot raise the limit');
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000a002", "role": "authenticated"}';
select is((select count(*)::int from public.lookup_phones(array[encode(sha256('+919100000001'::bytea), 'hex')])),
  1, 'lookup_phones quota: each user has their own budget');
reset role;
select results_eq(
  $$select user_id, hashes from private.lookup_quota order by user_id$$,
  $$values ('00000000-0000-0000-0000-00000000a001'::uuid, 4), ('00000000-0000-0000-0000-00000000a002'::uuid, 1),
           ('00000000-0000-0000-0000-00000000a003'::uuid, 5)$$,
  'lookup_phones quota: usage is recorded per user per day');

-- Concurrency: two sessions send the same key; the second blocks on the first, then returns its id.
-- Fixtures are committed through a third session, and removed at the end. dblink requires
-- non-superusers to authenticate with a password, and loopback is trust, so the sessions connect
-- back to the server's network address with the local stack's fixed default password.
create function pg_temp.conninfo() returns text language sql as $$
  select format('host=%s dbname=postgres user=postgres password=postgres', host(inet_server_addr()))
$$;
select dblink_connect('setup', pg_temp.conninfo());
select dblink_exec('setup', $$
  begin;
  insert into auth.users (id, phone, phone_confirmed_at) values ('00000000-0000-0000-0000-00000000c001', '919100000101', now());
  insert into public.profiles (id, phone, name) values ('00000000-0000-0000-0000-00000000c001', '+919100000101', 'Race');
  insert into public.spaces (id, name, created_by) values ('00000000-0000-0000-0000-00000000c100', 'Race', '00000000-0000-0000-0000-00000000c001');
  insert into public.space_members (id, space_id, phone, user_id, role) values
    ('00000000-0000-0000-0000-00000000c201', '00000000-0000-0000-0000-00000000c100', '+919100000101', '00000000-0000-0000-0000-00000000c001', 'owner');
  commit;
$$);

create function pg_temp.begin_as_race_user(conn text) returns text language sql as $$
  select dblink_exec(conn, $q$begin; set local role authenticated;
    set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000c001", "role": "authenticated"}'$q$);
$$;
create function pg_temp.race_call(key text, description text) returns text language sql as $$
  select format($q$select public.add_expense('{"space_id": "00000000-0000-0000-0000-00000000c100",
    "idempotency_key": "%s", "description": "%s", "amount_minor": 100,
    "payers": [{"member_id": "00000000-0000-0000-0000-00000000c201", "amount_minor": 100}],
    "splits": [{"member_id": "00000000-0000-0000-0000-00000000c201"}]}')::text$q$, key, description)
$$;
-- Whether backend pid is waiting on a lock, polled for up to 10 s (pg_locks is read live).
create function pg_temp.blocked(pid int) returns boolean language plpgsql as $$
begin
  for i in 1..200 loop
    if exists (select from pg_locks l where l.pid = blocked.pid and not l.granted) then
      return true;
    end if;
    perform pg_sleep(0.05);
  end loop;
  return false;
end $$;

select dblink_connect('s1', pg_temp.conninfo());
select dblink_connect('s2', pg_temp.conninfo());
create temp table s2 as select pid from dblink('s2', 'select pg_backend_pid()') t(pid int);

-- Same payload: both calls return the one expense.
create temp table race (first text, second text);
select pg_temp.begin_as_race_user('s1');
select pg_temp.begin_as_race_user('s2');
insert into race (first) select id from dblink('s1', pg_temp.race_call('00000000-0000-0000-0000-00000000c301', 'Race')) t(id text);
select dblink_send_query('s2', pg_temp.race_call('00000000-0000-0000-0000-00000000c301', 'Race'));
select ok(pg_temp.blocked((select pid from s2)), 'race: the second call waits on the first, uncommitted, insert');
select dblink_exec('s1', 'commit');
update race set second = (select id from dblink_get_result('s2') t(id text));
select * from dblink_get_result('s2') t(id text); -- drains the end-of-results marker
select dblink_exec('s2', 'commit');
select ok((select first is not null and first = second from race),
  'race: concurrent calls with the same key and payload return the same expense id');

-- Different payload: the second call waits, then gets the idempotency conflict.
select pg_temp.begin_as_race_user('s1');
select pg_temp.begin_as_race_user('s2');
select * from dblink('s1', pg_temp.race_call('00000000-0000-0000-0000-00000000c302', 'Race')) t(id text);
select dblink_send_query('s2', pg_temp.race_call('00000000-0000-0000-0000-00000000c302', 'Race, changed'));
select ok(pg_temp.blocked((select pid from s2)), 'race: a changed-payload call also waits on the first insert');
select dblink_exec('s1', 'commit');
select * from dblink_get_result('s2', false) t(id text);
select * from dblink_get_result('s2', false) t(id text);
select matches(dblink_error_message('s2'), 'already used with a different payload',
  'race: concurrent calls with the same key and a different payload get the idempotency conflict');
select dblink_exec('s2', 'rollback');

select results_eq(
  $$select e.idempotency_key::text, e.description, (select count(*)::int from public.expense_payers p where p.expense_id = e.id)
      from public.expenses e where e.space_id = '00000000-0000-0000-0000-00000000c100' order by 1$$,
  $$values ('00000000-0000-0000-0000-00000000c301', 'Race', 1), ('00000000-0000-0000-0000-00000000c302', 'Race', 1)$$,
  'race: exactly one expense and one payer row per key; the changed payload wrote nothing');

select dblink_exec('setup', $$
  begin;
  delete from public.activity where space_id = '00000000-0000-0000-0000-00000000c100';
  delete from public.expense_splits where member_id = '00000000-0000-0000-0000-00000000c201';
  delete from public.expense_payers where member_id = '00000000-0000-0000-0000-00000000c201';
  delete from public.expenses where space_id = '00000000-0000-0000-0000-00000000c100';
  delete from public.space_members where space_id = '00000000-0000-0000-0000-00000000c100';
  delete from public.spaces where id = '00000000-0000-0000-0000-00000000c100';
  delete from auth.users where id = '00000000-0000-0000-0000-00000000c001';
  commit;
$$);
select dblink_disconnect('setup');
select dblink_disconnect('s1');
select dblink_disconnect('s2');

select * from finish();
rollback;
