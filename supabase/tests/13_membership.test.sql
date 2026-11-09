-- Membership follow-ups (#70): set_member_role, re-adding a former member, idempotency key retention.
-- Callers: A owns space S; B and C are accepted members; P has an account but is still a pending
-- member; X is a number on S with no account; O is an outsider; D has an unverified phone.
begin;
create extension if not exists pgtap with schema extensions;

select plan(52);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000007001', '919700000001', now()),
  ('00000000-0000-0000-0000-000000007002', '919700000002', now()),
  ('00000000-0000-0000-0000-000000007003', '919700000003', now()),
  ('00000000-0000-0000-0000-000000007004', '919700000004', now()),
  ('00000000-0000-0000-0000-000000007006', '919700000006', now()),
  ('00000000-0000-0000-0000-000000007007', '919700000007', null);
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000007001', '+919700000001', 'Asha'),
  ('00000000-0000-0000-0000-000000007002', '+919700000002', 'Bilal'),
  ('00000000-0000-0000-0000-000000007003', '+919700000003', 'Chitra'),
  ('00000000-0000-0000-0000-000000007004', '+919700000004', 'Priya'),
  ('00000000-0000-0000-0000-000000007006', '+919700000006', 'Omar');
insert into public.spaces (id, name, kind, created_by) values
  ('00000000-0000-0000-0000-000000007010', 'Flat 70', 'flat', '00000000-0000-0000-0000-000000007001');
insert into public.space_members (id, space_id, phone, user_id, role) values
  ('00000000-0000-0000-0000-000000007021', '00000000-0000-0000-0000-000000007010', '+919700000001', '00000000-0000-0000-0000-000000007001', 'owner'),
  ('00000000-0000-0000-0000-000000007022', '00000000-0000-0000-0000-000000007010', '+919700000002', '00000000-0000-0000-0000-000000007002', 'member'),
  ('00000000-0000-0000-0000-000000007023', '00000000-0000-0000-0000-000000007010', '+919700000003', '00000000-0000-0000-0000-000000007003', 'member'),
  ('00000000-0000-0000-0000-000000007024', '00000000-0000-0000-0000-000000007010', '+919700000004', null, 'member'),
  ('00000000-0000-0000-0000-000000007025', '00000000-0000-0000-0000-000000007010', '+919700000009', null, 'member');

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
create function pg_temp.role_call(member text, role text, key text) returns text language sql as $$
  select format('select public.set_member_role(%L, %L, %L, %L)', '00000000-0000-0000-0000-000000007010', member, role, key)
$$;
-- An exact expense in S of `amount` paid by `payer` and owed by `taker`.
create function pg_temp.expense(key text, payer text, taker text, amount int, settlement boolean default false)
returns text language sql as $$
  select format('select public.add_expense(%L)', jsonb_build_object(
    'space_id', '00000000-0000-0000-0000-000000007010', 'idempotency_key', key, 'description', 'Fixture',
    'amount_minor', amount, 'split_type', 'exact', 'is_settlement', settlement,
    'payers', jsonb_build_array(jsonb_build_object('member_id', payer, 'amount_minor', amount)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', taker, 'amount_minor', amount))))
$$;
create function pg_temp.balance(member text) returns bigint language sql as $$
  select balance_minor from public.space_member_balances where member_id = member::uuid
$$;
grant execute on all functions in schema pg_temp to public;

-- Hardening.
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
      and p.proname in ('set_member_role', 'write_member_role', 'rejoin_members', 'add_space_members')
      and (not coalesce(p.proconfig @> array['search_path=""'], false)
           or has_function_privilege('anon', p.oid, 'execute')
           or not has_function_privilege('authenticated', p.oid, 'execute'))),
  null,
  'new RPCs and helpers have a fixed search_path and are executable by authenticated only');
select ok(not has_function_privilege('authenticated', 'private.purge_idempotency_keys()', 'execute')
          and not has_function_privilege('anon', 'private.purge_idempotency_keys()', 'execute')
          and not has_function_privilege('authenticated', 'public.guard_member_rejoin()', 'execute'),
  'the purge and the rejoin guard are not executable by clients');
select is((select schedule from cron.job where jobname = 'purge-idempotency-keys'), '17 3 * * *',
  'retention: the purge runs daily through pg_cron');

set local role anon;
select throws_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007022', 'owner', '00000000-0000-0000-0000-000000007101'),
  '42501', null, 'anon cannot call set_member_role');
reset role;
set local role authenticated;

-- set_member_role: denied.
select pg_temp.login('00000000-0000-0000-0000-000000007007');
select throws_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007022', 'owner', '00000000-0000-0000-0000-000000007101'),
  '42501', null, 'set_member_role: unverified D is refused');
select pg_temp.login('00000000-0000-0000-0000-000000007006');
select throws_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007022', 'owner', '00000000-0000-0000-0000-000000007101'),
  '42501', null, 'set_member_role: outsider O is refused');
select pg_temp.login('00000000-0000-0000-0000-000000007002');
select throws_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007022', 'owner', '00000000-0000-0000-0000-000000007102'),
  '42501', null, 'set_member_role: member B cannot promote themselves');
select throws_ok($$update public.space_members set role = 'owner' where id = '00000000-0000-0000-0000-000000007022'$$,
  '42501', null, 'space_members: nor by updating role directly');
select pg_temp.login('00000000-0000-0000-0000-000000007001');
select throws_ok(format('select public.set_member_role(%L, %L, null, %L)', '00000000-0000-0000-0000-000000007010',
    '00000000-0000-0000-0000-000000007022', '00000000-0000-0000-0000-000000007103'),
  '22023', null, 'set_member_role: a role is required');
select throws_ok(pg_temp.role_call(gen_random_uuid()::text, 'owner', '00000000-0000-0000-0000-000000007103'),
  '22023', null, 'set_member_role: an unknown member is rejected');
select is(pg_temp.hint_of(pg_temp.role_call('00000000-0000-0000-0000-000000007024', 'owner', '00000000-0000-0000-0000-000000007104')),
  'not_accepted', 'set_member_role: pending P cannot be promoted');
select is(pg_temp.hint_of(pg_temp.role_call('00000000-0000-0000-0000-000000007021', 'member', '00000000-0000-0000-0000-000000007105')),
  'last_owner', 'set_member_role: the sole owner cannot demote themselves');

-- set_member_role: allowed. A hands over to B, then leaves.
select lives_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007022', 'owner', '00000000-0000-0000-0000-000000007106'),
  'set_member_role: owner A promotes B');
select is((select role::text from public.space_members where id = '00000000-0000-0000-0000-000000007022'), 'owner',
  'set_member_role: B is an owner');
select lives_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007022', 'owner', '00000000-0000-0000-0000-000000007106'),
  'set_member_role: a replay succeeds');
select throws_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007023', 'owner', '00000000-0000-0000-0000-000000007106'),
  'PT409', null, 'set_member_role: the same key for another member is a conflict');
select lives_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007021', 'member', '00000000-0000-0000-0000-000000007107'),
  'set_member_role: A demotes themselves now that B owns S');
select lives_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007021', 'member', '00000000-0000-0000-0000-000000007107'),
  'set_member_role: a replay succeeds after A is no longer an owner');
select throws_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007023', 'owner', '00000000-0000-0000-0000-000000007108'),
  '42501', null, 'set_member_role: A, now a member, cannot promote C');
select lives_ok($$select public.leave_space('00000000-0000-0000-0000-000000007010', '00000000-0000-0000-0000-000000007109')$$,
  'hand-over: A leaves after handing S to B');
select pg_temp.login('00000000-0000-0000-0000-000000007002');
select is(pg_temp.hint_of(pg_temp.role_call('00000000-0000-0000-0000-000000007022', 'member', '00000000-0000-0000-0000-000000007110')),
  'last_owner', 'set_member_role: B, now the sole owner, cannot step down');
select lives_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007023', 'owner', '00000000-0000-0000-0000-000000007111'),
  'set_member_role: B promotes C');
select lives_ok(pg_temp.role_call('00000000-0000-0000-0000-000000007023', 'member', '00000000-0000-0000-0000-000000007112'),
  'set_member_role: and demotes C again, B remaining an owner');
select is((select count(*)::int from public.space_members
            where space_id = '00000000-0000-0000-0000-000000007010' and role = 'owner' and left_at is null), 1,
  'set_member_role: S has one owner, B');

-- Re-adding: X's history is a 200 split, settled; then B removes X at a zero balance.
select lives_ok(pg_temp.expense('00000000-0000-0000-0000-000000007201',
  '00000000-0000-0000-0000-000000007022', '00000000-0000-0000-0000-000000007025', 200), 'fixture: X owes B 200');
select lives_ok(pg_temp.expense('00000000-0000-0000-0000-000000007202',
  '00000000-0000-0000-0000-000000007025', '00000000-0000-0000-0000-000000007022', 200, true), 'fixture: X settles with B');
select lives_ok($$select public.leave_space('00000000-0000-0000-0000-000000007010', '00000000-0000-0000-0000-000000007203',
    '00000000-0000-0000-0000-000000007025')$$, 'fixture: B removes X');
select throws_ok($$update public.space_members set left_at = null where id = '00000000-0000-0000-0000-000000007025'$$,
  '42501', null, 'space_members: an owner cannot bring X back by updating left_at directly');

select pg_temp.login('00000000-0000-0000-0000-000000007006');
select throws_ok($$select public.add_space_members('00000000-0000-0000-0000-000000007010',
    '[{"phone": "+919700000009"}]', '00000000-0000-0000-0000-000000007204')$$,
  '42501', null, 'add_space_members: outsider O cannot re-add X');
select pg_temp.login('00000000-0000-0000-0000-000000007003');
select lives_ok($$select public.add_space_members('00000000-0000-0000-0000-000000007010',
    '[{"phone": "+919700000009", "name": "Xavier"}, {"phone": "+919700000011"}]', '00000000-0000-0000-0000-000000007205')$$,
  'add_space_members: member C re-adds X alongside a new number');
select results_eq($$select id, left_at, accepted_at, role::text, name from public.space_members
                    where space_id = '00000000-0000-0000-0000-000000007010' and phone = '+919700000009'$$,
  $$values ('00000000-0000-0000-0000-000000007025'::uuid, null::timestamptz, null::timestamptz, 'member', 'Xavier')$$,
  'rejoin: X''s row is reactivated as a pending member with the new name');
select is((select count(*)::int from public.expense_splits where member_id = '00000000-0000-0000-0000-000000007025')
          + (select count(*)::int from public.expense_payers where member_id = '00000000-0000-0000-0000-000000007025'), 2,
  'rejoin: X''s history stays on the row');
select is(pg_temp.balance('00000000-0000-0000-0000-000000007025'), 0::bigint, 'rejoin: X starts at a zero balance');
select is((select count(*)::int from public.space_members where phone = '+919700000011' and left_at is null), 1,
  'rejoin: the new number is added alongside');
select lives_ok($$select public.add_space_members('00000000-0000-0000-0000-000000007010',
    '[{"phone": "+919700000011"}, {"phone": "+919700000009", "name": "Xavier"}]', '00000000-0000-0000-0000-000000007205')$$,
  'add_space_members: a replay succeeds');
select is(pg_temp.hint_of($$select public.add_space_members('00000000-0000-0000-0000-000000007010',
    '[{"phone": "+919700000009"}]', '00000000-0000-0000-0000-000000007206')$$),
  'already_member', 'add_space_members: X is active again');
select lives_ok(pg_temp.expense('00000000-0000-0000-0000-000000007207',
  '00000000-0000-0000-0000-000000007023', '00000000-0000-0000-0000-000000007025', 300), 're-add then expense: C pays 300 for X');
select is(pg_temp.balance('00000000-0000-0000-0000-000000007025'), -300::bigint,
  're-add then expense: X owes exactly the new 300');

-- An accepted former member rejoins as a claim for the same user, who accepts it again.
select pg_temp.login('00000000-0000-0000-0000-000000007002');
select lives_ok($$select public.add_space_members('00000000-0000-0000-0000-000000007010',
    '[{"phone": "+919700000001"}]', '00000000-0000-0000-0000-000000007208')$$,
  'add_space_members: owner B re-adds A');
select results_eq($$select id, user_id, accepted_at, role::text from public.space_members
                    where space_id = '00000000-0000-0000-0000-000000007010' and phone = '+919700000001'$$,
  $$values ('00000000-0000-0000-0000-000000007021'::uuid, '00000000-0000-0000-0000-000000007001'::uuid,
            null::timestamptz, 'member')$$,
  'rejoin: A''s row keeps A and is a pending member, not an owner');
select pg_temp.login('00000000-0000-0000-0000-000000007001');
select throws_ok(pg_temp.expense('00000000-0000-0000-0000-000000007209',
  '00000000-0000-0000-0000-000000007021', '00000000-0000-0000-0000-000000007022', 100),
  '42501', null, 'rejoin: A cannot write before accepting');
select lives_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-000000007021')$$,
  'rejoin: A accepts the claim');
select ok(public.is_accepted_member('00000000-0000-0000-0000-000000007010'), 'rejoin: A is an accepted member again');

-- A former member who left with a balance (a rejected claim departs whatever it is) cannot rejoin.
select pg_temp.login('00000000-0000-0000-0000-000000007002');
select lives_ok(pg_temp.expense('00000000-0000-0000-0000-000000007210',
  '00000000-0000-0000-0000-000000007022', '00000000-0000-0000-0000-000000007024', 100), 'fixture: B pays 100 for pending P');
select pg_temp.login('00000000-0000-0000-0000-000000007004');
select lives_ok($$select public.reject_claim('space_member', '00000000-0000-0000-0000-000000007024')$$,
  'fixture: P rejects the claim, leaving a balance of -100');
select pg_temp.login('00000000-0000-0000-0000-000000007002');
select is(pg_temp.hint_of($$select public.add_space_members('00000000-0000-0000-0000-000000007010',
    '[{"phone": "+919700000004"}]', '00000000-0000-0000-0000-000000007211')$$),
  'balance_not_zero', 'add_space_members: P''s number cannot rejoin onto a non-zero departed balance');
select ok((select left_at is not null and rejected_at is not null from public.space_members
            where id = '00000000-0000-0000-0000-000000007024'), 'rejoin: P''s row is unchanged');

-- Retention: keys older than 30 days are purged; younger ones are kept.
reset role;
insert into private.idempotency_keys (user_id, key, kind, fingerprint, created_at) values
  ('00000000-0000-0000-0000-000000007001', '00000000-0000-0000-0000-000000007301', 'leave_space', 'f', now() - interval '31 days'),
  ('00000000-0000-0000-0000-000000007001', '00000000-0000-0000-0000-000000007302', 'leave_space', 'f', now() - interval '29 days');
update private.idempotency_keys set created_at = now() - interval '31 days'
 where user_id = '00000000-0000-0000-0000-000000007003' and key = '00000000-0000-0000-0000-000000007205';
select cmp_ok(private.purge_idempotency_keys(), '>=', 2, 'retention: the purge deletes the expired keys');
select is((select array_agg(key::text order by key) from private.idempotency_keys
            where key in ('00000000-0000-0000-0000-000000007301', '00000000-0000-0000-0000-000000007302',
                          '00000000-0000-0000-0000-000000007205')),
  array['00000000-0000-0000-0000-000000007302'], 'retention: only the 29-day-old key is left');
select ok(exists (select from private.idempotency_keys where key = '00000000-0000-0000-0000-000000007208'),
  'retention: keys used today are kept');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000007003');
select throws_ok($$select private.purge_idempotency_keys()$$, '42501', null, 'retention: a client cannot run the purge');
select lives_ok($$select public.add_space_members('00000000-0000-0000-0000-000000007010',
    '[{"phone": "+919700000012"}]', '00000000-0000-0000-0000-000000007205')$$,
  'retention: after the window, C''s purged key runs as a new call instead of conflicting');

select * from finish();
rollback;
