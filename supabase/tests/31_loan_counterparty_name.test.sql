-- create_loan keeps the name the creator types for the other party (#257).
-- L lends to a number with no account under "Ravi"; a second loan is sent with no name.
begin;
create extension if not exists pgtap with schema extensions;

select plan(7);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000009b01', '919871000001', now());
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000009b01', '+919871000001', 'Lata');

create function pg_temp.loan(key text, name text) returns text language sql as $$
  select format('select public.create_loan(%L)', jsonb_strip_nulls(jsonb_build_object(
    'idempotency_key', key, 'direction', 'lent', 'counterparty_phone', '+919871000002',
    'principal_minor', 500000, 'start_on', '2026-11-01', 'counterparty_name', name)))
$$;
create function pg_temp.name_of(key text) returns text language sql as $$
  select counterparty_name from public.loans where id = key::uuid
$$;
grant execute on all functions in schema pg_temp to public;

set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-000000009b01', 'role', 'authenticated')::text, true);

select lives_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0a', '  Ravi  '), 'create_loan: takes a name');
select is(pg_temp.name_of('00000000-0000-0000-0000-000000009b0a'), 'Ravi', 'the name is stored trimmed');
select lives_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0a', 'Ravi'),
  'a replay with the same name is the same payload');
select throws_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0a', 'Ravi K'), 'PT409', null,
  'a replay with another name is a conflict');

select lives_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0b', '   '), 'a blank name is no name');
select is(pg_temp.name_of('00000000-0000-0000-0000-000000009b0b'), null, 'a blank name is stored as null');
select throws_ok(pg_temp.loan('00000000-0000-0000-0000-000000009b0c', repeat('x', 101)), '23514', null,
  'a name over 100 characters is refused');

select * from finish();
rollback;
