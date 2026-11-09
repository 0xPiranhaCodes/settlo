-- Phone linking (#9): A records spaces S1, S2, S6 and loans L1 (A lends), L2 (A borrows) against N's
-- number before N joins. N reads nothing until verifying; verifying links every row as a pending
-- claim, which N may read but not write; N accepts S1 and L1 and rejects S2 and L2; X, another
-- verified user, can settle none of them. U changes number (S3, S5 on the old one, S4 on the new).
-- N deletes the account and N2 verifies the recycled number. Regression tests for the PR #38 review.
begin;
create extension if not exists pgtap with schema extensions;

select plan(102);

-- Linking is deferred to commit; fire it at each statement so this transaction can observe it.
set constraints auth.link_verified_phone immediate;

create function pg_temp.affected(q text) returns int language plpgsql as $$
declare
  n int;
begin
  execute q;
  get diagnostics n = row_count;
  return n;
end $$;

-- [+policy] / [-policy] tags, as in 03_rls; the policies this migration recreates or regates need both.
create temp table covered (tag text not null);
grant all on covered to public;
create function pg_temp.tagged(tap text) returns text language sql as $$
  insert into pg_temp.covered select m[1] from regexp_matches(tap, '\[([+-][a-z_]+)\]', 'g') m;
  select tap;
$$;

-- Hardening: every security definer function in public has a fixed empty search_path and no
-- anon/public execute; the claim RPCs are callable by authenticated, the triggers by nobody.
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef
      and not (p.proconfig @> array['search_path=""'])),
  null, 'every security definer function in public has search_path ''''');
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef
      and (has_function_privilege('anon', p.oid, 'execute')
           or exists (select from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                       where a.grantee = 0 and a.privilege_type = 'EXECUTE'))),
  null, 'no security definer function in public is executable by anon or public');
select ok(
  has_function_privilege('authenticated', 'public.accept_claim(text, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.reject_claim(text, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.delete_account()', 'execute'),
  'authenticated can call accept_claim, reject_claim and delete_account');
select ok(
  not has_function_privilege('authenticated', 'public.link_verified_phone()', 'execute')
  and not has_function_privilege('authenticated', 'public.stamp_own_acceptance()', 'execute')
  and not has_function_privilege('authenticated', 'public.guard_phone_change()', 'execute')
  and not has_function_privilege('authenticated', 'public.release_pending_claims(uuid, text)', 'execute'),
  'authenticated cannot call the linking triggers or release_pending_claims');

-- A and X sign up already verified: the insert itself creates their profiles. N and U are mid-OTP.
insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-00000000f001', '919000000011', now()),
  ('00000000-0000-0000-0000-00000000f003', '919000000013', now());
insert into auth.users (id, phone) values
  ('00000000-0000-0000-0000-00000000f002', '919000000012'),
  ('00000000-0000-0000-0000-00000000f004', '919000000014');

select results_eq(
  $$select id, phone::text from public.profiles where id::text like '00000000-0000-0000-0000-00000000f00_' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f001'::uuid, '+919000000011'),
           ('00000000-0000-0000-0000-00000000f003'::uuid, '+919000000013')$$,
  'a verified sign-up creates the profile with the E.164 phone; an unverified one does not');
update public.profiles set name = 'A' where id = '00000000-0000-0000-0000-00000000f001';

-- A records everything against N's and U's numbers, through RLS. A's own rows are recorded by phone
-- only and still come out linked to A.
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f001", "role": "authenticated"}';
insert into public.spaces (id, name) values
  ('00000000-0000-0000-0000-00000000f101', 'Flat 402'),
  ('00000000-0000-0000-0000-00000000f102', 'Goa trip'),
  ('00000000-0000-0000-0000-00000000f103', 'U old 1'),
  ('00000000-0000-0000-0000-00000000f104', 'U new'),
  ('00000000-0000-0000-0000-00000000f105', 'U old 2'),
  ('00000000-0000-0000-0000-00000000f106', 'Co-owned');
insert into public.space_members (id, space_id, phone, role) values
  ('00000000-0000-0000-0000-00000000f201', '00000000-0000-0000-0000-00000000f101', '+919000000011', 'owner'),
  ('00000000-0000-0000-0000-00000000f202', '00000000-0000-0000-0000-00000000f101', '+919000000012', 'member'),
  ('00000000-0000-0000-0000-00000000f203', '00000000-0000-0000-0000-00000000f102', '+919000000011', 'owner'),
  ('00000000-0000-0000-0000-00000000f204', '00000000-0000-0000-0000-00000000f102', '+919000000012', 'member'),
  ('00000000-0000-0000-0000-00000000f205', '00000000-0000-0000-0000-00000000f103', '+919000000011', 'owner'),
  ('00000000-0000-0000-0000-00000000f206', '00000000-0000-0000-0000-00000000f103', '+919000000014', 'member'),
  ('00000000-0000-0000-0000-00000000f207', '00000000-0000-0000-0000-00000000f104', '+919000000011', 'owner'),
  ('00000000-0000-0000-0000-00000000f208', '00000000-0000-0000-0000-00000000f104', '+919000000015', 'member'),
  ('00000000-0000-0000-0000-00000000f209', '00000000-0000-0000-0000-00000000f105', '+919000000011', 'owner'),
  ('00000000-0000-0000-0000-00000000f210', '00000000-0000-0000-0000-00000000f105', '+919000000014', 'member'),
  ('00000000-0000-0000-0000-00000000f211', '00000000-0000-0000-0000-00000000f106', '+919000000011', 'owner'),
  ('00000000-0000-0000-0000-00000000f212', '00000000-0000-0000-0000-00000000f106', '+919000000012', 'owner');
insert into public.loans (id, lender_phone, borrower_phone, principal_minor, schedule_type) values
  ('00000000-0000-0000-0000-00000000f501', '+919000000011', '+919000000012', 100000, 'flexible'),
  ('00000000-0000-0000-0000-00000000f502', '+919000000012', '+919000000011', 50000, 'flexible');
do $$ begin
  insert into public.expenses (id, space_id, description, amount_minor)
  values ('00000000-0000-0000-0000-00000000f301', '00000000-0000-0000-0000-00000000f101', 'Rent', 1000);
  insert into public.expense_payers (expense_id, member_id, amount_minor)
  values ('00000000-0000-0000-0000-00000000f301', '00000000-0000-0000-0000-00000000f201', 1000);
  insert into public.expense_splits (expense_id, member_id, split_type, amount_minor)
  values ('00000000-0000-0000-0000-00000000f301', '00000000-0000-0000-0000-00000000f201', 'exact', 1000);
end $$;
insert into public.recurring_expenses (id, space_id, description, amount_minor, template, recurrence, next_run_on)
values ('00000000-0000-0000-0000-00000000f401', '00000000-0000-0000-0000-00000000f101', 'Wifi', 500, '{}', 'monthly', current_date);
insert into public.loan_repayments (id, loan_id, amount_minor, principal_minor)
values ('00000000-0000-0000-0000-00000000f601', '00000000-0000-0000-0000-00000000f501', 10000, 10000);
reset role;

select results_eq(
  $$select id, user_id, accepted_at is not null from public.space_members where id::text like '%f20_' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f201'::uuid, '00000000-0000-0000-0000-00000000f001'::uuid, true),
           ('00000000-0000-0000-0000-00000000f202'::uuid, null::uuid, false),
           ('00000000-0000-0000-0000-00000000f203'::uuid, '00000000-0000-0000-0000-00000000f001'::uuid, true),
           ('00000000-0000-0000-0000-00000000f204'::uuid, null::uuid, false),
           ('00000000-0000-0000-0000-00000000f205'::uuid, '00000000-0000-0000-0000-00000000f001'::uuid, true),
           ('00000000-0000-0000-0000-00000000f206'::uuid, null::uuid, false),
           ('00000000-0000-0000-0000-00000000f207'::uuid, '00000000-0000-0000-0000-00000000f001'::uuid, true),
           ('00000000-0000-0000-0000-00000000f208'::uuid, null::uuid, false),
           ('00000000-0000-0000-0000-00000000f209'::uuid, '00000000-0000-0000-0000-00000000f001'::uuid, true)$$,
  'the creator''s own number is linked and accepted at insert; other numbers are not');
select results_eq(
  $$select id, lender_id, borrower_id, lender_accepted_at is not null, borrower_accepted_at is not null
      from public.loans where id::text like '%f50_' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f501'::uuid, '00000000-0000-0000-0000-00000000f001'::uuid, null::uuid, true, false),
           ('00000000-0000-0000-0000-00000000f502'::uuid, null::uuid, '00000000-0000-0000-0000-00000000f001'::uuid, false, true)$$,
  'the creator''s side of each loan is linked and accepted at insert; the number''s side is not');

-- N, before verifying: nothing at all.
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f002", "role": "authenticated"}';
select is((select count(*)::int from public.spaces), 0, 'unverified N reads no spaces');
select is((select count(*)::int from public.space_members), 0, 'unverified N reads no members');
select pg_temp.tagged(is((select count(*)::int from public.loans), 0, 'unverified N reads no loans [-loans_select]'));
select is((select count(*)::int from public.activity), 0, 'unverified N reads no activity');
select is((select count(*)::int from public.profiles), 0, 'unverified N reads no profiles');
select throws_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f202')$$,
  '42501', null, 'unverified N cannot accept a claim');
select throws_ok($$select public.reject_claim('loan', '00000000-0000-0000-0000-00000000f501')$$,
  '42501', null, 'unverified N cannot reject a claim');
reset role;

-- N verifies.
update auth.users set phone_confirmed_at = now() where id = '00000000-0000-0000-0000-00000000f002';

select is((select phone::text from public.profiles where id = '00000000-0000-0000-0000-00000000f002'),
  '+919000000012', 'verifying creates N''s profile');
select results_eq(
  $$select id, user_id, accepted_at from public.space_members where phone = '+919000000012' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f202'::uuid, '00000000-0000-0000-0000-00000000f002'::uuid, null::timestamptz),
           ('00000000-0000-0000-0000-00000000f204'::uuid, '00000000-0000-0000-0000-00000000f002'::uuid, null::timestamptz),
           ('00000000-0000-0000-0000-00000000f212'::uuid, '00000000-0000-0000-0000-00000000f002'::uuid, null::timestamptz)$$,
  'verifying links N''s memberships as pending claims');
select results_eq(
  $$select id, lender_id, borrower_id from public.loans where id::text like '%f50_' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f501'::uuid, '00000000-0000-0000-0000-00000000f001'::uuid, '00000000-0000-0000-0000-00000000f002'::uuid),
           ('00000000-0000-0000-0000-00000000f502'::uuid, '00000000-0000-0000-0000-00000000f002'::uuid, '00000000-0000-0000-0000-00000000f001'::uuid)$$,
  'verifying links N''s side of both loans');
select is((select count(*)::int from public.loans
            where id::text like '%f50_' and (lender_accepted_at is null) = (lender_id = '00000000-0000-0000-0000-00000000f002')
              and (borrower_accepted_at is null) = (borrower_id = '00000000-0000-0000-0000-00000000f002')),
  2, 'N''s linked loan sides are still pending');
update public.profiles set name = 'N', upi_id = 'n@upi' where id = '00000000-0000-0000-0000-00000000f002';

-- A cannot learn N's name or UPI id from a link N has not accepted.
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f001", "role": "authenticated"}';
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000f002'),
  0, 'A cannot read N''s profile while every claim is pending');

-- X, a verified stranger, can settle none of N's claims.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f003", "role": "authenticated"}';
select throws_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f202')$$,
  '42501', null, 'X cannot accept N''s membership');
select throws_ok($$select public.reject_claim('space_member', '00000000-0000-0000-0000-00000000f204')$$,
  '42501', null, 'X cannot reject N''s membership');
select throws_ok($$select public.accept_claim('loan', '00000000-0000-0000-0000-00000000f501')$$,
  '42501', null, 'X cannot accept N''s loan side');
select throws_ok($$select public.reject_claim('loan', '00000000-0000-0000-0000-00000000f502')$$,
  '42501', null, 'X cannot reject N''s loan side');
select throws_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f201')$$,
  '42501', null, 'X cannot accept A''s membership either');

-- N reviews: everything recorded against the number is there to read.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f002", "role": "authenticated"}';
select results_eq('select id from public.spaces order by id',
  $$values ('00000000-0000-0000-0000-00000000f101'::uuid), ('00000000-0000-0000-0000-00000000f102'::uuid),
           ('00000000-0000-0000-0000-00000000f106'::uuid)$$,
  'verified N reads every space recorded against the number');
select pg_temp.tagged(results_eq('select id from public.loans order by id',
  $$values ('00000000-0000-0000-0000-00000000f501'::uuid), ('00000000-0000-0000-0000-00000000f502'::uuid)$$,
  'verified N reads both loans recorded against the number [+loans_select]'));
select is((select count(*)::int from public.expenses), 1, 'pending N reads the S1 ledger to review it');
select is((select name from public.profiles where id = '00000000-0000-0000-0000-00000000f001'),
  'A', 'N can see who recorded the claims');
select throws_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f201')$$,
  '42501', null, 'N cannot accept A''s membership');
select throws_ok($$select public.accept_claim('loan_side', '00000000-0000-0000-0000-00000000f501')$$,
  '42501', null, 'an unknown claim kind is refused');

-- A pending claimant is read-only (review finding 1): every write path is refused.
select pg_temp.tagged(throws_ok(
  $$insert into public.space_members (space_id, phone) values ('00000000-0000-0000-0000-00000000f101', '+919000000019')$$,
  '42501', null, 'pending N cannot add a member [-space_members_insert]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.space_members set left_at = now() where id = '00000000-0000-0000-0000-00000000f202'$$),
  0, 'pending N cannot update its membership [-space_members_update]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.spaces set name = 'Mine' where id = '00000000-0000-0000-0000-00000000f106'$$),
  0, 'pending owner N cannot rename S6 [-spaces_update]'));
select pg_temp.tagged(throws_ok(
  $$insert into public.expenses (id, space_id, description, amount_minor, idempotency_key)
    values ('00000000-0000-0000-0000-00000000f399', '00000000-0000-0000-0000-00000000f101', 'Written before accepting claim', 1000,
            '00000000-0000-0000-0000-00000000f398')$$,
  '42501', null, 'pending N cannot add an expense [-expenses_insert]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.expenses set description = 'x' where id = '00000000-0000-0000-0000-00000000f301'$$),
  0, 'pending N cannot edit an expense [-expenses_update]'));
select pg_temp.tagged(throws_ok(
  format('select public.add_expense(%L::jsonb)', jsonb_build_object(
    'space_id', '00000000-0000-0000-0000-00000000f101', 'idempotency_key', '00000000-0000-0000-0000-00000000f397',
    'description', 'Via RPC', 'amount_minor', 1000, 'split_type', 'equal',
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-00000000f202', 'amount_minor', 1000)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-00000000f202')))),
  '42501', null, 'pending N cannot add an expense through add_expense (security invoker) [-expenses_insert]'));
select pg_temp.tagged(throws_ok(
  $$insert into public.expense_payers (expense_id, member_id, amount_minor)
    values ('00000000-0000-0000-0000-00000000f301', '00000000-0000-0000-0000-00000000f202', 1000)$$,
  '42501', null, 'pending N cannot add a payer [-expense_payers_insert]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.expense_payers set amount_minor = amount_minor
                              where expense_id = '00000000-0000-0000-0000-00000000f301'$$),
  0, 'pending N cannot edit a payer [-expense_payers_update]'));
select pg_temp.tagged(is(pg_temp.affected($$delete from public.expense_payers where expense_id = '00000000-0000-0000-0000-00000000f301'$$),
  0, 'pending N cannot remove a payer [-expense_payers_delete]'));
select pg_temp.tagged(throws_ok(
  $$insert into public.expense_splits (expense_id, member_id, split_type, amount_minor)
    values ('00000000-0000-0000-0000-00000000f301', '00000000-0000-0000-0000-00000000f202', 'exact', 0)$$,
  '42501', null, 'pending N cannot add a split [-expense_splits_insert]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.expense_splits set amount_minor = amount_minor
                              where expense_id = '00000000-0000-0000-0000-00000000f301'$$),
  0, 'pending N cannot edit a split [-expense_splits_update]'));
select pg_temp.tagged(is(pg_temp.affected($$delete from public.expense_splits where expense_id = '00000000-0000-0000-0000-00000000f301'$$),
  0, 'pending N cannot remove a split [-expense_splits_delete]'));
select pg_temp.tagged(throws_ok(
  $$insert into public.recurring_expenses (space_id, description, amount_minor, template, recurrence, next_run_on)
    values ('00000000-0000-0000-0000-00000000f101', 'x', 1, '{}', 'monthly', current_date)$$,
  '42501', null, 'pending N cannot add a recurring expense [-recurring_expenses_insert]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.recurring_expenses set description = 'x' where id = '00000000-0000-0000-0000-00000000f401'$$),
  0, 'pending N cannot edit a recurring expense [-recurring_expenses_update]'));
select pg_temp.tagged(throws_ok(
  $$insert into public.loan_repayments (loan_id, amount_minor, principal_minor)
    values ('00000000-0000-0000-0000-00000000f501', 1000, 1000)$$,
  '42501', null, 'pending borrower N cannot record a repayment [-loan_repayments_insert]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-00000000f002'
                              where id = '00000000-0000-0000-0000-00000000f601'$$),
  0, 'pending borrower N cannot confirm a repayment [-loan_repayments_update]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.loans set closed_at = now() where id = '00000000-0000-0000-0000-00000000f502'$$),
  0, 'pending lender N cannot close L2 [-loans_update]'));

-- Accept S1 and L1.
select lives_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f202')$$,
  'N accepts the S1 membership');
select lives_ok($$select public.accept_claim('loan', '00000000-0000-0000-0000-00000000f501')$$,
  'N accepts the borrower side of L1');
select throws_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f202')$$,
  '42501', null, 'an accepted claim cannot be accepted again');
select throws_ok($$select public.reject_claim('space_member', '00000000-0000-0000-0000-00000000f202')$$,
  '42501', null, 'an accepted claim cannot be rejected');

-- Accepted, N writes like any member or party.
select pg_temp.tagged(lives_ok(
  $$insert into public.space_members (space_id, phone) values ('00000000-0000-0000-0000-00000000f101', '+919000000019')$$,
  'accepted N adds a member [+space_members_insert]'));
select pg_temp.tagged(lives_ok(
  $q$do $$ begin
    insert into public.expenses (id, space_id, description, amount_minor)
    values ('00000000-0000-0000-0000-00000000f302', '00000000-0000-0000-0000-00000000f101', 'Gas', 600);
    insert into public.expense_payers (expense_id, member_id, amount_minor)
    values ('00000000-0000-0000-0000-00000000f302', '00000000-0000-0000-0000-00000000f202', 600);
    insert into public.expense_splits (expense_id, member_id, split_type, amount_minor)
    values ('00000000-0000-0000-0000-00000000f302', '00000000-0000-0000-0000-00000000f202', 'exact', 600);
  end $$$q$,
  'accepted N adds an expense with payers and splits [+expenses_insert] [+expense_payers_insert] [+expense_splits_insert]'));
select pg_temp.tagged(lives_ok(
  format('select public.add_expense(%L::jsonb)', jsonb_build_object(
    'space_id', '00000000-0000-0000-0000-00000000f101', 'idempotency_key', '00000000-0000-0000-0000-00000000f397',
    'description', 'Via RPC', 'amount_minor', 1000, 'split_type', 'equal',
    'payers', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-00000000f202', 'amount_minor', 1000)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', '00000000-0000-0000-0000-00000000f202')))),
  'accepted N adds an expense through add_expense [+expenses_insert]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.expenses set description = 'Rent (Nov)' where id = '00000000-0000-0000-0000-00000000f301'$$),
  1, 'accepted N edits an expense [+expenses_update]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.expense_payers set amount_minor = amount_minor
                              where expense_id = '00000000-0000-0000-0000-00000000f301'$$),
  1, 'accepted N edits a payer [+expense_payers_update]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.expense_splits set amount_minor = amount_minor
                              where expense_id = '00000000-0000-0000-0000-00000000f301'$$),
  1, 'accepted N edits a split [+expense_splits_update]'));
select pg_temp.tagged(is(pg_temp.affected($$delete from public.expense_payers where expense_id = '00000000-0000-0000-0000-00000000f302'$$),
  1, 'accepted N removes a payer [+expense_payers_delete]'));
select pg_temp.tagged(is(pg_temp.affected($$delete from public.expense_splits where expense_id = '00000000-0000-0000-0000-00000000f302'$$),
  1, 'accepted N removes a split [+expense_splits_delete]'));
select lives_ok(
  $q$do $$ begin
    insert into public.expense_payers (expense_id, member_id, amount_minor)
    values ('00000000-0000-0000-0000-00000000f302', '00000000-0000-0000-0000-00000000f201', 600);
    insert into public.expense_splits (expense_id, member_id, split_type, amount_minor)
    values ('00000000-0000-0000-0000-00000000f302', '00000000-0000-0000-0000-00000000f201', 'exact', 600);
    set constraints all immediate;
  end $$$q$,
  'accepted N rebalances the expense and it passes the commit-time check');
set constraints all deferred;
set constraints auth.link_verified_phone immediate;
select pg_temp.tagged(lives_ok(
  $$insert into public.recurring_expenses (space_id, description, amount_minor, template, recurrence, next_run_on)
    values ('00000000-0000-0000-0000-00000000f101', 'Milk', 100, '{}', 'monthly', current_date)$$,
  'accepted N adds a recurring expense [+recurring_expenses_insert]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.recurring_expenses set description = 'Wifi 2' where id = '00000000-0000-0000-0000-00000000f401'$$),
  1, 'accepted N edits a recurring expense [+recurring_expenses_update]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-00000000f002'
                              where id = '00000000-0000-0000-0000-00000000f601'$$),
  1, 'accepted borrower N confirms A''s repayment [+loan_repayments_update]'));
select pg_temp.tagged(lives_ok(
  $$insert into public.loan_repayments (loan_id, amount_minor, principal_minor)
    values ('00000000-0000-0000-0000-00000000f501', 1000, 1000)$$,
  'accepted borrower N records a repayment [+loan_repayments_insert]'));

-- Reject S2 and L2.
select lives_ok($$select public.reject_claim('space_member', '00000000-0000-0000-0000-00000000f204')$$,
  'N rejects the S2 membership');
select lives_ok($$select public.reject_claim('loan', '00000000-0000-0000-0000-00000000f502')$$,
  'N rejects the lender side of L2');
select results_eq('select id from public.spaces order by id',
  $$values ('00000000-0000-0000-0000-00000000f101'::uuid), ('00000000-0000-0000-0000-00000000f106'::uuid)$$,
  'N no longer reads S2 after rejecting it');
select pg_temp.tagged(results_eq('select id from public.loans', $$values ('00000000-0000-0000-0000-00000000f501'::uuid)$$,
  'N no longer reads L2 after rejecting its lender side [-loans_select]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.loans set closed_at = now() where id = '00000000-0000-0000-0000-00000000f502'$$),
  0, 'N cannot close L2 after rejecting its lender side [-loans_update]'));
select is((select count(*)::int from public.activity where action = 'rejected'), 0,
  'N does not read the rejection activity of what it rejected');
reset role;

select results_eq(
  $$select id, user_id, accepted_at is not null, rejected_at is not null, left_at is not null
      from public.space_members where id in ('00000000-0000-0000-0000-00000000f202', '00000000-0000-0000-0000-00000000f204') order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f202'::uuid, '00000000-0000-0000-0000-00000000f002'::uuid, true, false, false),
           ('00000000-0000-0000-0000-00000000f204'::uuid, null::uuid, false, true, true)$$,
  'accept keeps the link; reject unlinks the number and ends the membership');
select results_eq(
  $$select id, lender_id, borrower_id, borrower_accepted_at is not null, lender_rejected_at is not null
      from public.loans where id::text like '%f50_' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f501'::uuid, '00000000-0000-0000-0000-00000000f001'::uuid,
            '00000000-0000-0000-0000-00000000f002'::uuid, true, false),
           ('00000000-0000-0000-0000-00000000f502'::uuid, null::uuid,
            '00000000-0000-0000-0000-00000000f001'::uuid, true, true)$$,
  'accept stamps N''s loan side; reject unlinks it');

-- Re-verifying (a new OTP) does not relink what was rejected.
update auth.users set phone_confirmed_at = clock_timestamp() where id = '00000000-0000-0000-0000-00000000f002';
select is((select count(*)::int from public.space_members where id = '00000000-0000-0000-0000-00000000f204' and user_id is not null)
          + (select count(*)::int from public.loans where id = '00000000-0000-0000-0000-00000000f502' and lender_id is not null),
  0, 're-verifying does not relink rejected claims');

-- A, the creator, hears about both rejections and now sees N where N accepted.
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f001", "role": "authenticated"}';
select results_eq(
  $$select space_id, loan_id, actor_id, after from public.activity where action = 'rejected' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f102'::uuid, null::uuid, null::uuid,
            '{"member_id": "00000000-0000-0000-0000-00000000f204", "phone": "+919000000012"}'::jsonb),
           (null::uuid, '00000000-0000-0000-0000-00000000f502'::uuid, null::uuid,
            '{"side": "lender", "phone": "+919000000012"}'::jsonb)$$,
  'reject writes an activity row the creator reads, naming the number and not the caller');
select is((select name from public.profiles where id = '00000000-0000-0000-0000-00000000f002'),
  'N', 'A reads N''s profile once N accepted a shared claim');
select results_eq('select id from public.loans order by id',
  $$values ('00000000-0000-0000-0000-00000000f501'::uuid), ('00000000-0000-0000-0000-00000000f502'::uuid)$$,
  'A still reads both loans');
select pg_temp.tagged(is(pg_temp.affected($$update public.spaces set name = 'Flat 402B' where id = '00000000-0000-0000-0000-00000000f101'$$),
  1, 'accepted owner A renames S1 [+spaces_update]'));
select pg_temp.tagged(is(pg_temp.affected($$update public.loans set closed_at = now() where id = '00000000-0000-0000-0000-00000000f501'$$),
  1, 'lender A closes L1 [+loans_update]'));
reset role;

-- U verifies the old number, accepts S3, leaves S5 pending, then changes number (review finding 2).
update auth.users set phone_confirmed_at = now() where id = '00000000-0000-0000-0000-00000000f004';
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f004", "role": "authenticated"}';
select lives_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f206')$$,
  'U accepts S3 on the old number');
reset role;

-- The reviewer's exploit: only the phone changes, the old confirmation timestamp stays.
update auth.users set phone = '919000000015' where id = '00000000-0000-0000-0000-00000000f004';
select is((select user_id from public.space_members where id = '00000000-0000-0000-0000-00000000f208'),
  null, 'a phone change with a stale confirmation links nothing on the new number');
select is((select phone_confirmed_at from auth.users where id = '00000000-0000-0000-0000-00000000f004'),
  null, 'a phone change without a fresh confirmation unverifies the account');
select results_eq(
  $$select id, user_id, accepted_at is not null from public.space_members where id in
      ('00000000-0000-0000-0000-00000000f206', '00000000-0000-0000-0000-00000000f210') order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f206'::uuid, '00000000-0000-0000-0000-00000000f004'::uuid, true),
           ('00000000-0000-0000-0000-00000000f210'::uuid, null::uuid, false)$$,
  'a phone change keeps accepted links and releases pending claims on the old number');
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f004", "role": "authenticated"}';
select is((select count(*)::int from public.spaces), 0, 'U reads nothing until the new number is confirmed');
reset role;

update auth.users set phone_confirmed_at = clock_timestamp() where id = '00000000-0000-0000-0000-00000000f004';
select results_eq(
  $$select user_id, accepted_at from public.space_members where id = '00000000-0000-0000-0000-00000000f208'$$,
  $$values ('00000000-0000-0000-0000-00000000f004'::uuid, null::timestamptz)$$,
  'confirming the new number links its claims as pending');
select is((select phone::text from public.profiles where id = '00000000-0000-0000-0000-00000000f004'),
  '+919000000015', 'confirming the new number moves the profile to it');
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f004", "role": "authenticated"}';
select results_eq('select id from public.spaces order by id',
  $$values ('00000000-0000-0000-0000-00000000f103'::uuid), ('00000000-0000-0000-0000-00000000f104'::uuid)$$,
  'U reads the accepted S3 and the new number''s S4, not the old number''s pending S5');
reset role;

update auth.users set phone_confirmed_at = null where id = '00000000-0000-0000-0000-00000000f004';
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f004", "role": "authenticated"}';
select is((select count(*)::int from public.spaces), 0, 'unverifying removes U''s access');
reset role;
update auth.users set phone_confirmed_at = clock_timestamp() where id = '00000000-0000-0000-0000-00000000f004';
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f004", "role": "authenticated"}';
select results_eq('select id from public.spaces order by id',
  $$values ('00000000-0000-0000-0000-00000000f103'::uuid), ('00000000-0000-0000-0000-00000000f104'::uuid)$$,
  're-verifying restores exactly U''s own spaces');

-- N leaves S1, then deletes the account (review finding 3).
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f002", "role": "authenticated"}';
select pg_temp.tagged(is(pg_temp.affected($$update public.space_members set left_at = now() where id = '00000000-0000-0000-0000-00000000f202'$$),
  1, 'accepted N leaves S1 [+space_members_update]'));
select lives_ok('select public.delete_account()', 'N deletes the account');
select is((select count(*)::int from public.spaces), 0, 'the deleted account reads nothing');
reset role;
select results_eq(
  $$select name, upi_id, phone::text, deleted_at is not null from public.profiles where id = '00000000-0000-0000-0000-00000000f002'$$,
  $$values (null::text, null::text, null::text, true)$$,
  'account deletion keeps a tombstone profile with name, UPI id and phone cleared');
select is((select phone from auth.users where id = '00000000-0000-0000-0000-00000000f002'),
  null, 'account deletion releases the number from the auth identity');
select is((select user_id from public.space_members where id = '00000000-0000-0000-0000-00000000f212'),
  null, 'account deletion releases pending claims');
select throws_ok($$update public.profiles set phone = null where id = '00000000-0000-0000-0000-00000000f001'$$,
  '23514', null, 'only a deleted profile may have no phone');

-- N2 gets the recycled number and verifies it.
select lives_ok(
  $$insert into auth.users (id, phone, phone_confirmed_at) values ('00000000-0000-0000-0000-00000000f005', '919000000012', now())$$,
  'a new holder can verify a recycled number');
select results_eq(
  $$select id, user_id, accepted_at is not null from public.space_members where phone = '+919000000012' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f202'::uuid, '00000000-0000-0000-0000-00000000f002'::uuid, true),
           ('00000000-0000-0000-0000-00000000f204'::uuid, null::uuid, false),
           ('00000000-0000-0000-0000-00000000f212'::uuid, '00000000-0000-0000-0000-00000000f005'::uuid, false)$$,
  'N2 is linked only to the never-claimed S6 row, as a pending claim; N''s accepted history stays N''s');
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f005", "role": "authenticated"}';
select results_eq('select id from public.spaces', $$values ('00000000-0000-0000-0000-00000000f106'::uuid)$$,
  'N2 reads only S6');
select is((select count(*)::int from public.loans), 0, 'N2 inherits none of N''s loans');
select results_eq('select id from public.profiles where id <> ''00000000-0000-0000-0000-00000000f001''',
  $$values ('00000000-0000-0000-0000-00000000f005'::uuid)$$,
  'N2 does not see N''s tombstone');
reset role;
set local role anon;
select throws_ok($$select public.delete_account()$$, '42501', null, 'anon cannot call delete_account');
reset role;

select is(
  (select array_agg(t order by t) from (
     select sign || p as t from unnest(array[
       'space_members_insert', 'space_members_update', 'spaces_update', 'expenses_insert', 'expenses_update',
       'expense_payers_insert', 'expense_payers_update', 'expense_payers_delete',
       'expense_splits_insert', 'expense_splits_update', 'expense_splits_delete',
       'recurring_expenses_insert', 'recurring_expenses_update', 'loans_select', 'loans_update',
       'loan_repayments_insert', 'loan_repayments_update']) p
     cross join (values ('+'), ('-')) v(sign)
     except select tag from pg_temp.covered) missing),
  null, 'every policy this migration recreates or regates has an allowed (+) and a denied (-) tagged test');

select * from finish();
rollback;
