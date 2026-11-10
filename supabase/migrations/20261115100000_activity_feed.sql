-- Activity feed and 'Needs you' (#91). The feed is an RPC that starts from the caller's own
-- memberships, never from activity at large: a scan of activity filtered by RLS would read every
-- other tenant's newer rows before finding the caller's (PR #101 review: 9 s for a first page).
-- Each of the caller's spaces and loans contributes at most one page through the (key, created_at,
-- id) indexes below, and the newest of those make the page. Rows are ordered by (created_at, id),
-- newest first, and the next page starts strictly below the last row seen. Contract: for rows
-- committed before the first page loaded, pages are strict and stable (no row repeats or is
-- skipped). created_at is the transaction's start, so a transaction that commits after the client
-- has paged past its created_at lands behind the cursor and is not in later pages; it appears on
-- pull-to-refresh, which reloads from the top (tests/21_activity_feed_race.test.sql).
--
-- Who sees what is unchanged from the review: only spaces the caller is an accepted, active member
-- of and loans they are an accepted party to. A departed member, an outsider, a pending claimant,
-- an unverified user and anon see nothing. The RPC is security definer so it can read past RLS
-- after making those checks itself (as the RLS helpers do), and names a profile only where RLS
-- would show it (can_see_profile: the person accepted their membership or loan side).

-- The keyset paths. They replace (space_id, created_at desc) and (loan_id, created_at desc).
drop index public.activity_space_id_idx;
drop index public.activity_loan_id_idx;
create index activity_space_feed_idx on public.activity (space_id, created_at, id) where space_id is not null;
create index activity_loan_feed_idx on public.activity (loan_id, created_at, id) where loan_id is not null;

-- One row per activity row, newest first, with what the app needs to say it in a line. my_side is
-- which way a settle-up or repayment moves money for the caller ('in' to them, 'out' from them);
-- status is the settle-up's or repayment's current state. p_before_at / p_before_id are the
-- created_at and id of the last row already shown; null for the first page.
create function public.activity_feed(
  p_before_at timestamptz default null, p_before_id bigint default null, p_limit int default 30
) returns table (
  id bigint, created_at timestamptz, action text, kind text,
  space_id uuid, space_name text, expense_id uuid, loan_id uuid, repayment_id uuid,
  by_me boolean, actor_name text, counterparty text, description text, amount_minor bigint,
  before_description text, before_amount_minor bigint, status text, my_side text,
  link_only boolean
)
language sql stable security definer set search_path = '' as $$
  with me as (
    select public.verified_uid() as uid
  ), cursor as (
    select coalesce(p_before_at, 'infinity'::timestamptz) as at,
           coalesce(p_before_id, 9223372036854775807) as id,
           least(greatest(coalesce(p_limit, 30), 1), 100) as n
  ), my_spaces as (
    select m.space_id
      from me, public.space_members m
      join public.spaces s on s.id = m.space_id
     where m.user_id = me.uid and m.left_at is null and m.accepted_at is not null and s.deleted_at is null
  ), my_loans as (
    select l.id from me, public.loans l where l.lender_id = me.uid and l.lender_accepted_at is not null
    union
    select l.id from me, public.loans l where l.borrower_id = me.uid and l.borrower_accepted_at is not null
  ), page as (
    select k.created_at, k.id
      from (
        select k.created_at, k.id
          from my_spaces ms, cursor c
          cross join lateral (
            select a.created_at, a.id from public.activity a
             where a.space_id = ms.space_id and (a.created_at, a.id) < (c.at, c.id)
             order by a.created_at desc, a.id desc
             limit c.n) k
        union all
        select k.created_at, k.id
          from my_loans ml, cursor c
          cross join lateral (
            select a.created_at, a.id from public.activity a
             where a.loan_id = ml.id and (a.created_at, a.id) < (c.at, c.id)
             order by a.created_at desc, a.id desc
             limit c.n) k
      ) k
     order by k.created_at desc, k.id desc
     limit (select n from cursor)
  )
  select a.id, a.created_at, a.action,
         case when coalesce((a.after ->> 'link_only')::boolean, false) then 'member'
              when a.repayment_id is not null then 'repayment'
              when a.loan_id is not null then 'loan'
              when a.expense_id is null then 'member'
              when e.is_settlement then 'settlement'
              else 'expense' end,
         a.space_id, s.name, a.expense_id, a.loan_id, a.repayment_id,
         coalesce(a.actor_id = me.uid, false),
         case when a.loan_id is not null then them.name
              else (select coalesce(m.name, case when m.accepted_at is not null then p.name end, m.phone::text)
                      from public.space_members m
                      left join public.profiles p on p.id = m.user_id
                     where m.space_id = a.space_id and m.user_id = a.actor_id
                     order by m.left_at desc nulls first
                     limit 1) end,
         them.name,
         case when coalesce((a.after ->> 'link_only')::boolean, false) then
           coalesce((select m.name from public.space_members m
                      where m.id = (a.after ->> 'member_id')::uuid),
                    them.name, a.after ->> 'phone')
         else coalesce(a.after ->> 'description', a.after ->> 'phone') end,
         coalesce((a.after ->> 'amount_minor')::bigint, (a.after ->> 'principal_minor')::bigint),
         case when a.action = 'edited' then a.before ->> 'description' end,
         case when a.action = 'edited' then (a.before ->> 'amount_minor')::bigint end,
         case when a.repayment_id is not null then r.status
              when e.deleted_at is not null then 'deleted'
              else e.settlement_status end,
         case when a.repayment_id is not null then case when side.me_lender then 'in' else 'out' end
              when e.is_settlement then (
                select case when public.is_me(pm.user_id, pm.phone) then 'out'
                            when public.is_me(sm.user_id, sm.phone) then 'in' end
                  from public.expense_payers ep
                  join public.space_members pm on pm.id = ep.member_id
                  join public.expense_splits es on es.expense_id = ep.expense_id
                  join public.space_members sm on sm.id = es.member_id
                 where ep.expense_id = a.expense_id
                 limit 1) end,
         coalesce((a.after ->> 'link_only')::boolean, false)
    from page
    cross join me
    join public.activity a on a.id = page.id
    left join public.spaces s on s.id = a.space_id
    left join public.expenses e on e.id = a.expense_id
    left join public.loans l on l.id = a.loan_id
    left join public.loan_repayments r on r.id = a.repayment_id
    cross join lateral (select l.lender_id = me.uid as me_lender) side
    left join lateral (
      select coalesce(case when (case when side.me_lender then l.borrower_accepted_at else l.lender_accepted_at end)
                                is not null then p.name end,
                      case when side.me_lender then l.borrower_phone else l.lender_phone end::text) as name
        from (select 1) one
        left join public.profiles p on p.id = case when side.me_lender then l.borrower_id else l.lender_id end
       where l.id is not null
    ) them on true
   order by a.created_at desc, a.id desc
$$;

revoke all on function public.activity_feed(timestamptz, bigint, int) from public, anon, authenticated;
grant execute on function public.activity_feed(timestamptz, bigint, int) to authenticated;

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

revoke all on public.needs_you from public, anon, authenticated;
grant select on public.needs_you to authenticated;
