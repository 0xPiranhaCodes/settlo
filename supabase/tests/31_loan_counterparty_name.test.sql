-- create_loan keeps the name the creator types for the other party (#257), for the creator alone.
-- L lends to R's number under "Ravi"; a second loan is sent with no name. O is a stranger.
begin;
create extension if not exists pgtap with schema extensions;

select plan(21);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000009b01', '919871000001', now()),
  ('00000000-0000-0000-0000-000000009b02', '919871000002', now()),
  ('00000000-0000-0000-0000-000000009b03', '919871000003', now());
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000009b01', '+919871000001', 'Lata'),
  ('00000000-0000-0000-0000-000000009b02', '+919871000002', 'Raj'),
  ('00000000-0000-0000-0000-000000009b03', '+919871000003', 'Om');

create function pg_temp.loan(key text, name text) returns text language sql as $$
  select format('select public.create_loan(%L)', jsonb_strip_nulls(jsonb_build_object(
    'idempotency_key', key, 'direction', 'lent', 'counterparty_phone', '+919871000002',
    'principal_minor', 500000, 'start_on', '2026-11-01', 'counterparty_name', name)))
$$;
create function pg_temp.name_of(key text) returns text language sql as $$
  select counterparty_name from public.loan_labels where loan_id = key::uuid
$$;
create function pg_temp.as_user(id text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true)
$$;
-- Every activity snapshot of the loan the caller can see, as text, for a search for the label.
create function pg_temp.snapshots(key text) returns text language sql as $$
  select coalesce(string_agg(concat(before::text, after::text), ''), '')
    from public.activity where loan_id = key::uuid
$$;
grant execute on all functions in schema pg_temp to public;

select hasnt_column('public', 'loans', 'counterparty_name', 'the label is not on the shared loans row');

set local role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-000000009b01');

select lives_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0a', '  Ravi  '), 'create_loan: takes a name');
select is(pg_temp.name_of('00000000-0000-0000-0000-000000009b0a'), 'Ravi', 'the creator reads it, trimmed');
select lives_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0a', 'Ravi'),
  'a replay with the same name is the same payload');
select throws_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0a', 'Ravi K'), 'PT409', null,
  'a replay with another name is a conflict');
select is((select count(*)::int from public.loan_labels where loan_id = '00000000-0000-0000-0000-000000009b0a'), 1,
  'a replay adds no second label');

select lives_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0b', '   '), 'a blank name is no name');
select is(pg_temp.name_of('00000000-0000-0000-0000-000000009b0b'), null, 'a blank name stores no label');
select throws_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0c', repeat('x', 101)), '23514', null,
  'a name over 100 characters is refused');

select isnt(pg_temp.snapshots('00000000-0000-0000-0000-000000009b0a'), '', 'the creator sees the loan activity');
select ok(pg_temp.snapshots('00000000-0000-0000-0000-000000009b0a') not like '%Ravi%',
  'activity snapshots do not carry the label');
select throws_ok($$update public.loan_labels set counterparty_name = 'R' where loan_id = '00000000-0000-0000-0000-000000009b0a'$$,
  '42501', null, 'not even the creator can change a label');

-- R, the pending borrower.
select pg_temp.as_user('00000000-0000-0000-0000-000000009b02');
select is((select count(*)::int from public.loans where id = '00000000-0000-0000-0000-000000009b0a'), 1,
  'fixture: the pending counterparty sees the loan');
select is(pg_temp.name_of('00000000-0000-0000-0000-000000009b0a'), null, 'the pending counterparty cannot read the label');
select ok(pg_temp.snapshots('00000000-0000-0000-0000-000000009b0a') not like '%Ravi%',
  'nor find it in the activity they see');
select throws_ok($$insert into public.loan_labels (loan_id, counterparty_name) values ('00000000-0000-0000-0000-000000009b0b', 'L')$$,
  '42501', null, 'the counterparty cannot label a loan they did not create');

select lives_ok($$select public.accept_claim('loan', '00000000-0000-0000-0000-000000009b0a')$$, 'fixture: R accepts');
select is(pg_temp.name_of('00000000-0000-0000-0000-000000009b0a'), null, 'the accepted counterparty cannot read the label');
select ok(pg_temp.snapshots('00000000-0000-0000-0000-000000009b0a') not like '%Ravi%',
  'nor find it in the activity once accepted');

-- O, a stranger.
select pg_temp.as_user('00000000-0000-0000-0000-000000009b03');
select is((select count(*)::int from public.loan_labels), 0, 'an outsider reads no labels');
select throws_ok($$insert into public.loan_labels (loan_id, counterparty_name) values ('00000000-0000-0000-0000-000000009b0b', 'L')$$,
  '42501', null, 'an outsider cannot label the loan');

select * from finish();
rollback;
