-- Activity feed and 'Needs you' (#91): activity_feed and needs_you.
-- Callers: A owns space S; B is an accepted member; D was a member and left; P has an account but
-- is still a pending member of S and the pending borrower of L2; O is an outsider; anon has no
-- session. A paid E1 and edited it; B records paying A (pending); A lends B L1 and B records a
-- repayment (pending); A lends P L2, which P has not accepted.
begin;
create extension if not exists pgtap with schema extensions;

select plan(30);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000009101', '919910000001', now()),
  ('00000000-0000-0000-0000-000000009102', '919910000002', now()),
  ('00000000-0000-0000-0000-000000009103', '919910000003', now()),
  ('00000000-0000-0000-0000-000000009104', '919910000004', now()),
  ('00000000-0000-0000-0000-000000009105', '919910000005', now()),
  ('00000000-0000-0000-0000-000000009106', '919910000006', null);
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000009101', '+919910000001', 'Asha'),
  ('00000000-0000-0000-0000-000000009102', '+919910000002', 'Bilal'),
  ('00000000-0000-0000-0000-000000009103', '+919910000003', 'Dev'),
  ('00000000-0000-0000-0000-000000009104', '+919910000004', 'Priya'),
  ('00000000-0000-0000-0000-000000009105', '+919910000005', 'Omar'),
  ('00000000-0000-0000-0000-000000009106', '+919910000006', 'Uma');
insert into public.spaces (id, name, kind, created_by) values
  ('00000000-0000-0000-0000-000000009110', 'Flat 91', 'flat', '00000000-0000-0000-0000-000000009101');
insert into public.space_members (id, space_id, phone, user_id, role) values
  ('00000000-0000-0000-0000-000000009121', '00000000-0000-0000-0000-000000009110', '+919910000001', '00000000-0000-0000-0000-000000009101', 'owner'),
  ('00000000-0000-0000-0000-000000009122', '00000000-0000-0000-0000-000000009110', '+919910000002', '00000000-0000-0000-0000-000000009102', 'member'),
  ('00000000-0000-0000-0000-000000009123', '00000000-0000-0000-0000-000000009110', '+919910000003', '00000000-0000-0000-0000-000000009103', 'member'),
  ('00000000-0000-0000-0000-000000009124', '00000000-0000-0000-0000-000000009110', '+919910000004', null, 'member');

create function pg_temp.login(u text) returns text language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true)
$$;
-- The caller's feed as kind:action, oldest first.
create function pg_temp.feed() returns text language sql as $$
  select string_agg(kind || ':' || action, ' ' order by id) from public.activity_feed()
$$;
create function pg_temp.needs() returns text language sql as $$
  select string_agg(kind || ':' || counterparty || ':' || amount_minor, ' ' order by kind)
    from public.needs_you
$$;
grant execute on all functions in schema pg_temp to public;

-- Hardening.
select ok(not has_function_privilege('anon', 'public.activity_feed(timestamptz, bigint, int, uuid, boolean)', 'execute')
          and not has_table_privilege('anon', 'public.needs_you', 'select')
          and has_function_privilege('authenticated', 'public.activity_feed(timestamptz, bigint, int, uuid, boolean)', 'execute')
          and has_table_privilege('authenticated', 'public.needs_you', 'select'),
  'activity_feed and needs_you are for authenticated only');
select ok(not has_table_privilege('authenticated', 'public.needs_you', 'insert')
          and not has_table_privilege('authenticated', 'public.needs_you', 'delete'),
  'needs_you is read-only');
select ok((select coalesce(c.reloptions @> array['security_invoker=true'], false)
             from pg_class c where c.oid = 'public.needs_you'::regclass)
          and (select p.prosecdef and p.provolatile = 's' and p.proconfig @> array['search_path=""']
                 from pg_proc p where p.oid = 'public.activity_feed(timestamptz, bigint, int, uuid, boolean)'::regprocedure),
  'needs_you reads as the caller; activity_feed is a stable definer with a fixed search_path');

set local role anon;
select throws_ok('select * from public.activity_feed()', '42501', null, 'anon cannot read activity_feed');
select throws_ok('select * from public.needs_you', '42501', null, 'anon cannot read needs_you');
reset role;
set local role authenticated;

-- Fixtures, through the RPCs so activity is written as in the app.
select pg_temp.login('00000000-0000-0000-0000-000000009101');
select lives_ok(format('select public.add_expense(%L)', jsonb_build_object(
    'space_id', '00000000-0000-0000-0000-000000009110', 'idempotency_key', '00000000-0000-0000-0000-000000009a01',
    'description', 'Groceries', 'amount_minor', 9000,
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009121', 'amount_minor', 9000)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009121'),
                                jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009122')))),
  'fixture: A pays 9000 for A and B');
select lives_ok(format('select public.update_expense(%L)', jsonb_build_object(
    'expense_id', (select id from public.expenses where idempotency_key = '00000000-0000-0000-0000-000000009a01'),
    'idempotency_key', '00000000-0000-0000-0000-000000009a02', 'description', 'Groceries and gas', 'amount_minor', 12000,
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009121', 'amount_minor', 12000)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009121'),
                                jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009122')))),
  'fixture: A edits it to 12000');
select lives_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000009a11",
    "direction": "lent", "counterparty_phone": "+919910000002", "principal_minor": 50000}')$$,
  'fixture: A lends B 50000 (L1)');
select lives_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000009a12",
    "direction": "lent", "counterparty_phone": "+919910000004", "principal_minor": 7000}')$$,
  'fixture: A lends P 7000 (L2); P does not accept');

select pg_temp.login('00000000-0000-0000-0000-000000009102');
select lives_ok(format('select public.add_expense(%L)', jsonb_build_object(
    'space_id', '00000000-0000-0000-0000-000000009110', 'idempotency_key', '00000000-0000-0000-0000-000000009a03',
    'description', 'Settle up', 'amount_minor', 3000, 'split_type', 'exact', 'is_settlement', true,
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009122', 'amount_minor', 3000)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009121', 'amount_minor', 3000)))),
  'fixture: B records paying A 3000 (pending)');
select lives_ok($$select public.accept_claim('loan', '00000000-0000-0000-0000-000000009a11')$$,
  'fixture: B accepts L1');
select lives_ok($$select public.record_repayment('{"loan_id": "00000000-0000-0000-0000-000000009a11",
    "idempotency_key": "00000000-0000-0000-0000-000000009a13", "amount_minor": 1000}')$$,
  'fixture: B records repaying A 1000 (pending)');

-- A, an accepted member and the lender: everything in S, L1 and L2.
select pg_temp.login('00000000-0000-0000-0000-000000009101');
select is(pg_temp.feed(),
  'expense:created expense:edited loan:created loan:created settlement:created repayment:recorded',
  'member: A sees S, L1 and L2, oldest first by id');
select ok((select before_amount_minor = 9000 and amount_minor = 12000
                  and before_description = 'Groceries' and description = 'Groceries and gas'
                  and by_me and actor_name = 'Asha' and space_name = 'Flat 91' and my_side is null
             from public.activity_feed() where action = 'edited'),
  'member: an edit carries its before and after values');
select ok((select actor_name = 'Bilal' and not by_me and my_side = 'in' and status = 'pending' and amount_minor = 3000
             from public.activity_feed() where kind = 'settlement'),
  'member: a settle-up to A is in A''s favour');
select ok((select actor_name = 'Bilal' and counterparty = 'Bilal' and my_side = 'in' and status = 'pending'
                  and amount_minor = 1000
             from public.activity_feed() where kind = 'repayment'),
  'member: a repayment to the lender is in the lender''s favour');
-- Pages: newest first by (created_at, id); each page starts strictly below the last row shown.
create temp table feed0 as select row_number() over () as n, f.id, f.created_at from public.activity_feed() f;
create temp table page1 as select f.id, f.created_at from public.activity_feed(null, null, 4) f;
select is((select array_agg(id) from page1), (select array_agg(id order by n) from feed0 where n <= 4),
  'pages: the first page is the four newest');
select ok((select bool_and(a.created_at > b.created_at or (a.created_at = b.created_at and a.id > b.id))
             from feed0 a join feed0 b on b.n = a.n + 1),
  'pages: the feed runs newest first by created_at, then id');
-- Something new lands between the two page loads.
select lives_ok(format('select public.add_expense(%L)', jsonb_build_object(
    'space_id', '00000000-0000-0000-0000-000000009110', 'idempotency_key', '00000000-0000-0000-0000-000000009a04',
    'description', 'Milk', 'amount_minor', 100,
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009121', 'amount_minor', 100)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-000000009121')))),
  'insert between pages: A adds Milk');
create temp table page2 as
  select f.id from public.activity_feed(
    (select created_at from page1 order by created_at, id limit 1),
    (select id from page1 order by created_at, id limit 1), 4) f;
select is((select array_agg(id) from (select id from page1 union all select id from page2) p),
          (select array_agg(id order by n) from feed0),
  'insert between pages: the two pages are the original six, once each and in order');
select is((select count(*)::int from public.activity_feed() where description = 'Milk'), 1,
  'insert between pages: the new row heads the next first page');
select is(pg_temp.needs(), 'repayment:Bilal:1000 settlement:Bilal:3000',
  'member: Needs you lists the settle-up and repayment waiting for A');

-- B, the payer and borrower: the same space and L1, against B; nothing waits for B.
select pg_temp.login('00000000-0000-0000-0000-000000009102');
select is(pg_temp.feed(), 'expense:created expense:edited loan:created settlement:created repayment:recorded expense:created',
  'member: B sees S and L1, not L2');
select ok((select bool_and(my_side = 'out') from public.activity_feed() where kind in ('settlement', 'repayment')),
  'member: what B paid is against B');
select is(pg_temp.needs(), null, 'member: what B recorded never waits for B');

-- P: verified, but a pending member of S and the pending borrower of L2.
select pg_temp.login('00000000-0000-0000-0000-000000009104');
select is((select count(*)::int from public.activity_feed()) + (select count(*)::int from public.needs_you), 0,
  'pending claimant: P sees no activity and nothing waiting');

-- U: a member row linked to an account whose phone is not verified.
reset role;
insert into public.space_members (space_id, phone, user_id, role, accepted_at)
values ('00000000-0000-0000-0000-000000009110', '+919910000006', '00000000-0000-0000-0000-000000009106', 'member', now());
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000009106');
select is((select count(*)::int from public.activity_feed()) + (select count(*)::int from public.needs_you), 0,
  'unverified: U sees nothing');

-- O: an outsider.
select pg_temp.login('00000000-0000-0000-0000-000000009105');
select is((select count(*)::int from public.activity_feed()) + (select count(*)::int from public.needs_you), 0,
  'outsider: O sees nothing');

-- D was a member while all of this happened, then left.
select pg_temp.login('00000000-0000-0000-0000-000000009103');
select is((select count(*)::int from public.activity_feed() where space_id is not null), 4,
  'fixture: D sees S while a member');
reset role;
update public.space_members set left_at = now() where id = '00000000-0000-0000-0000-000000009123';
set local role authenticated;
select is((select count(*)::int from public.activity_feed()) + (select count(*)::int from public.needs_you), 0,
  'departed: D sees nothing once gone');

select * from finish();
rollback;
