-- Loans (#7): interest-free v1, party checks, two-sided confirmation, final confirm/dispute,
-- only confirmed repayments count, trigger-written activity, RESTRICT history.
begin;
create extension if not exists pgtap with schema extensions;

select plan(30);

-- Lender, borrower and an unrelated third party.
insert into auth.users (id, phone) values
  ('00000000-0000-0000-0000-00000000e001', '919000000001'),
  ('00000000-0000-0000-0000-00000000e002', '919000000002'),
  ('00000000-0000-0000-0000-00000000e003', '919000000003');
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-00000000e001', '+919000000001', 'Lender'),
  ('00000000-0000-0000-0000-00000000e002', '+919000000002', 'Borrower'),
  ('00000000-0000-0000-0000-00000000e003', '+919000000003', 'Third');

-- Loan constraints.
select throws_ok(
  $$insert into public.loans (lender_phone, borrower_phone, principal_minor, interest_type, installment_minor, due_day)
    values ('+919000000001', '+919000000002', 100000, 'simple', 10000, 5)$$,
  '23514', null, 'v1 rejects interest_type simple');
select throws_ok(
  $$insert into public.loans (lender_phone, borrower_phone, principal_minor, installment_minor, due_day)
    values ('+919000000001', '+919000000001', 100000, 10000, 5)$$,
  '23514', null, 'lender and borrower must differ');
select throws_ok(
  $$insert into public.loans (lender_phone, borrower_phone, principal_minor, installment_minor, due_day)
    values ('+919000000001', '+919000000002', 100000, 10000, 29)$$,
  '23514', null, 'due_day must be 1..28');
select throws_ok(
  $$insert into public.loans (lender_phone, borrower_phone, principal_minor)
    values ('+919000000001', '+919000000002', 100000)$$,
  '23514', null, 'a monthly loan needs an instalment and a due day');
select throws_ok(
  $$insert into public.loans (lender_phone, borrower_phone, lender_id, principal_minor, installment_minor, due_day)
    values ('+919000000001', '+919000000002', '00000000-0000-0000-0000-00000000e003', 100000, 10000, 5)$$,
  '23514', null, 'lender_id must belong to lender_phone');
select throws_ok(
  $$insert into public.loans (lender_phone, borrower_phone, principal_minor, installment_minor, due_day, created_by)
    values ('+919000000001', '+919000000002', 100000, 10000, 5, '00000000-0000-0000-0000-00000000e003')$$,
  '42501', null, 'a third party cannot create a loan between two others');

-- ₹1,000.00 interest-free, ₹100.00 monthly on the 5th; borrower has not linked yet (phone only).
insert into public.loans (id, lender_phone, borrower_phone, lender_id, principal_minor, installment_minor, due_day, start_on,
                          created_by)
values ('00000000-0000-0000-0000-00000000f001', '+919000000001', '+919000000002',
        '00000000-0000-0000-0000-00000000e001', 100000, 10000, 5, '2026-10-01', '00000000-0000-0000-0000-00000000e001');

select throws_ok(
  $$update public.loans set borrower_phone = '+919000000003' where id = '00000000-0000-0000-0000-00000000f001'$$,
  '55000', null, 'loan parties cannot change');

-- Recording.
select throws_ok(
  $$insert into public.loan_repayments (loan_id, amount_minor, principal_minor, recorded_by)
    values ('00000000-0000-0000-0000-00000000f001', 10000, 10000, '00000000-0000-0000-0000-00000000e003')$$,
  '42501', null, 'third party cannot record a repayment');
select throws_ok(
  $$insert into public.loan_repayments (loan_id, amount_minor, principal_minor, interest_minor, recorded_by)
    values ('00000000-0000-0000-0000-00000000f001', 10000, 9000, 500, '00000000-0000-0000-0000-00000000e002')$$,
  '23514', null, 'amount must equal principal + interest');
select throws_ok(
  $$insert into public.loan_repayments (loan_id, amount_minor, principal_minor, interest_minor, recorded_by)
    values ('00000000-0000-0000-0000-00000000f001', 10000, 9000, 1000, '00000000-0000-0000-0000-00000000e002')$$,
  '23514', null, 'interest is rejected on an interest-free loan');
select throws_ok(
  $$insert into public.loan_repayments (loan_id, amount_minor, principal_minor, recorded_by, confirmed_by, confirmed_at)
    values ('00000000-0000-0000-0000-00000000f001', 10000, 10000, '00000000-0000-0000-0000-00000000e002',
            '00000000-0000-0000-0000-00000000e001', now())$$,
  '23514', null, 'a repayment cannot be inserted already confirmed');

-- Borrower (party by phone only) records three repayments.
select lives_ok(
  $$insert into public.loan_repayments (id, loan_id, amount_minor, principal_minor, method, reference, paid_on, recorded_by) values
    ('00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-00000000f001', 60000, 60000, 'upi', '4321 8812 0099', '2026-10-05', '00000000-0000-0000-0000-00000000e002'),
    ('00000000-0000-0000-0000-0000000f0002', '00000000-0000-0000-0000-00000000f001', 60000, 60000, 'cash', null, '2026-11-05', '00000000-0000-0000-0000-00000000e002'),
    ('00000000-0000-0000-0000-0000000f0003', '00000000-0000-0000-0000-00000000f001', 10000, 10000, 'bank', null, '2026-11-06', '00000000-0000-0000-0000-00000000e002')$$,
  'borrower records repayments; pending ones do not count, so 60000 + 60000 > principal is accepted');
select is(
  (select status from public.loan_repayments where id = '00000000-0000-0000-0000-0000000f0001'),
  'pending', 'a recorded repayment is pending');

-- Confirmation.
select throws_ok(
  $$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-00000000e002'
     where id = '00000000-0000-0000-0000-0000000f0001'$$,
  '42501', null, 'recorder cannot confirm their own repayment');
select throws_ok(
  $$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-00000000e003'
     where id = '00000000-0000-0000-0000-0000000f0001'$$,
  '42501', null, 'third party cannot confirm');
select throws_ok(
  $$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-00000000e001', amount_minor = 1, principal_minor = 1
     where id = '00000000-0000-0000-0000-0000000f0001'$$,
  '55000', null, 'confirming cannot change what is confirmed');

-- An authenticated user cannot confirm in someone else's name.
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000e003"}';
select throws_ok(
  $$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-00000000e001'
     where id = '00000000-0000-0000-0000-0000000f0001'$$,
  '42501', null, 'confirmed_by must be the current user');
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000e001"}';
select lives_ok(
  $$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-00000000e001'
     where id = '00000000-0000-0000-0000-0000000f0001'$$,
  'lender (the other party) confirms');
set local request.jwt.claims = '{}';
select results_eq(
  $$select status, confirmed_at is not null from public.loan_repayments where id = '00000000-0000-0000-0000-0000000f0001'$$,
  $$values ('confirmed'::text, true)$$, 'confirmed repayment has status and server-set confirmed_at');

select throws_ok(
  $$update public.loan_repayments set amount_minor = 50000, principal_minor = 50000
     where id = '00000000-0000-0000-0000-0000000f0001'$$,
  '55000', null, 'confirmed repayment cannot be edited');
select throws_ok(
  $$update public.loan_repayments set confirmed_by = null where id = '00000000-0000-0000-0000-0000000f0001'$$,
  '55000', null, 'confirmation cannot be withdrawn');
select throws_ok(
  $$update public.loan_repayments set confirmed_by = null, disputed_by = '00000000-0000-0000-0000-00000000e001'
     where id = '00000000-0000-0000-0000-0000000f0001'$$,
  '55000', null, 'confirmed repayment cannot be disputed');

-- Only confirmed repayments count: 60000 confirmed + 60000 exceeds the 100000 principal.
select throws_ok(
  $$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-00000000e001'
     where id = '00000000-0000-0000-0000-0000000f0002'$$,
  '23514', null, 'confirming past the principal is rejected');

-- Disputes.
select throws_ok(
  $$update public.loan_repayments set disputed_by = '00000000-0000-0000-0000-00000000e002'
     where id = '00000000-0000-0000-0000-0000000f0002'$$,
  '42501', null, 'recorder cannot dispute their own repayment');
select lives_ok(
  $$update public.loan_repayments set disputed_by = '00000000-0000-0000-0000-00000000e001', dispute_reason = 'not in my bank'
     where id = '00000000-0000-0000-0000-0000000f0002'$$,
  'lender disputes a repayment');
select results_eq(
  $$select status, dispute_reason, disputed_at is not null from public.loan_repayments where id = '00000000-0000-0000-0000-0000000f0002'$$,
  $$values ('disputed'::text, 'not in my bank'::text, true)$$, 'dispute is recorded with reason and time');
select throws_ok(
  $$update public.loan_repayments set disputed_by = null, confirmed_by = '00000000-0000-0000-0000-00000000e001'
     where id = '00000000-0000-0000-0000-0000000f0002'$$,
  '55000', null, 'disputed repayment cannot later be confirmed');

-- Activity is written by triggers with the acting party.
select results_eq(
  $$select action, actor_id from public.activity
     where repayment_id in ('00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f0002')
     order by repayment_id, id$$,
  $$values ('recorded'::text, '00000000-0000-0000-0000-00000000e002'::uuid),
           ('confirmed', '00000000-0000-0000-0000-00000000e001'),
           ('recorded', '00000000-0000-0000-0000-00000000e002'),
           ('disputed', '00000000-0000-0000-0000-00000000e001')$$,
  'record, confirm and dispute each write activity');

-- History survives.
select throws_ok(
  $$delete from public.loans where id = '00000000-0000-0000-0000-00000000f001'$$,
  '23503', null, 'loan with repayments cannot be hard-deleted');
select is(
  (select count(*)::int from pg_constraint
    where contype = 'f' and confdeltype <> 'r'
      and conrelid in ('public.loans'::regclass, 'public.loan_repayments'::regclass, 'public.activity'::regclass)),
  0, 'every FK from loans, repayments and activity is ON DELETE RESTRICT');

select * from finish();
rollback;
