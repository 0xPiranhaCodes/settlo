-- Loan RPCs (#87): create_loan, record_repayment, confirm_repayment, dispute_repayment.
-- Callers: L lends to B. B has an account but is a pending claimant on the loan until they accept;
-- O is an outsider; D has an unverified phone; anon has no session.
-- Loan K: 30000 paise, 10000 a month on the 5th. R1 10000 by L, confirmed by B; R2 15000 by B,
-- disputed by L; R3 20000 by B and R4 15000 by L both pending; confirming R3 repays and closes K,
-- so R4 can no longer be confirmed.
begin;
create extension if not exists pgtap with schema extensions;

select plan(90);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000008701', '919870000001', now()),
  ('00000000-0000-0000-0000-000000008702', '919870000002', now()),
  ('00000000-0000-0000-0000-000000008704', '919870000004', now()),
  ('00000000-0000-0000-0000-000000008705', '919870000005', null);
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000008701', '+919870000001', 'Lata'),
  ('00000000-0000-0000-0000-000000008702', '+919870000002', 'Bilal'),
  ('00000000-0000-0000-0000-000000008704', '+919870000004', 'Omar');

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
-- Loan K, lent by the caller to B.
create function pg_temp.loan_k(principal int default 30000) returns text language sql as $$
  select format('select public.create_loan(%L)', jsonb_build_object(
    'idempotency_key', '00000000-0000-0000-0000-000000008a01', 'direction', 'lent',
    'counterparty_phone', '+919870000002', 'principal_minor', principal,
    'installment_minor', 10000, 'due_day', 5, 'start_on', '2026-11-01'))
$$;
create function pg_temp.record(key text, amount int, loan text default '00000000-0000-0000-0000-000000008a01')
returns text language sql as $$
  select format('select public.record_repayment(%L)', jsonb_build_object(
    'loan_id', loan, 'idempotency_key', key, 'amount_minor', amount, 'method', 'upi', 'paid_on', '2026-11-05'))
$$;
create function pg_temp.confirm(repayment text, key text) returns text language sql as $$
  select format('select public.confirm_repayment(%L, %L)', repayment, key)
$$;
create function pg_temp.dispute(repayment text, reason text, key text) returns text language sql as $$
  select format('select public.dispute_repayment(%L, %L, %L)', repayment, reason, key)
$$;
-- K's summary as text, the columns that do not depend on today's date.
create function pg_temp.summary() returns text language sql as $$
  select format('repaid=%s outstanding=%s confirmed=%s pending=%s/%s disputed=%s closed=%s',
                repaid_minor, outstanding_minor, confirmed_count, pending_count, pending_minor, disputed_count,
                (closed_at is not null)::text)
    from public.loan_summaries where loan_id = '00000000-0000-0000-0000-000000008a01'
$$;
create function pg_temp.status(repayment text) returns text language sql as $$
  select status from public.loan_repayments where id = repayment::uuid
$$;
create function pg_temp.last_activity() returns public.activity language sql as $$
  select * from public.activity where loan_id = '00000000-0000-0000-0000-000000008a01' order by id desc limit 1
$$;
grant execute on all functions in schema pg_temp to public;

-- Hardening.
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace in ('public'::regnamespace, 'private'::regnamespace)
      and p.proname in ('create_loan', 'record_repayment', 'confirm_repayment', 'dispute_repayment')
      and (not coalesce(p.proconfig @> array['search_path=""'], false)
           or has_function_privilege('anon', p.oid, 'execute')
           or not has_function_privilege('authenticated', p.oid, 'execute'))),
  null,
  'loan RPCs have a fixed search_path and are executable by authenticated only');
select ok(not has_function_privilege('authenticated', 'public.log_loan_activity()', 'execute')
          and not has_function_privilege('authenticated', 'public.close_repaid_loan()', 'execute'),
  'the loan triggers are not executable by clients');
select ok(not has_function_privilege('authenticated', 'private.settle_repayment(text, uuid, boolean, text)', 'execute')
          and not has_function_privilege('anon', 'private.settle_repayment(text, uuid, boolean, text)', 'execute'),
  'private.settle_repayment is not executable by clients');

set local role anon;
select throws_ok(pg_temp.loan_k(), '42501', null, 'anon cannot call create_loan');
select throws_ok(pg_temp.record('00000000-0000-0000-0000-000000008b01', 10000), '42501', null,
  'anon cannot call record_repayment');
select throws_ok(pg_temp.confirm('00000000-0000-0000-0000-000000008b01', '00000000-0000-0000-0000-000000008c01'),
  '42501', null, 'anon cannot call confirm_repayment');
select throws_ok(pg_temp.dispute('00000000-0000-0000-0000-000000008b01', 'No', '00000000-0000-0000-0000-000000008c01'),
  '42501', null, 'anon cannot call dispute_repayment');
reset role;
set local role authenticated;

-- create_loan: denied and invalid.
select pg_temp.login('00000000-0000-0000-0000-000000008705');
select throws_ok(pg_temp.loan_k(), '42501', null, 'create_loan: unverified D is refused');
select pg_temp.login('00000000-0000-0000-0000-000000008701');
select throws_ok($$select public.create_loan('[]')$$, '22023', null, 'create_loan: the payload must be an object');
select throws_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000008a09",
    "direction": "gifted", "counterparty_phone": "+919870000002", "principal_minor": 100}')$$,
  '22023', null, 'create_loan: direction must be lent or borrowed');
select throws_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000008a09",
    "direction": "lent", "counterparty_phone": "+919870000001", "principal_minor": 100}')$$,
  '22023', null, 'create_loan: the counterparty cannot be the caller');
select throws_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000008a09",
    "direction": "lent", "principal_minor": 100}')$$,
  '22023', null, 'create_loan: the counterparty phone is required');
select throws_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000008a09",
    "direction": "lent", "counterparty_phone": "+919870000002", "principal_minor": 0}')$$,
  '22023', null, 'create_loan: the principal must be positive');
select throws_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000008a09",
    "direction": "lent", "counterparty_phone": "+919870000002", "principal_minor": 100, "installment_minor": 50}')$$,
  '22023', null, 'create_loan: an instalment needs a due day');
select throws_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000008a09",
    "direction": "lent", "counterparty_phone": "+919870000002", "principal_minor": 100, "installment_minor": 500,
    "due_day": 5}')$$,
  '22023', null, 'create_loan: the instalment cannot exceed the principal');
select throws_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000008a09",
    "direction": "lent", "counterparty_phone": "+919870000002", "principal_minor": 100, "installment_minor": 50,
    "due_day": 31}')$$,
  '22023', null, 'create_loan: due_day must be 1..28');
select is(pg_temp.hint_of($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000008a09",
    "direction": "lent", "counterparty_phone": "+919870000002", "principal_minor": 100, "interest_type": "simple"}')$$),
  'interest_not_supported', 'create_loan: v1 is interest free');

-- create_loan: allowed. L lends to B, who has an account but has not accepted the loan yet.
select is((select public.create_loan(jsonb_build_object(
    'idempotency_key', '00000000-0000-0000-0000-000000008a01', 'direction', 'lent',
    'counterparty_phone', '+919870000002', 'principal_minor', 30000,
    'installment_minor', 10000, 'due_day', 5, 'start_on', '2026-11-01'))),
  '00000000-0000-0000-0000-000000008a01'::uuid, 'create_loan: L lends to B; the key is the loan id');
select ok((select lender_phone = '+919870000001' and borrower_phone = '+919870000002'
                  and lender_id = '00000000-0000-0000-0000-000000008701' and lender_accepted_at is not null
                  and borrower_id is null and borrower_accepted_at is null
                  and schedule_type = 'monthly' and interest_type = 'none' and start_on = '2026-11-01'
             from public.loans where id = '00000000-0000-0000-0000-000000008a01'),
  'create_loan: L is the accepted lender; B''s side is a pending claim');
select is((pg_temp.last_activity()).action, 'created', 'create_loan: logs created');
select ok((select actor_id = '00000000-0000-0000-0000-000000008701' and before is null
                  and (after ->> 'principal_minor')::int = 30000
             from pg_temp.last_activity()),
  'create_loan: the activity row has the new loan as after');
select is(pg_temp.summary(), 'repaid=0 outstanding=30000 confirmed=0 pending=0/0 disputed=0 closed=false',
  'loan_summaries: a new loan is all outstanding');
select lives_ok(pg_temp.loan_k(), 'create_loan: a replay succeeds');
select is((select count(*)::int from public.activity where loan_id = '00000000-0000-0000-0000-000000008a01'), 1,
  'create_loan: a replay writes nothing');
select throws_ok(pg_temp.loan_k(40000), 'PT409', null, 'create_loan: the same key with another payload is a conflict');
select pg_temp.login('00000000-0000-0000-0000-000000008704');
select throws_ok(pg_temp.loan_k(), 'PT409', null, 'create_loan: another user''s key is a conflict');
select lives_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000008a02",
    "direction": "borrowed", "counterparty_phone": "+919870000099", "principal_minor": 5000}')$$,
  'create_loan: O borrows from a number with no account, flexible');
select ok((select lender_phone = '+919870000099' and borrower_id = '00000000-0000-0000-0000-000000008704'
                  and lender_id is null and schedule_type = 'flexible'
             from public.loans where id = '00000000-0000-0000-0000-000000008a02'),
  'create_loan: borrowed makes the caller the borrower');

-- record_repayment: denied.
select throws_ok(pg_temp.record('00000000-0000-0000-0000-000000008b01', 10000), '42501', null,
  'record_repayment: outsider O is refused');
select pg_temp.login('00000000-0000-0000-0000-000000008705');
select throws_ok(pg_temp.record('00000000-0000-0000-0000-000000008b01', 10000), '42501', null,
  'record_repayment: unverified D is refused');
select pg_temp.login('00000000-0000-0000-0000-000000008702');
select throws_ok(pg_temp.record('00000000-0000-0000-0000-000000008b01', 10000), '42501', null,
  'record_repayment: pending claimant B is refused');
select pg_temp.login('00000000-0000-0000-0000-000000008701');
select throws_ok(pg_temp.record('00000000-0000-0000-0000-000000008b01', 0), '22023', null,
  'record_repayment: the amount must be positive');
select is(pg_temp.hint_of(pg_temp.record('00000000-0000-0000-0000-000000008b01', 30001)), 'overpayment',
  'record_repayment: more than the principal is refused');

-- record_repayment: allowed. L records R1.
select is((select public.record_repayment(jsonb_build_object(
    'loan_id', '00000000-0000-0000-0000-000000008a01', 'idempotency_key', '00000000-0000-0000-0000-000000008b01',
    'amount_minor', 10000, 'method', 'upi', 'paid_on', '2026-11-05'))),
  '00000000-0000-0000-0000-000000008b01'::uuid, 'record_repayment: L records R1; the key is the repayment id');
select ok((select status = 'pending' and principal_minor = 10000 and interest_minor = 0
                  and recorded_by = '00000000-0000-0000-0000-000000008701'
             from public.loan_repayments where id = '00000000-0000-0000-0000-000000008b01'),
  'record_repayment: R1 is pending, all principal');
select ok((select action = 'recorded' and repayment_id = '00000000-0000-0000-0000-000000008b01'
                  and before is null and after ->> 'status' = 'pending'
             from pg_temp.last_activity()),
  'record_repayment: logs recorded with the new repayment');
select is(pg_temp.summary(), 'repaid=0 outstanding=30000 confirmed=0 pending=1/10000 disputed=0 closed=false',
  'loan_summaries: R1 is pending and does not count');
select lives_ok(pg_temp.record('00000000-0000-0000-0000-000000008b01', 10000), 'record_repayment: a replay succeeds');
select is((select count(*)::int from public.loan_repayments where loan_id = '00000000-0000-0000-0000-000000008a01'), 1,
  'record_repayment: a replay writes nothing');
select throws_ok(pg_temp.record('00000000-0000-0000-0000-000000008b01', 9000), 'PT409', null,
  'record_repayment: the same key with another payload is a conflict');

-- confirm / dispute: denied.
select is(pg_temp.hint_of(pg_temp.confirm('00000000-0000-0000-0000-000000008b01', '00000000-0000-0000-0000-000000008c01')),
  'own_record', 'confirm_repayment: L cannot confirm a repayment L recorded');
select is(pg_temp.hint_of(pg_temp.dispute('00000000-0000-0000-0000-000000008b01', 'Oops', '00000000-0000-0000-0000-000000008c02')),
  'own_record', 'dispute_repayment: nor dispute it');
select throws_ok($$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-000000008701'
                    where id = '00000000-0000-0000-0000-000000008b01'$$,
  '42501', null, 'loan_repayments: nor confirm it directly');
select pg_temp.login('00000000-0000-0000-0000-000000008702');
select throws_ok(pg_temp.confirm('00000000-0000-0000-0000-000000008b01', '00000000-0000-0000-0000-000000008c03'),
  '42501', null, 'confirm_repayment: pending claimant B is refused');
select throws_ok(pg_temp.dispute('00000000-0000-0000-0000-000000008b01', 'No', '00000000-0000-0000-0000-000000008c04'),
  '42501', null, 'dispute_repayment: pending claimant B is refused');
select pg_temp.login('00000000-0000-0000-0000-000000008704');
select throws_ok(pg_temp.confirm('00000000-0000-0000-0000-000000008b01', '00000000-0000-0000-0000-000000008c05'),
  '42501', null, 'confirm_repayment: outsider O is refused');
select throws_ok(pg_temp.dispute('00000000-0000-0000-0000-000000008b01', 'No', '00000000-0000-0000-0000-000000008c06'),
  '42501', null, 'dispute_repayment: outsider O is refused');
select pg_temp.login('00000000-0000-0000-0000-000000008705');
select throws_ok(pg_temp.confirm('00000000-0000-0000-0000-000000008b01', '00000000-0000-0000-0000-000000008c07'),
  '42501', null, 'confirm_repayment: unverified D is refused');

-- B accepts the loan and confirms R1.
select pg_temp.login('00000000-0000-0000-0000-000000008702');
select lives_ok($$select public.accept_claim('loan', '00000000-0000-0000-0000-000000008a01')$$, 'B accepts loan K');
select throws_ok(pg_temp.confirm('00000000-0000-0000-0000-000000008b01', null), '22023', null,
  'confirm_repayment: a key is required');
select lives_ok(pg_temp.confirm('00000000-0000-0000-0000-000000008b01', '00000000-0000-0000-0000-000000008c08'),
  'confirm_repayment: B confirms R1');
select is(pg_temp.status('00000000-0000-0000-0000-000000008b01'), 'confirmed', 'confirm_repayment: R1 is confirmed');
select ok((select action = 'confirmed' and actor_id = '00000000-0000-0000-0000-000000008702'
                  and before ->> 'status' = 'pending' and after ->> 'status' = 'confirmed'
                  and after ->> 'confirmed_by' = '00000000-0000-0000-0000-000000008702'
             from pg_temp.last_activity()),
  'confirm_repayment: logs confirmed with before and after');
select is(pg_temp.summary(), 'repaid=10000 outstanding=20000 confirmed=1 pending=0/0 disputed=0 closed=false',
  'loan_summaries: R1 counts once confirmed');
select lives_ok(pg_temp.confirm('00000000-0000-0000-0000-000000008b01', '00000000-0000-0000-0000-000000008c08'),
  'confirm_repayment: a replay succeeds after R1 is no longer pending');
select throws_ok(pg_temp.confirm('00000000-0000-0000-0000-000000008b02', '00000000-0000-0000-0000-000000008c08'),
  'PT409', null, 'confirm_repayment: the same key for another repayment is a conflict');
select is(pg_temp.hint_of(pg_temp.confirm('00000000-0000-0000-0000-000000008b01', '00000000-0000-0000-0000-000000008c09')),
  'not_pending', 'confirm_repayment: a confirmed repayment is final');
select is(pg_temp.hint_of(pg_temp.dispute('00000000-0000-0000-0000-000000008b01', 'Changed my mind',
    '00000000-0000-0000-0000-000000008c10')),
  'not_pending', 'dispute_repayment: a confirmed repayment cannot be disputed');

-- B records R2; L disputes it.
select lives_ok(pg_temp.record('00000000-0000-0000-0000-000000008b02', 15000), 'record_repayment: borrower B records R2');
select is(pg_temp.hint_of(pg_temp.dispute('00000000-0000-0000-0000-000000008b02', 'Mine', '00000000-0000-0000-0000-000000008c11')),
  'own_record', 'dispute_repayment: B cannot dispute a repayment B recorded');
select pg_temp.login('00000000-0000-0000-0000-000000008701');
select throws_ok(pg_temp.dispute('00000000-0000-0000-0000-000000008b02', '  ', '00000000-0000-0000-0000-000000008c12'),
  '22023', null, 'dispute_repayment: a reason is required');
select lives_ok(pg_temp.dispute('00000000-0000-0000-0000-000000008b02', ' Not received ', '00000000-0000-0000-0000-000000008c13'),
  'dispute_repayment: L disputes R2');
select ok((select status = 'disputed' and dispute_reason = 'Not received'
                  and disputed_by = '00000000-0000-0000-0000-000000008701'
             from public.loan_repayments where id = '00000000-0000-0000-0000-000000008b02'),
  'dispute_repayment: R2 stays visible, disputed with its reason');
select ok((select action = 'disputed' and before ->> 'status' = 'pending' and after ->> 'dispute_reason' = 'Not received'
             from pg_temp.last_activity()),
  'dispute_repayment: logs disputed with before and after');
select is(pg_temp.summary(), 'repaid=10000 outstanding=20000 confirmed=1 pending=0/0 disputed=1 closed=false',
  'loan_summaries: a disputed repayment does not count');
select lives_ok(pg_temp.dispute('00000000-0000-0000-0000-000000008b02', 'Not received', '00000000-0000-0000-0000-000000008c13'),
  'dispute_repayment: a replay succeeds');
select throws_ok(pg_temp.dispute('00000000-0000-0000-0000-000000008b02', 'Short', '00000000-0000-0000-0000-000000008c13'),
  'PT409', null, 'dispute_repayment: the same key with another reason is a conflict');
select is(pg_temp.hint_of(pg_temp.confirm('00000000-0000-0000-0000-000000008b02', '00000000-0000-0000-0000-000000008c14')),
  'not_pending', 'confirm_repayment: a disputed repayment is final');

-- Review probes (#94): none of these reach past the RPC contract.
select is(pg_temp.hint_of($$insert into public.loan_repayments (id, loan_id, amount_minor, principal_minor)
    values ('00000000-0000-0000-0000-000000008b09', '00000000-0000-0000-0000-000000008a01', 20001, 20001)$$),
  'overpayment', 'probe 1: a direct insert of more than is outstanding is refused too');
select throws_ok($$update public.loans set closed_at = now() where id = '00000000-0000-0000-0000-000000008a01'$$,
  '42501', null, 'probe 2: lender L cannot close K at a balance');
select throws_ok(pg_temp.record('00000000-0000-0000-0000-000000008a01', 100), 'PT409', null,
  'probe 3: L''s create_loan key cannot be reused for record_repayment');
select throws_ok(format('select public.create_loan(%L)', jsonb_build_object(
    'idempotency_key', '00000000-0000-0000-0000-000000008b01', 'direction', 'lent',
    'counterparty_phone', '+919870000004', 'principal_minor', 100)),
  'PT409', null, 'probe 3: nor L''s record_repayment key for create_loan');
select throws_ok($$select private.settle_repayment('direct_probe', '00000000-0000-0000-0000-000000008b02', false, null)$$,
  '42501', null, 'probe 4: the confirm/dispute helper cannot be called directly');

-- Closing. R3 by B and R4 by L are both pending; each fits what is outstanding, together they do not.
select pg_temp.login('00000000-0000-0000-0000-000000008702');
select is(pg_temp.hint_of(pg_temp.record('00000000-0000-0000-0000-000000008b03', 20001)), 'overpayment',
  'record_repayment: more than is outstanding is refused');
select lives_ok(pg_temp.record('00000000-0000-0000-0000-000000008b03', 20000), 'record_repayment: B records R3');
select pg_temp.login('00000000-0000-0000-0000-000000008701');
select lives_ok(pg_temp.record('00000000-0000-0000-0000-000000008b04', 15000), 'record_repayment: L records R4');
select is(pg_temp.summary(), 'repaid=10000 outstanding=20000 confirmed=1 pending=2/35000 disputed=1 closed=false',
  'loan_summaries: R3 and R4 are pending');
select lives_ok(pg_temp.confirm('00000000-0000-0000-0000-000000008b03', '00000000-0000-0000-0000-000000008c15'),
  'confirm_repayment: L confirms R3');
select is(pg_temp.summary(), 'repaid=30000 outstanding=0 confirmed=2 pending=1/15000 disputed=1 closed=true',
  'loan_summaries: K is repaid and closed');
select ok((select installments_paid = 3 and on_track is null and next_due_on is null
             from public.loan_summaries where loan_id = '00000000-0000-0000-0000-000000008a01'),
  'loan_summaries: every instalment paid, no next due date');
select ok((select action = 'closed' and actor_id = '00000000-0000-0000-0000-000000008701'
                  and before ->> 'closed_at' is null and after ->> 'closed_at' is not null and repayment_id is null
             from pg_temp.last_activity()),
  'closing: logs closed with before and after');
select is((select array_agg(action order by id) from public.activity
            where loan_id = '00000000-0000-0000-0000-000000008a01' and id > (
              select id from public.activity where repayment_id = '00000000-0000-0000-0000-000000008b04')),
  array['confirmed', 'closed'], 'closing: confirmed is logged before closed');
select pg_temp.login('00000000-0000-0000-0000-000000008702');
select is(pg_temp.hint_of(pg_temp.confirm('00000000-0000-0000-0000-000000008b04', '00000000-0000-0000-0000-000000008c16')),
  'overpayment', 'confirm_repayment: B cannot confirm R4 past the principal');
select is(pg_temp.status('00000000-0000-0000-0000-000000008b04'), 'pending', 'confirm_repayment: R4 stays pending');
select lives_ok(pg_temp.dispute('00000000-0000-0000-0000-000000008b04', 'Already repaid', '00000000-0000-0000-0000-000000008c17'),
  'dispute_repayment: B can still dispute R4');
select is(pg_temp.hint_of(pg_temp.record('00000000-0000-0000-0000-000000008b05', 100)), 'loan_closed',
  'record_repayment: nothing more can be recorded on a closed loan');
select lives_ok(pg_temp.record('00000000-0000-0000-0000-000000008b03', 20000),
  'record_repayment: a replay of R3 still succeeds after K closed');
select is(pg_temp.summary(), 'repaid=30000 outstanding=0 confirmed=2 pending=0/0 disputed=2 closed=true',
  'loan_summaries: the final state');
select pg_temp.login('00000000-0000-0000-0000-000000008701');
select throws_ok($$update public.loans set closed_at = null where id = '00000000-0000-0000-0000-000000008a01'$$,
  '42501', null, 'probe 2: lender L cannot reopen K');
select is((select count(*)::int from public.activity where loan_id = '00000000-0000-0000-0000-000000008a01'), 10,
  'activity: one row per change on K (created, 4 recorded, 2 confirmed, 2 disputed, closed)');

select * from finish();
rollback;
