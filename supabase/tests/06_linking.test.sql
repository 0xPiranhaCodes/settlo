-- Phone linking (#9): A records spaces S1, S2 and loans L1 (A lends), L2 (A borrows) against N's
-- number before N joins. N reads nothing until verifying; verifying links every row as a pending
-- claim; N accepts S1 and L1 and rejects S2 and L2; X, another verified user, can settle none of them.
begin;
create extension if not exists pgtap with schema extensions;

select plan(50);

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

-- [+policy] / [-policy] tags, as in 03_rls; the policies this migration recreates need both.
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
  and not has_function_privilege('authenticated', 'public.stamp_own_acceptance()', 'execute'),
  'authenticated cannot call the linking triggers');

-- A and X sign up already verified: the insert itself creates their profiles. N is mid-OTP.
insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-00000000f001', '919000000011', now()),
  ('00000000-0000-0000-0000-00000000f003', '919000000013', now());
insert into auth.users (id, phone) values ('00000000-0000-0000-0000-00000000f002', '919000000012');

select results_eq(
  $$select id, phone::text from public.profiles where id::text like '00000000-0000-0000-0000-00000000f00_' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f001'::uuid, '+919000000011'),
           ('00000000-0000-0000-0000-00000000f003'::uuid, '+919000000013')$$,
  'a verified sign-up creates the profile with the E.164 phone; an unverified one does not');
update public.profiles set name = 'A' where id = '00000000-0000-0000-0000-00000000f001';

-- A records everything against N's number, through RLS.
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f001", "role": "authenticated"}';
insert into public.spaces (id, name) values
  ('00000000-0000-0000-0000-00000000f101', 'Flat 402'),
  ('00000000-0000-0000-0000-00000000f102', 'Goa trip');
insert into public.space_members (id, space_id, phone, user_id, role) values
  ('00000000-0000-0000-0000-00000000f201', '00000000-0000-0000-0000-00000000f101', '+919000000011', '00000000-0000-0000-0000-00000000f001', 'owner'),
  ('00000000-0000-0000-0000-00000000f202', '00000000-0000-0000-0000-00000000f101', '+919000000012', null, 'member');
insert into public.space_members (id, space_id, phone, user_id, role) values
  ('00000000-0000-0000-0000-00000000f203', '00000000-0000-0000-0000-00000000f102', '+919000000011', '00000000-0000-0000-0000-00000000f001', 'owner'),
  ('00000000-0000-0000-0000-00000000f204', '00000000-0000-0000-0000-00000000f102', '+919000000012', null, 'member');
insert into public.loans (id, lender_phone, borrower_phone, lender_id, borrower_id, principal_minor, schedule_type) values
  ('00000000-0000-0000-0000-00000000f501', '+919000000011', '+919000000012', '00000000-0000-0000-0000-00000000f001', null, 100000, 'flexible'),
  ('00000000-0000-0000-0000-00000000f502', '+919000000012', '+919000000011', null, '00000000-0000-0000-0000-00000000f001', 50000, 'flexible');
reset role;

select results_eq(
  $$select id, accepted_at is not null from public.space_members where id::text like '%f20_' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f201'::uuid, true), ('00000000-0000-0000-0000-00000000f202'::uuid, false),
           ('00000000-0000-0000-0000-00000000f203'::uuid, true), ('00000000-0000-0000-0000-00000000f204'::uuid, false)$$,
  'the creator''s own membership is accepted at insert; the number''s is not');
select results_eq(
  $$select id, lender_accepted_at is not null, borrower_accepted_at is not null from public.loans where id::text like '%f50_' order by id$$,
  $$values ('00000000-0000-0000-0000-00000000f501'::uuid, true, false), ('00000000-0000-0000-0000-00000000f502'::uuid, false, true)$$,
  'the creator''s side of each loan is accepted at insert; the number''s side is not');

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
           ('00000000-0000-0000-0000-00000000f204'::uuid, '00000000-0000-0000-0000-00000000f002'::uuid, null::timestamptz)$$,
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

-- N reviews: everything recorded against the number is there to review.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f002", "role": "authenticated"}';
select results_eq('select id from public.spaces order by id',
  $$values ('00000000-0000-0000-0000-00000000f101'::uuid), ('00000000-0000-0000-0000-00000000f102'::uuid)$$,
  'verified N reads both spaces recorded against the number');
select pg_temp.tagged(results_eq('select id from public.loans order by id',
  $$values ('00000000-0000-0000-0000-00000000f501'::uuid), ('00000000-0000-0000-0000-00000000f502'::uuid)$$,
  'verified N reads both loans recorded against the number [+loans_select]'));
select is((select name from public.profiles where id = '00000000-0000-0000-0000-00000000f001'),
  'A', 'N can see who recorded the claims');
select throws_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f201')$$,
  '42501', null, 'N cannot accept A''s membership');
select throws_ok($$select public.accept_claim('loan_side', '00000000-0000-0000-0000-00000000f501')$$,
  '42501', null, 'an unknown claim kind is refused');

-- Accept S1 and L1.
select lives_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f202')$$,
  'N accepts the S1 membership');
select lives_ok($$select public.accept_claim('loan', '00000000-0000-0000-0000-00000000f501')$$,
  'N accepts the borrower side of L1');
select throws_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000f202')$$,
  '42501', null, 'an accepted claim cannot be accepted again');
select throws_ok($$select public.reject_claim('space_member', '00000000-0000-0000-0000-00000000f202')$$,
  '42501', null, 'an accepted claim cannot be rejected');

-- Reject S2 and L2.
select lives_ok($$select public.reject_claim('space_member', '00000000-0000-0000-0000-00000000f204')$$,
  'N rejects the S2 membership');
select lives_ok($$select public.reject_claim('loan', '00000000-0000-0000-0000-00000000f502')$$,
  'N rejects the lender side of L2');
select results_eq('select id from public.spaces', $$values ('00000000-0000-0000-0000-00000000f101'::uuid)$$,
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
      from public.space_members where phone = '+919000000012' order by id$$,
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
update auth.users set phone_confirmed_at = now() where id = '00000000-0000-0000-0000-00000000f002';
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
select pg_temp.tagged(is(pg_temp.affected($$update public.loans set closed_at = now() where id = '00000000-0000-0000-0000-00000000f501'$$),
  1, 'lender A closes L1 [+loans_update]'));

-- N deletes the account: the profile stays for shared history, anonymised.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-00000000f002", "role": "authenticated"}';
select lives_ok('select public.delete_account()', 'N deletes the account');
reset role;
select results_eq(
  $$select name, upi_id from public.profiles where id = '00000000-0000-0000-0000-00000000f002'$$,
  $$values (null::text, null::text)$$,
  'account deletion keeps the profile with name and UPI id cleared');
set local role anon;
select throws_ok($$select public.delete_account()$$, '42501', null, 'anon cannot call delete_account');
reset role;

select is(
  (select array_agg(t order by t) from (
     select sign || p as t from unnest(array['loans_select', 'loans_update']) p cross join (values ('+'), ('-')) v(sign)
     except select tag from pg_temp.covered) missing),
  null, 'every policy this migration recreates has an allowed (+) and a denied (-) tagged test');

select * from finish();
rollback;
