-- Account deletion (#74). A and D share space S (a rent expense D paid, a settle-up D disputed) and
-- a loan A lent D; A also recorded D's number in space P, which D never accepted. X is unrelated.
-- D deletes the account: A's balances and history read exactly as before, only D's account goes,
-- a second call is a no-op, and the number signing up again inherits only the never-claimed P row.
begin;
create extension if not exists pgtap with schema extensions;

select plan(22);

-- Linking is deferred to commit; fire it at each statement so this transaction can observe it.
set constraints auth.link_verified_phone immediate;

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-0000000d0001', '919660000001', now()),
  ('00000000-0000-0000-0000-0000000d0002', '919660000002', now()),
  ('00000000-0000-0000-0000-0000000d0003', '919660000003', now());
update public.profiles set name = 'Asha' where id = '00000000-0000-0000-0000-0000000d0001';
update public.profiles set name = 'Dev', upi_id = 'dev@okaxis' where id = '00000000-0000-0000-0000-0000000d0002';
insert into public.friends (user_id, friend_phone, friend_id) values
  ('00000000-0000-0000-0000-0000000d0002', '+919660000001', '00000000-0000-0000-0000-0000000d0001'),
  ('00000000-0000-0000-0000-0000000d0001', '+919660000002', '00000000-0000-0000-0000-0000000d0002');

insert into public.spaces (id, name, created_by) values
  ('00000000-0000-0000-0000-0000000d0101', 'Flat', '00000000-0000-0000-0000-0000000d0001'),
  ('00000000-0000-0000-0000-0000000d0102', 'Trip', '00000000-0000-0000-0000-0000000d0001');
insert into public.space_members (id, space_id, phone, user_id, role) values
  ('00000000-0000-0000-0000-0000000d0201', '00000000-0000-0000-0000-0000000d0101', '+919660000001', '00000000-0000-0000-0000-0000000d0001', 'owner'),
  ('00000000-0000-0000-0000-0000000d0202', '00000000-0000-0000-0000-0000000d0101', '+919660000002', '00000000-0000-0000-0000-0000000d0002', 'member'),
  ('00000000-0000-0000-0000-0000000d0203', '00000000-0000-0000-0000-0000000d0102', '+919660000001', '00000000-0000-0000-0000-0000000d0001', 'owner'),
  ('00000000-0000-0000-0000-0000000d0204', '00000000-0000-0000-0000-0000000d0102', '+919660000002', null, 'member');
-- Linked to D on verification, never accepted: a pending claim.
update public.space_members set user_id = '00000000-0000-0000-0000-0000000d0002'
 where id = '00000000-0000-0000-0000-0000000d0204';

-- D records the rent (so D is the actor in A's history) and disputes A's settle-up.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000d0002", "role": "authenticated"}';
insert into public.expenses (id, space_id, description, amount_minor) values
  ('00000000-0000-0000-0000-0000000d0301', '00000000-0000-0000-0000-0000000d0101', 'Rent', 1000);
insert into public.expense_payers (expense_id, member_id, amount_minor) values
  ('00000000-0000-0000-0000-0000000d0301', '00000000-0000-0000-0000-0000000d0202', 1000);
insert into public.expense_splits (expense_id, member_id, split_type, amount_minor) values
  ('00000000-0000-0000-0000-0000000d0301', '00000000-0000-0000-0000-0000000d0201', 'exact', 500),
  ('00000000-0000-0000-0000-0000000d0301', '00000000-0000-0000-0000-0000000d0202', 'exact', 500);
insert into public.expenses (id, space_id, description, amount_minor, is_settlement, created_by,
                             disputed_by, disputed_at, dispute_reason) values
  ('00000000-0000-0000-0000-0000000d0302', '00000000-0000-0000-0000-0000000d0101', 'Settle up', 200, true,
   '00000000-0000-0000-0000-0000000d0001', '00000000-0000-0000-0000-0000000d0002', now(), 'Never received it');
insert into public.expense_payers (expense_id, member_id, amount_minor) values
  ('00000000-0000-0000-0000-0000000d0302', '00000000-0000-0000-0000-0000000d0201', 200);
insert into public.expense_splits (expense_id, member_id, split_type, amount_minor) values
  ('00000000-0000-0000-0000-0000000d0302', '00000000-0000-0000-0000-0000000d0202', 'exact', 200);
insert into public.loans (id, lender_phone, borrower_phone, lender_id, borrower_id, principal_minor, schedule_type, created_by) values
  ('00000000-0000-0000-0000-0000000d0501', '+919660000001', '+919660000002', '00000000-0000-0000-0000-0000000d0001',
   '00000000-0000-0000-0000-0000000d0002', 100000, 'flexible', '00000000-0000-0000-0000-0000000d0002');
insert into private.invite_links (id, token_hash, kind, subject_id, target_phone, issuer_id, idempotency_key, fingerprint) values
  ('00000000-0000-0000-0000-0000000d0601', '\x01', 'space', '00000000-0000-0000-0000-0000000d0204', '+919660000009',
   '00000000-0000-0000-0000-0000000d0002', gen_random_uuid(), 'f');
reset request.jwt.claims;

-- Everything the caller can read of the shared ledgers, through RLS. A claim nobody accepted is
-- compared without its link: deletion releases it.
create function pg_temp.ledger() returns text language sql as $$
  select jsonb_build_object(
    'balances', (select jsonb_agg(to_jsonb(b) - 'user_id' order by b.member_id) from public.space_member_balances b),
    'members', (select jsonb_agg(case when m.accepted_at is null then to_jsonb(m) - 'user_id' else to_jsonb(m) end
                                 order by m.id) from public.space_members m),
    'expenses', (select jsonb_agg(to_jsonb(e) order by e.id) from public.expenses e),
    'payers', (select jsonb_agg(to_jsonb(p) order by p.expense_id, p.member_id) from public.expense_payers p),
    'splits', (select jsonb_agg(to_jsonb(s) order by s.expense_id, s.member_id) from public.expense_splits s),
    'loans', (select jsonb_agg(to_jsonb(l) order by l.id) from public.loans l),
    'activity', (select jsonb_agg(to_jsonb(a) order by a.id) from public.activity a))::text
$$;
create temp table snap (v text);
grant all on snap to public;

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000d0001", "role": "authenticated"}';
insert into snap select pg_temp.ledger();
select results_eq(
  $$select balance_minor from public.space_member_balances where space_id = '00000000-0000-0000-0000-0000000d0101' order by member_id$$,
  $$values (-500::bigint), (500::bigint)$$, 'before: A owes D 500 in the Flat');
select is((select count(*)::int from public.activity), 3, 'before: A reads the Flat''s and the loan''s history');
reset role;

-- Caller only: no arguments to aim it with, and nobody without a session.
select is((select array_agg(pg_get_function_identity_arguments(oid)) from pg_proc
            where pronamespace = 'public'::regnamespace and proname = 'delete_account'),
  array[''], 'delete_account takes no arguments, so it can only act on auth.uid()');
set local role anon;
select throws_ok($$select public.delete_account()$$, '42501', null, 'anon cannot call delete_account');
reset role;
set local role authenticated;
set local request.jwt.claims to '{"role": "authenticated"}';
select throws_ok($$select public.delete_account()$$, '42501', null, 'a caller without a user id is refused');

set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000d0002", "role": "authenticated"}';
select lives_ok('select public.delete_account()', 'D deletes the account');
select is((select count(*)::int from public.spaces) + (select count(*)::int from public.loans)
          + (select count(*)::int from public.profiles), 0, 'D''s old token reads nothing');
reset role;

select results_eq(
  $$select name, upi_id, phone::text, deleted_at is not null from public.profiles where id = '00000000-0000-0000-0000-0000000d0002'$$,
  $$values ('Deleted user', null::text, null::text, true)$$,
  'the profile stays as a tombstone named Deleted user, without UPI id or phone');
select results_eq(
  $$select id from auth.users where id::text like '00000000-0000-0000-0000-0000000d000_' order by id$$,
  $$values ('00000000-0000-0000-0000-0000000d0001'::uuid), ('00000000-0000-0000-0000-0000000d0003'::uuid)$$,
  'only the caller''s auth user is deleted');
select results_eq(
  $$select name, phone::text, deleted_at is null from public.profiles where id::text like '00000000-0000-0000-0000-0000000d000_' and id <> '00000000-0000-0000-0000-0000000d0002' order by id$$,
  $$values ('Asha', '+919660000001', true), (null, '+919660000003', true)$$,
  'other profiles are untouched');
select results_eq(
  $$select user_id, friend_phone::text, friend_id from public.friends where friend_phone in ('+919660000001', '+919660000002')$$,
  $$values ('00000000-0000-0000-0000-0000000d0001'::uuid, '+919660000002', null::uuid)$$,
  'D''s friends list is deleted; A''s entry for D keeps the number A typed, unlinked');
select is((select dispute_reason from public.expenses where id = '00000000-0000-0000-0000-0000000d0302'),
  'Never received it', 'D''s dispute reason is kept');
select ok((select revoked_at is not null from private.invite_links where id = '00000000-0000-0000-0000-0000000d0601'),
  'invite links D issued are revoked');

set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000d0001", "role": "authenticated"}';
select is(pg_temp.ledger(), (select v from snap),
  'A''s balances, members, expenses, allocations, loans and activity are unchanged, bar the released claim');
select results_eq(
  $$select balance_minor from public.space_member_balances where space_id = '00000000-0000-0000-0000-0000000d0101' order by member_id$$,
  $$values (-500::bigint), (500::bigint)$$, 'after: A still owes D''s tombstone 500');

-- Idempotent: the token outlives the auth user, so a retry after a lost response must succeed.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000d0002", "role": "authenticated"}';
select lives_ok('select public.delete_account()', 'a second delete_account is a no-op');
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000d0001", "role": "authenticated"}';
select is(pg_temp.ledger(), (select v from snap), 'and changes nothing for A');
reset role;

-- The same number signs up again: a new user, linked only to the row nobody had claimed.
select lives_ok(
  $$insert into auth.users (id, phone, phone_confirmed_at) values ('00000000-0000-0000-0000-0000000d0004', '919660000002', now())$$,
  'the released number can sign up again');
select results_eq(
  $$select id, user_id, accepted_at is not null from public.space_members where phone = '+919660000002' order by id$$,
  $$values ('00000000-0000-0000-0000-0000000d0202'::uuid, '00000000-0000-0000-0000-0000000d0002'::uuid, true),
           ('00000000-0000-0000-0000-0000000d0204'::uuid, '00000000-0000-0000-0000-0000000d0004'::uuid, false)$$,
  'it is linked to the never-claimed Trip row as a pending claim; the accepted Flat row stays the tombstone''s');
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-0000000d0004", "role": "authenticated"}';
select results_eq(
  $$select (select array_agg(id) from public.spaces), (select count(*)::int from public.loans),
           (select count(*)::int from public.expenses), (select name from public.profiles where id = '00000000-0000-0000-0000-0000000d0004')$$,
  $$values (array['00000000-0000-0000-0000-0000000d0102'::uuid], 0, 0, null::text)$$,
  'it reads only the Trip: none of the old loans, expenses or profile');
reset role;

-- The cascade that replaced profiles_id_fkey: a live profile goes with its auth user, a tombstone stays.
delete from auth.users where id = '00000000-0000-0000-0000-0000000d0003';
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-0000000d0003'),
  0, 'deleting an auth user still removes its live profile');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-0000000d0002'),
  1, 'the tombstone outlives its auth user');

select * from finish();
rollback;
