-- Views (#11): member balances, monthly fairness, monthly categories, loan summaries.
-- Every expected value below is hand-computed from the fixtures; the views run as invoker.
begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

-- Members A, B, C of one space; plus an outsider who is in nothing.
insert into auth.users (id, phone) values
  ('00000000-0000-0000-0000-0000000011a1', '919000000011'),
  ('00000000-0000-0000-0000-0000000011a2', '919000000012'),
  ('00000000-0000-0000-0000-0000000011a9', '919000000019');
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-0000000011a1', '+919000000011', 'Lender'),
  ('00000000-0000-0000-0000-0000000011a2', '+919000000012', 'Borrower'),
  ('00000000-0000-0000-0000-0000000011a9', '+919000000019', 'Outsider');

insert into public.spaces (id, name, kind)
values ('00000000-0000-0000-0000-0000000012a1', 'Flat 402', 'flat');
insert into public.space_members (id, space_id, phone, role) values
  ('00000000-0000-0000-0000-0000000013a1', '00000000-0000-0000-0000-0000000012a1', '+919000000021', 'owner'),
  ('00000000-0000-0000-0000-0000000013a2', '00000000-0000-0000-0000-0000000012a1', '+919000000022', 'member'),
  ('00000000-0000-0000-0000-0000000013a3', '00000000-0000-0000-0000-0000000012a1', '+919000000023', 'member');

-- E1 Oct: 10001 groceries paid by C, equal split; remainder 2 paise to the payer (splitEqual):
--   A 3333, B 3333, C 3335.
-- E2 Nov: 30000 rent paid by A, equal: 10000 each.
-- E3 Nov: 9000 food paid by B 6000 + A 3000, exact: A 2000, B 3000, C 4000.
-- S  Nov: settlement, B pays A 5000 (payer B, split A).
-- E4 Nov: 50000 rent paid by C, equal (C 16668, A 16666, B 16666), then soft-deleted.
insert into public.expenses (id, space_id, description, category, amount_minor, spent_on, is_settlement) values
  ('00000000-0000-0000-0000-0000000014a1', '00000000-0000-0000-0000-0000000012a1', 'Groceries', 'groceries', 10001, '2026-10-15', false),
  ('00000000-0000-0000-0000-0000000014a2', '00000000-0000-0000-0000-0000000012a1', 'Rent', 'rent', 30000, '2026-11-01', false),
  ('00000000-0000-0000-0000-0000000014a3', '00000000-0000-0000-0000-0000000012a1', 'Dinner', 'food', 9000, '2026-11-10', false),
  ('00000000-0000-0000-0000-0000000014a4', '00000000-0000-0000-0000-0000000012a1', 'Settle up', null, 5000, '2026-11-15', true),
  ('00000000-0000-0000-0000-0000000014a5', '00000000-0000-0000-0000-0000000012a1', 'Rent again', 'rent', 50000, '2026-11-20', false);
insert into public.expense_payers (expense_id, member_id, amount_minor) values
  ('00000000-0000-0000-0000-0000000014a1', '00000000-0000-0000-0000-0000000013a3', 10001),
  ('00000000-0000-0000-0000-0000000014a2', '00000000-0000-0000-0000-0000000013a1', 30000),
  ('00000000-0000-0000-0000-0000000014a3', '00000000-0000-0000-0000-0000000013a2', 6000),
  ('00000000-0000-0000-0000-0000000014a3', '00000000-0000-0000-0000-0000000013a1', 3000),
  ('00000000-0000-0000-0000-0000000014a4', '00000000-0000-0000-0000-0000000013a2', 5000),
  ('00000000-0000-0000-0000-0000000014a5', '00000000-0000-0000-0000-0000000013a3', 50000);
insert into public.expense_splits (expense_id, member_id, split_type, amount_minor) values
  ('00000000-0000-0000-0000-0000000014a1', '00000000-0000-0000-0000-0000000013a1', 'equal', 3333),
  ('00000000-0000-0000-0000-0000000014a1', '00000000-0000-0000-0000-0000000013a2', 'equal', 3333),
  ('00000000-0000-0000-0000-0000000014a1', '00000000-0000-0000-0000-0000000013a3', 'equal', 3335),
  ('00000000-0000-0000-0000-0000000014a2', '00000000-0000-0000-0000-0000000013a1', 'equal', 10000),
  ('00000000-0000-0000-0000-0000000014a2', '00000000-0000-0000-0000-0000000013a2', 'equal', 10000),
  ('00000000-0000-0000-0000-0000000014a2', '00000000-0000-0000-0000-0000000013a3', 'equal', 10000),
  ('00000000-0000-0000-0000-0000000014a3', '00000000-0000-0000-0000-0000000013a1', 'exact', 2000),
  ('00000000-0000-0000-0000-0000000014a3', '00000000-0000-0000-0000-0000000013a2', 'exact', 3000),
  ('00000000-0000-0000-0000-0000000014a3', '00000000-0000-0000-0000-0000000013a3', 'exact', 4000),
  ('00000000-0000-0000-0000-0000000014a4', '00000000-0000-0000-0000-0000000013a1', 'exact', 5000),
  ('00000000-0000-0000-0000-0000000014a5', '00000000-0000-0000-0000-0000000013a1', 'equal', 16666),
  ('00000000-0000-0000-0000-0000000014a5', '00000000-0000-0000-0000-0000000013a2', 'equal', 16666),
  ('00000000-0000-0000-0000-0000000014a5', '00000000-0000-0000-0000-0000000013a3', 'equal', 16668);
set constraints all immediate;
update public.expenses set deleted_at = now() where id = '00000000-0000-0000-0000-0000000014a5';
set constraints all immediate;

-- Balances (E4 excluded, settlement counted):
--   A paid 30000 + 3000 = 33000, owes 3333 + 10000 + 2000 + 5000 = 20333 -> +12667
--   B paid 6000 + 5000  = 11000, owes 3333 + 10000 + 3000        = 16333 ->  -5333
--   C paid 10001,                owes 3335 + 10000 + 4000        = 17335 ->  -7334
select results_eq(
  $$select member_id, paid_minor, owed_minor, balance_minor from public.space_member_balances
     where space_id = '00000000-0000-0000-0000-0000000012a1' order by phone$$,
  $$values ('00000000-0000-0000-0000-0000000013a1'::uuid, 33000::bigint, 20333::bigint, 12667::bigint),
           ('00000000-0000-0000-0000-0000000013a2', 11000, 16333, -5333),
           ('00000000-0000-0000-0000-0000000013a3', 10001, 17335, -7334)$$,
  'balances: paid - owed, settlement counted, soft-deleted expense excluded');
select is(
  (select sum(balance_minor)::bigint from public.space_member_balances
    where space_id = '00000000-0000-0000-0000-0000000012a1'),
  0::bigint, 'balances net to zero');

-- Fairness (settlement and E4 excluded):
--   Oct total 10001: A 0/3333, B 0/3333, C 10001/3335.
--   Nov total 39000: A 33000/12000, B 6000/13000, C 0/14000.
select results_eq(
  $$select month, member_id, paid_minor, fair_share_minor, difference_minor, month_total_minor
      from public.space_monthly_fairness
     where space_id = '00000000-0000-0000-0000-0000000012a1' order by month, phone$$,
  $$values ('2026-10-01'::date, '00000000-0000-0000-0000-0000000013a1'::uuid, 0::bigint, 3333::bigint, -3333::bigint, 10001::bigint),
           ('2026-10-01', '00000000-0000-0000-0000-0000000013a2', 0, 3333, -3333, 10001),
           ('2026-10-01', '00000000-0000-0000-0000-0000000013a3', 10001, 3335, 6666, 10001),
           ('2026-11-01', '00000000-0000-0000-0000-0000000013a1', 33000, 12000, 21000, 39000),
           ('2026-11-01', '00000000-0000-0000-0000-0000000013a2', 6000, 13000, -7000, 39000),
           ('2026-11-01', '00000000-0000-0000-0000-0000000013a3', 0, 14000, -14000, 39000)$$,
  'fairness: paid vs fair share per member per month, a member who paid nothing still appears');

select results_eq(
  $$select month, category, total_minor, expense_count from public.space_monthly_categories
     where space_id = '00000000-0000-0000-0000-0000000012a1' order by month, category$$,
  $$values ('2026-10-01'::date, 'groceries'::text, 10001::bigint, 1),
           ('2026-11-01', 'food', 9000, 1),
           ('2026-11-01', 'rent', 30000, 1)$$,
  'categories: settlement and soft-deleted rent excluded');

-- Loan: 100000 at 30000 monthly on the 5th from 20 Aug 2026, so n = ceil(100000 / 30000) = 4
-- instalments due 5 Sep, 5 Oct, 5 Nov, 5 Dec 2026. Borrower records three repayments; the lender
-- confirms 30000, disputes 20000 and leaves 30000 pending. Only the confirmed one counts.
insert into public.loans (id, lender_phone, borrower_phone, lender_id, borrower_id,
                          principal_minor, installment_minor, due_day, start_on)
values ('00000000-0000-0000-0000-0000000015a1', '+919000000011', '+919000000012',
        '00000000-0000-0000-0000-0000000011a1', '00000000-0000-0000-0000-0000000011a2',
        100000, 30000, 5, '2026-08-20');
insert into public.loans (id, lender_phone, borrower_phone, principal_minor, schedule_type, start_on)
values ('00000000-0000-0000-0000-0000000015a2', '+919000000011', '+919000000012', 50000, 'flexible', '2026-08-20');
insert into public.loan_repayments (id, loan_id, amount_minor, principal_minor, paid_on, recorded_by) values
  ('00000000-0000-0000-0000-0000000016a1', '00000000-0000-0000-0000-0000000015a1', 30000, 30000, '2026-09-05', '00000000-0000-0000-0000-0000000011a2'),
  ('00000000-0000-0000-0000-0000000016a2', '00000000-0000-0000-0000-0000000015a1', 30000, 30000, '2026-10-05', '00000000-0000-0000-0000-0000000011a2'),
  ('00000000-0000-0000-0000-0000000016a3', '00000000-0000-0000-0000-0000000015a1', 20000, 20000, '2026-11-05', '00000000-0000-0000-0000-0000000011a2'),
  ('00000000-0000-0000-0000-0000000016a4', '00000000-0000-0000-0000-0000000015a2', 50000, 50000, '2026-09-01', '00000000-0000-0000-0000-0000000011a2');
update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-0000000011a1'
 where id in ('00000000-0000-0000-0000-0000000016a1', '00000000-0000-0000-0000-0000000016a4');
update public.loan_repayments set disputed_by = '00000000-0000-0000-0000-0000000011a1'
 where id = '00000000-0000-0000-0000-0000000016a3';

select results_eq(
  $$select repaid_minor, outstanding_minor, confirmed_count, pending_count, pending_minor, disputed_count,
           installments_total, installments_paid, ends_on
      from public.loan_summaries where loan_id = '00000000-0000-0000-0000-0000000015a1'$$,
  $$values (30000::bigint, 70000::bigint, 1, 1, 30000::bigint, 1, 4, 1, '2026-12-05'::date)$$,
  'loan: outstanding = principal - confirmed only; pending and disputed are counted, not repaid');
select results_eq(
  $$select * from public.loan_summaries order by loan_id$$,
  $$select * from public.loan_summaries_as_of((now() at time zone 'Asia/Kolkata')::date) order by loan_id$$,
  'loan_summaries is loan_summaries_as_of India''s today');

-- Schedule as of fixed dates: (instalments due before the date, expected, next due, on track).
select results_eq(
  $$select installments_due, expected_minor, next_due_on, on_track
      from public.loan_summaries_as_of('2026-08-25') where loan_id = '00000000-0000-0000-0000-0000000015a1'$$,
  $$values (0, 0::bigint, '2026-09-05'::date, true)$$, 'before the first instalment nothing is due');
select results_eq(
  $$select installments_due, expected_minor, next_due_on, on_track
      from public.loan_summaries_as_of('2026-10-05') where loan_id = '00000000-0000-0000-0000-0000000015a1'$$,
  $$values (1, 30000::bigint, '2026-10-05'::date, true)$$, 'on the due day itself the instalment is not yet overdue');
select results_eq(
  $$select installments_due, expected_minor, next_due_on, on_track
      from public.loan_summaries_as_of('2026-10-06') where loan_id = '00000000-0000-0000-0000-0000000015a1'$$,
  $$values (2, 60000::bigint, '2026-11-05'::date, false)$$, 'the day after a missed due date the loan is behind');
select results_eq(
  $$select installments_due, expected_minor, next_due_on, on_track
      from public.loan_summaries_as_of('2027-03-01') where loan_id = '00000000-0000-0000-0000-0000000015a1'$$,
  $$values (4, 100000::bigint, null::date, false)$$, 'after the schedule ends: all due, expected capped at principal, no next date');
select results_eq(
  $$select repaid_minor, outstanding_minor, installments_total, installments_paid, installments_due,
           expected_minor, next_due_on, ends_on, on_track
      from public.loan_summaries_as_of('2026-11-09') where loan_id = '00000000-0000-0000-0000-0000000015a2'$$,
  $$values (50000::bigint, 0::bigint, null::int, null::int, null::int, null::bigint, null::date, null::date, null::boolean)$$,
  'flexible loan: repaid in full, no schedule columns');

-- Invoker security: views carry security_invoker, so the caller's RLS applies.
select is(
  (select count(*)::int from pg_class
    where oid in ('public.space_member_balances'::regclass, 'public.space_monthly_fairness'::regclass,
                  'public.space_monthly_categories'::regclass, 'public.loan_summaries'::regclass)
      and reloptions @> array['security_invoker=true']),
  4, 'all four views are security_invoker');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-0000000011a9", "role": "authenticated"}';
select is((select count(*)::int from public.space_member_balances), 0, 'outsider sees no balances');
select is((select count(*)::int from public.space_monthly_fairness), 0, 'outsider sees no fairness rows');
select is((select count(*)::int from public.space_monthly_categories), 0, 'outsider sees no categories');
select is((select count(*)::int from public.loan_summaries), 0, 'outsider sees no loan summaries');
reset role;

select ok(
  not has_table_privilege('anon', 'public.space_member_balances', 'select')
  and not has_table_privilege('anon', 'public.space_monthly_fairness', 'select')
  and not has_table_privilege('anon', 'public.space_monthly_categories', 'select')
  and not has_table_privilege('anon', 'public.loan_summaries', 'select')
  and not has_function_privilege('anon', 'public.loan_summaries_as_of(date)', 'execute'),
  'anon cannot read the views or the summary function');

select * from finish();
rollback;
