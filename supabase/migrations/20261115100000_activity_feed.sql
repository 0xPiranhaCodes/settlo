-- Activity feed and 'Needs you' (#91): read-only views over activity, settle-ups and repayments.
-- Both are security_invoker, so RLS on the tables they read still applies, and each also requires
-- the caller to be an accepted, active member of the space or an accepted party to the loan: a
-- departed member, an outsider and a pending claimant (verified, not yet accepted) see no rows.
-- The feed pages by keyset on id (`id=lt.<last id>&order=id.desc`), never by offset.

-- One row per activity row, with what the app needs to say it in a line. my_side is which way a
-- settle-up or repayment moves money for the caller ('in' to them, 'out' from them); status is the
-- settle-up's or repayment's current state, so a row of something later disputed reads as such.
create view public.activity_feed with (security_invoker = true) as
select a.id, a.created_at, a.action,
       case when a.repayment_id is not null then 'repayment'
            when a.loan_id is not null then 'loan'
            when a.expense_id is null then 'member'
            when e.is_settlement then 'settlement'
            else 'expense' end as kind,
       a.space_id, s.name as space_name, a.expense_id, a.loan_id, a.repayment_id,
       coalesce(a.actor_id = public.verified_uid(), false) as by_me,
       case when a.loan_id is not null then them.name
            else (select coalesce(m.name, p.name, m.phone::text)
                    from public.space_members m
                    left join public.profiles p on p.id = m.user_id
                   where m.space_id = a.space_id and m.user_id = a.actor_id
                   order by m.left_at desc nulls first
                   limit 1) end as actor_name,
       them.name as counterparty,
       -- 'rejected' rows name the number that declined (the creator entered it).
       coalesce(a.after ->> 'description', a.after ->> 'phone') as description,
       coalesce((a.after ->> 'amount_minor')::bigint, (a.after ->> 'principal_minor')::bigint) as amount_minor,
       case when a.action = 'edited' then a.before ->> 'description' end as before_description,
       case when a.action = 'edited' then (a.before ->> 'amount_minor')::bigint end as before_amount_minor,
       case when a.repayment_id is not null then r.status
            when e.deleted_at is not null then 'deleted'
            else e.settlement_status end as status,
       case when a.repayment_id is not null then case when me_lender then 'in' else 'out' end
            when e.is_settlement then (
              select case when public.is_me(pm.user_id, pm.phone) then 'out'
                          when public.is_me(sm.user_id, sm.phone) then 'in' end
                from public.expense_payers ep
                join public.space_members pm on pm.id = ep.member_id
                join public.expense_splits es on es.expense_id = ep.expense_id
                join public.space_members sm on sm.id = es.member_id
               where ep.expense_id = a.expense_id
               limit 1) end as my_side
from public.activity a
left join public.spaces s on s.id = a.space_id
left join public.expenses e on e.id = a.expense_id
left join public.loans l on l.id = a.loan_id
left join public.loan_repayments r on r.id = a.repayment_id
cross join lateral (select public.is_me(l.lender_id, l.lender_phone) as me_lender) side
left join lateral (
  select coalesce(p.name, case when side.me_lender then l.borrower_phone else l.lender_phone end::text) as name
    from (select 1) one
    left join public.profiles p on p.id = case when side.me_lender then l.borrower_id else l.lender_id end
   where l.id is not null
) them on true
where (a.space_id is not null and public.is_accepted_member(a.space_id))
   or (a.loan_id is not null and public.is_accepted_party(a.loan_id));

-- What waits for the caller's answer: settle-ups they are the payee of, and repayments the other
-- side of a loan recorded. counterparty is who paid. Same gate as the feed.
create view public.needs_you with (security_invoker = true) as
select 'settlement'::text as kind, ps.expense_id as id, ps.space_id, s.name as space_name,
       null::uuid as loan_id, coalesce(m.name, p.name, m.phone::text) as counterparty,
       ps.amount_minor, ps.spent_on as paid_on, ps.created_at
from public.pending_settlements ps
join public.spaces s on s.id = ps.space_id
join public.space_members m on m.id = ps.payer_member_id
left join public.profiles p on p.id = m.user_id
where ps.awaiting_me and public.is_accepted_member(ps.space_id)
union all
select 'repayment', r.id, null, null, r.loan_id,
       case when public.is_me(l.lender_id, l.lender_phone) then coalesce(bp.name, l.borrower_phone::text)
            else coalesce(lp.name, l.lender_phone::text) end,
       r.amount_minor, r.paid_on, r.created_at
from public.loan_repayments r
join public.loans l on l.id = r.loan_id
left join public.profiles lp on lp.id = l.lender_id
left join public.profiles bp on bp.id = l.borrower_id
where r.status = 'pending'
  and ((l.lender_accepted_at is not null and public.is_me(l.lender_id, l.lender_phone)
        and r.recorded_by is distinct from l.lender_id)
    or (l.borrower_accepted_at is not null and public.is_me(l.borrower_id, l.borrower_phone)
        and r.recorded_by is distinct from l.borrower_id));

revoke all on public.activity_feed, public.needs_you from public, anon, authenticated;
grant select on public.activity_feed, public.needs_you to authenticated;
