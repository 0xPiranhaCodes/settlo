-- Keyed claim decisions (#116): accept_claim / reject_claim with an idempotency key.
-- Callers: A owns space S and lent on loans K1 and K2; B holds a pending membership M1 and the
-- borrower side of K1 and K2; C holds a pending membership M2; O is an outsider; D is unverified.
begin;
create extension if not exists pgtap with schema extensions;

select plan(27);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-00000000b001', '919800000001', now()),
  ('00000000-0000-0000-0000-00000000b002', '919800000002', now()),
  ('00000000-0000-0000-0000-00000000b003', '919800000003', now()),
  ('00000000-0000-0000-0000-00000000b004', '919800000004', now()),
  ('00000000-0000-0000-0000-00000000b005', '919800000005', null);
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-00000000b001', '+919800000001', 'Asha'),
  ('00000000-0000-0000-0000-00000000b002', '+919800000002', 'Bilal'),
  ('00000000-0000-0000-0000-00000000b003', '+919800000003', 'Chitra'),
  ('00000000-0000-0000-0000-00000000b004', '+919800000004', 'Omar');
insert into public.spaces (id, name, kind, created_by) values
  ('00000000-0000-0000-0000-00000000b010', 'Flat 80', 'flat', '00000000-0000-0000-0000-00000000b001');
insert into public.space_members (id, space_id, phone, user_id, role) values
  ('00000000-0000-0000-0000-00000000b021', '00000000-0000-0000-0000-00000000b010', '+919800000001', '00000000-0000-0000-0000-00000000b001', 'owner'),
  ('00000000-0000-0000-0000-00000000b022', '00000000-0000-0000-0000-00000000b010', '+919800000002', null, 'member'),
  ('00000000-0000-0000-0000-00000000b023', '00000000-0000-0000-0000-00000000b010', '+919800000003', null, 'member');

create function pg_temp.login(u text) returns text language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true)
$$;
create function pg_temp.accept(kind text, id text, key text) returns text language sql as $$
  select format('select public.accept_claim(%L, %L, %L)', kind, id, key)
$$;
create function pg_temp.reject(kind text, id text, key text) returns text language sql as $$
  select format('select public.reject_claim(%L, %L, %L)', kind, id, key)
$$;
create function pg_temp.keys(u text) returns int language sql security definer as $$
  select count(*)::int from private.idempotency_keys where user_id = u::uuid and kind in ('accept_claim', 'reject_claim')
$$;
grant execute on all functions in schema pg_temp to public;

-- Hardening.
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname in ('accept_claim', 'reject_claim') and p.pronargs = 3
      and coalesce(p.proconfig @> array['search_path=""'], false)
      and not has_function_privilege('anon', p.oid, 'execute')
      and has_function_privilege('authenticated', p.oid, 'execute')),
  2, 'both keyed overloads pin search_path, refuse anon and allow authenticated');
select ok(has_function_privilege('authenticated', 'public.accept_claim(text, uuid)', 'execute')
          and has_function_privilege('authenticated', 'public.reject_claim(text, uuid)', 'execute'),
  'the unkeyed functions (#9) are still callable');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-00000000b001');
select lives_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-00000000b0a1", "direction": "lent",
    "counterparty_phone": "+919800000002", "principal_minor": 10000, "start_on": "2026-11-01"}')$$, 'fixture: loan K1');
select lives_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-00000000b0a2", "direction": "lent",
    "counterparty_phone": "+919800000002", "principal_minor": 20000, "start_on": "2026-11-01"}')$$, 'fixture: loan K2');

-- Arguments and callers.
select pg_temp.login('00000000-0000-0000-0000-00000000b002');
select throws_ok(pg_temp.accept('space_member', '00000000-0000-0000-0000-00000000b022', null), '22023', null,
  'accept_claim: a key is required');
select throws_ok(pg_temp.reject('space_member', '00000000-0000-0000-0000-00000000b022', null), '22023', null,
  'reject_claim: a key is required');
select pg_temp.login('00000000-0000-0000-0000-00000000b005');
select throws_ok(pg_temp.accept('space_member', '00000000-0000-0000-0000-00000000b022', '00000000-0000-0000-0000-00000000b101'),
  '42501', null, 'accept_claim: unverified D is refused');
select pg_temp.login('00000000-0000-0000-0000-00000000b004');
select throws_ok(pg_temp.accept('space_member', '00000000-0000-0000-0000-00000000b022', '00000000-0000-0000-0000-00000000b102'),
  '42501', null, 'accept_claim: outsider O cannot accept B''s claim');
select throws_ok(pg_temp.reject('loan', '00000000-0000-0000-0000-00000000b0a1', '00000000-0000-0000-0000-00000000b103'),
  '42501', null, 'reject_claim: nor reject B''s loan');
select is(pg_temp.keys('00000000-0000-0000-0000-00000000b004'), 0, 'a refused decision keeps no key');

-- Accept, then replay.
select pg_temp.login('00000000-0000-0000-0000-00000000b002');
select lives_ok(pg_temp.accept('space_member', '00000000-0000-0000-0000-00000000b022', '00000000-0000-0000-0000-00000000b201'),
  'accept_claim: B accepts membership M1');
select ok((select accepted_at is not null and user_id = '00000000-0000-0000-0000-00000000b002'
             from public.space_members where id = '00000000-0000-0000-0000-00000000b022'),
  'accept_claim: M1 is accepted and linked to B');
select lives_ok(pg_temp.accept('space_member', '00000000-0000-0000-0000-00000000b022', '00000000-0000-0000-0000-00000000b201'),
  'accept_claim: the same key replays as a no-op');
select throws_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-00000000b022')$$, '42501', null,
  'accept_claim: without the key the replay would have been refused');
select throws_ok(pg_temp.accept('loan', '00000000-0000-0000-0000-00000000b0a1', '00000000-0000-0000-0000-00000000b201'),
  'PT409', null, 'accept_claim: the key with another payload conflicts');
select throws_ok(pg_temp.reject('space_member', '00000000-0000-0000-0000-00000000b022', '00000000-0000-0000-0000-00000000b201'),
  'PT409', null, 'reject_claim: the key cannot be reused across functions');
select lives_ok(pg_temp.accept('loan', '00000000-0000-0000-0000-00000000b0a1', '00000000-0000-0000-0000-00000000b202'),
  'accept_claim: B accepts loan K1');
select ok((select borrower_accepted_at is not null from public.loans where id = '00000000-0000-0000-0000-00000000b0a1'),
  'accept_claim: K1''s borrower side is accepted');

-- Reject, then replay: one activity row.
select lives_ok(pg_temp.reject('loan', '00000000-0000-0000-0000-00000000b0a2', '00000000-0000-0000-0000-00000000b203'),
  'reject_claim: B says loan K2 isn''t theirs');
select lives_ok(pg_temp.reject('loan', '00000000-0000-0000-0000-00000000b0a2', '00000000-0000-0000-0000-00000000b203'),
  'reject_claim: the same key replays as a no-op');
reset role;
select is((select count(*)::int from public.activity
            where loan_id = '00000000-0000-0000-0000-00000000b0a2' and action = 'rejected'),
  1, 'reject_claim: the replay wrote no second activity row');
select ok((select borrower_id is null and borrower_rejected_at is not null
             from public.loans where id = '00000000-0000-0000-0000-00000000b0a2'),
  'reject_claim: K2''s borrower side is unlinked');

-- Keys are per user.
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-00000000b003');
select lives_ok(pg_temp.reject('space_member', '00000000-0000-0000-0000-00000000b023', '00000000-0000-0000-0000-00000000b201'),
  'reject_claim: C may use the key value B used');
select lives_ok(pg_temp.reject('space_member', '00000000-0000-0000-0000-00000000b023', '00000000-0000-0000-0000-00000000b201'),
  'reject_claim: and replay it');
reset role;
select is((select count(*)::int from public.activity
            where space_id = '00000000-0000-0000-0000-00000000b010' and action = 'rejected'),
  1, 'reject_claim: C''s replay wrote no second activity row');

-- Retention (#70): after the purge a replay is a new call, and a decision is final.
update private.idempotency_keys set created_at = now() - interval '31 days'
 where user_id = '00000000-0000-0000-0000-00000000b002' and key = '00000000-0000-0000-0000-00000000b201';
select cmp_ok(private.purge_idempotency_keys(), '>=', 1, 'retention: B''s expired key is purged');
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-00000000b002');
select throws_ok(pg_temp.accept('space_member', '00000000-0000-0000-0000-00000000b022', '00000000-0000-0000-0000-00000000b201'),
  '42501', null, 'retention: past the window the replay is refused, not applied twice');

select * from finish();
rollback;
