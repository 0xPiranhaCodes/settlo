-- Repayment bounds (#99): paid_on within the loan's start_on..today (Asia/Kolkata), reference
-- trimmed, at most 64 printable characters. Through record_repayment and a direct insert alike.
-- L lends B 100000 on loan K, which started three days ago in India.
begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000009901', '919990000001', now()),
  ('00000000-0000-0000-0000-000000009902', '919990000002', now());
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000009901', '+919990000001', 'Lata'),
  ('00000000-0000-0000-0000-000000009902', '+919990000002', 'Bilal');

create function pg_temp.today() returns date language sql as $$
  select (now() at time zone 'Asia/Kolkata')::date
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
-- record_repayment of 100 paise on K with the given key, paid_on and reference (null leaves it out).
create function pg_temp.record(key int, paid_on date, reference text default null) returns text language sql as $$
  select format('select public.record_repayment(%L)', jsonb_strip_nulls(jsonb_build_object(
    'loan_id', '00000000-0000-0000-0000-000000009a01',
    'idempotency_key', format('00000000-0000-0000-0000-%s', lpad(key::text, 12, '0')),
    'amount_minor', 100, 'paid_on', paid_on, 'reference', reference)))
$$;
create function pg_temp.reference_of(key int) returns text language sql as $$
  select reference from public.loan_repayments where id = format('00000000-0000-0000-0000-%s', lpad(key::text, 12, '0'))::uuid
$$;
grant execute on all functions in schema pg_temp to public;

select ok(not has_function_privilege('authenticated', 'public.bound_loan_repayment()', 'execute')
          and not has_function_privilege('anon', 'public.bound_loan_repayment()', 'execute'),
  'the bounds trigger is not executable by clients');

select set_config('request.jwt.claims',
  '{"sub": "00000000-0000-0000-0000-000000009901", "role": "authenticated"}', true);
set local role authenticated;
select public.create_loan(jsonb_build_object(
  'idempotency_key', '00000000-0000-0000-0000-000000009a01', 'direction', 'lent',
  'counterparty_phone', '+919990000002', 'principal_minor', 100000, 'start_on', pg_temp.today() - 3));

-- paid_on.
select is(pg_temp.hint_of(pg_temp.record(1, pg_temp.today() - 4)), 'paid_on_before_start',
  'paid_on: the day before the loan started is refused');
select lives_ok(pg_temp.record(2, pg_temp.today() - 3), 'paid_on: the day the loan started is accepted');
select lives_ok(pg_temp.record(3, pg_temp.today()), 'paid_on: today in India is accepted');
select is(pg_temp.hint_of(pg_temp.record(4, pg_temp.today() + 1)), 'paid_on_future',
  'paid_on: tomorrow is refused');
select lives_ok(pg_temp.record(5, null), 'paid_on: null defaults to today');
select is((select paid_on from public.loan_repayments where id = '00000000-0000-0000-0000-000000000005'),
  pg_temp.today(), 'paid_on: the default is today in India');
select lives_ok(pg_temp.record(1, pg_temp.today() - 3),
  'paid_on: a refused key is not claimed, so a corrected payload can reuse it');

-- reference.
select lives_ok(pg_temp.record(10, pg_temp.today(), repeat('x', 64)), 'reference: 64 characters are accepted');
select is(pg_temp.hint_of(pg_temp.record(11, pg_temp.today(), repeat('x', 65))), 'reference_invalid',
  'reference: 65 characters are refused');
select lives_ok(pg_temp.record(12, pg_temp.today(), '  ' || repeat('₹', 64) || '  '),
  'reference: 64 multi-byte characters within spaces are accepted');
select is(pg_temp.reference_of(12), repeat('₹', 64), 'reference: it is stored trimmed');
select is(pg_temp.hint_of(pg_temp.record(13, pg_temp.today(), E'UPI\n4321')), 'reference_invalid',
  'reference: a newline is refused');
select is(pg_temp.hint_of(pg_temp.record(14, pg_temp.today(), E'UPI 4321\t')), 'reference_invalid',
  'reference: a trailing tab is refused');
select lives_ok(pg_temp.record(15, pg_temp.today(), null), 'reference: null is accepted');

-- A direct insert is held to the same bounds.
select is(pg_temp.hint_of(format(
  'insert into public.loan_repayments (loan_id, amount_minor, principal_minor, paid_on) values (%L, 100, 100, %L)',
  '00000000-0000-0000-0000-000000009a01', pg_temp.today() + 1)),
  'paid_on_future', 'direct insert: a future paid_on is refused');
select is(pg_temp.hint_of(format(
  'insert into public.loan_repayments (loan_id, amount_minor, principal_minor, reference) values (%L, 100, 100, %L)',
  '00000000-0000-0000-0000-000000009a01', E'a\u0007b')),
  'reference_invalid', 'direct insert: a control character is refused');

select * from finish();
rollback;
