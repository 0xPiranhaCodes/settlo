-- Read views (#11): member balances, monthly fairness, monthly categories, loan summaries.
-- Money is bigint paise (ADR 0003). Every view is security_invoker, so the caller's RLS on the
-- underlying tables applies (policies arrive in #8). Readable by authenticated only.
-- Soft-deleted expenses never count. Settlements count toward balances but are not spending,
-- so fairness and categories leave them out. Only confirmed repayments count toward a loan.

-- paid - owed per member over every live expense, settlements included. Positive: owed to them.
create view public.space_member_balances with (security_invoker = true) as
select m.space_id, m.id as member_id, m.phone, m.user_id,
       p.paid as paid_minor,
       s.owed as owed_minor,
       p.paid - s.owed as balance_minor
from public.space_members m
cross join lateral (
  select coalesce(sum(ep.amount_minor), 0)::bigint as paid
  from public.expense_payers ep
  join public.expenses e on e.id = ep.expense_id
  where ep.member_id = m.id and e.deleted_at is null
) p
cross join lateral (
  select coalesce(sum(es.amount_minor), 0)::bigint as owed
  from public.expense_splits es
  join public.expenses e on e.id = es.expense_id
  where es.member_id = m.id and e.deleted_at is null
) s;

-- Per member per month of spending: what they paid against their fair share (the sum of their
-- splits). Every member of the space gets a row for every month the space has spending.
create view public.space_monthly_fairness with (security_invoker = true) as
with spend as (
  select e.id, e.space_id, date_trunc('month', e.spent_on::timestamp)::date as month, e.amount_minor
  from public.expenses e
  where e.deleted_at is null and not e.is_settlement
),
months as (
  select space_id, month, sum(amount_minor)::bigint as total
  from spend group by space_id, month
),
paid as (
  select sp.month, ep.member_id, sum(ep.amount_minor)::bigint as paid
  from spend sp join public.expense_payers ep on ep.expense_id = sp.id
  group by sp.month, ep.member_id
),
fair as (
  select sp.month, es.member_id, sum(es.amount_minor)::bigint as fair
  from spend sp join public.expense_splits es on es.expense_id = sp.id
  group by sp.month, es.member_id
)
select t.space_id, t.month, m.id as member_id, m.phone, m.user_id,
       coalesce(p.paid, 0) as paid_minor,
       coalesce(f.fair, 0) as fair_share_minor,
       coalesce(p.paid, 0) - coalesce(f.fair, 0) as difference_minor,
       t.total as month_total_minor
from months t
join public.space_members m on m.space_id = t.space_id
left join paid p on p.member_id = m.id and p.month = t.month
left join fair f on f.member_id = m.id and f.month = t.month;

-- Spending per space, month and category (null category is its own group).
create view public.space_monthly_categories with (security_invoker = true) as
select e.space_id,
       date_trunc('month', e.spent_on::timestamp)::date as month,
       e.category,
       sum(e.amount_minor)::bigint as total_minor,
       count(*)::int as expense_count
from public.expenses e
where e.deleted_at is null and not e.is_settlement
group by e.space_id, date_trunc('month', e.spent_on::timestamp), e.category;

-- Loan summaries as of a date, so the schedule maths is testable; loan_summaries pins it to today.
-- Instalment k (1..n) is due on due_day of the k-th month after start_on's month, where
-- n = ceil(principal / instalment). An instalment counts as due once its date has passed, so the
-- borrower is on track on the due day itself. Monthly-schedule columns are null for flexible loans.
create function public.loan_summaries_as_of(p_as_of date)
returns table (
  loan_id uuid,
  lender_phone public.e164,
  borrower_phone public.e164,
  lender_id uuid,
  borrower_id uuid,
  schedule_type public.loan_schedule_type,
  principal_minor bigint,
  installment_minor bigint,
  due_day smallint,
  start_on date,
  closed_at timestamptz,
  repaid_minor bigint,
  outstanding_minor bigint,
  confirmed_count int,
  pending_count int,
  pending_minor bigint,
  disputed_count int,
  installments_total int,
  installments_paid int,
  installments_due int,
  expected_minor bigint,
  next_due_on date,
  ends_on date,
  on_track boolean
)
language sql stable set search_path = '' as $$
  select l.id, l.lender_phone, l.borrower_phone, l.lender_id, l.borrower_id, l.schedule_type,
         l.principal_minor, l.installment_minor, l.due_day, l.start_on, l.closed_at,
         r.repaid,
         l.principal_minor - r.repaid,
         r.confirmed_count, r.pending_count, r.pending_minor, r.disputed_count,
         s.n,
         case when r.repaid = l.principal_minor then s.n else (r.repaid / l.installment_minor)::int end,
         d.due,
         d.expected,
         case when l.closed_at is null and r.repaid < l.principal_minor and d.due < s.n
              then (s.first_month + make_interval(months => d.due + 1))::date + (l.due_day - 1) end,
         (s.first_month + make_interval(months => s.n))::date + (l.due_day - 1),
         case when l.closed_at is null then r.repaid >= d.expected end
  from public.loans l
  cross join lateral (
    select coalesce(sum(lr.principal_minor) filter (where lr.status = 'confirmed'), 0)::bigint as repaid,
           count(*) filter (where lr.status = 'confirmed')::int as confirmed_count,
           count(*) filter (where lr.status = 'pending')::int as pending_count,
           coalesce(sum(lr.amount_minor) filter (where lr.status = 'pending'), 0)::bigint as pending_minor,
           count(*) filter (where lr.status = 'disputed')::int as disputed_count
    from public.loan_repayments lr
    where lr.loan_id = l.id
  ) r
  cross join lateral (
    -- n and the month index of p_as_of relative to start_on's month; null for flexible loans.
    select ((l.principal_minor + l.installment_minor - 1) / l.installment_minor)::int as n,
           date_trunc('month', l.start_on::timestamp) as first_month,
           ((extract(year from p_as_of) - extract(year from l.start_on)) * 12
             + extract(month from p_as_of) - extract(month from l.start_on))::int as months_in
  ) s
  cross join lateral (
    -- Instalments whose due date is before p_as_of, clamped to 0..n.
    select case when l.schedule_type = 'monthly' then
             greatest(0, least(s.n, s.months_in - 1 + (l.due_day < extract(day from p_as_of))::int))
           end as due
  ) d0
  cross join lateral (
    -- least() ignores nulls, so guard it to keep expected null for flexible loans.
    select d0.due,
           case when d0.due is not null then least(l.principal_minor, l.installment_minor * d0.due) end as expected
  ) d
$$;

revoke execute on function public.loan_summaries_as_of(date) from public, anon;
grant execute on function public.loan_summaries_as_of(date) to authenticated;

-- "Today" is India's date: v1 is INR only, and due dates are Indian calendar days.
create view public.loan_summaries with (security_invoker = true) as
select * from public.loan_summaries_as_of((now() at time zone 'Asia/Kolkata')::date);

revoke all on public.space_member_balances, public.space_monthly_fairness,
              public.space_monthly_categories, public.loan_summaries from anon, authenticated;
grant select on public.space_member_balances, public.space_monthly_fairness,
                public.space_monthly_categories, public.loan_summaries to authenticated;
