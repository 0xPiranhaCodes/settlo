-- Activity filters, unread and 'Question this' (#109).
--
-- Filters: activity_feed takes a space or 'loans only' and applies it where the page is built, to
-- the caller's own memberships, so a filter can only narrow what they already see and each kept
-- space or loan still contributes one keyset page. Ordering, the cursor and the paging contract
-- are unchanged (20261115100000_activity_feed.sql).
--
-- Unread: one row per user holding the created_at of the newest entry they have seen. It lives on
-- the server so opening Activity on one phone clears the bell on the other; the app counts newer
-- entries in its mirror, so the count works offline.
--
-- 'Question this': a short note on an 'edited' row, from an accepted member of that space who is
-- not the editor. It is stored out of the API's reach and read only through activity_feed, which
-- shows the row, and so the note, only to accepted, active members of the space.

create table public.activity_seen (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  seen_at timestamptz not null
);
alter table public.activity_seen enable row level security;
create policy activity_seen_select on public.activity_seen for select to authenticated
  using (user_id = (select public.verified_uid()));
revoke all on public.activity_seen from public, anon, authenticated;
grant select on public.activity_seen to authenticated;

-- Moves the caller's cursor forward to p_at, never back and never past now, so replaying a queued
-- call or two phones answering out of order changes nothing.
create function public.mark_activity_seen(p_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.verified_uid() is null then
    raise exception 'mark_activity_seen: caller has no verified phone' using errcode = '42501';
  end if;
  if p_at is null then
    raise exception 'mark_activity_seen: a time is required' using errcode = '22023';
  end if;
  insert into public.activity_seen (user_id, seen_at) values (public.verified_uid(), least(p_at, now()))
  on conflict (user_id) do update set seen_at = greatest(activity_seen.seen_at, excluded.seen_at);
end $$;

create table private.activity_questions (
  activity_id bigint not null references public.activity (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  note text not null check (char_length(note) between 1 and 280),
  created_at timestamptz not null default now(),
  primary key (activity_id, author_id)
);
revoke all on table private.activity_questions from public, anon, authenticated;

-- One note per member per edit; asking again replaces it, so a replayed call is harmless.
create function public.question_activity(p_activity_id bigint, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_note text := btrim(coalesce(p_note, ''));
begin
  if public.verified_uid() is null then
    raise exception 'question_activity: caller has no verified phone' using errcode = '42501';
  end if;
  if v_note = '' or char_length(v_note) > 280 then
    raise exception 'question_activity: a note of 1 to 280 characters is required' using errcode = '22023';
  end if;
  -- One answer for a row that is missing, not an edit, the caller's own, or in a space they are
  -- not an accepted, active member of, so the call cannot probe for rows.
  if not exists (
    select from public.activity a
     where a.id = p_activity_id and a.action = 'edited' and a.space_id is not null
       and a.actor_id is distinct from public.verified_uid()
       and public.is_accepted_member(a.space_id)) then
    raise exception 'question_activity: not an edit you can question' using errcode = '42501';
  end if;
  -- The app's rule for an Indian phone number (packages/core/lib/export/names.dart, _phone).
  -- shortcut: ASCII digits and separators only; the app also redacts other scripts' digits and
  -- invisible separators before sending and again when showing. Port that normalisation here if
  -- notes are ever shown outside the app.
  v_note := regexp_replace(v_note,
    '(?<!\d)\(?(?:(?:\+91|91|0)[ .()\-]{0,2})?\d(?:[ .()\-]{0,2}\d){9}(?!\d)', '••••', 'g');
  insert into private.activity_questions (activity_id, author_id, note)
  values (p_activity_id, public.verified_uid(), v_note)
  on conflict (activity_id, author_id) do update set note = excluded.note;
end $$;

revoke execute on function public.mark_activity_seen(timestamptz), public.question_activity(bigint, text)
  from public, anon;
grant execute on function public.mark_activity_seen(timestamptz), public.question_activity(bigint, text)
  to authenticated;

-- The feed with its filters and each row's questions. The arguments and the return type change, so
-- it is dropped and recreated; callers that name only the old arguments resolve to this one.
drop function public.activity_feed(timestamptz, bigint, int);
create function public.activity_feed(
  p_before_at timestamptz default null, p_before_id bigint default null, p_limit int default 30,
  p_space_id uuid default null, p_loans_only boolean default false
) returns table (
  id bigint, created_at timestamptz, action text, kind text,
  space_id uuid, space_name text, expense_id uuid, loan_id uuid, repayment_id uuid,
  by_me boolean, actor_name text, counterparty text, description text, amount_minor bigint,
  before_description text, before_amount_minor bigint, status text, my_side text,
  link_only boolean, questions jsonb
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
       and (p_space_id is null or m.space_id = p_space_id) and not coalesce(p_loans_only, false)
  ), my_loans as (
    select l.id from me, public.loans l
     where l.lender_id = me.uid and l.lender_accepted_at is not null and p_space_id is null
    union
    select l.id from me, public.loans l
     where l.borrower_id = me.uid and l.borrower_accepted_at is not null and p_space_id is null
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
         coalesce((a.after ->> 'link_only')::boolean, false),
         -- Who asked is named as the row's actor is.
         (select jsonb_agg(jsonb_build_object(
                   'by_me', q.author_id = me.uid,
                   'name', (select coalesce(m.name, case when m.accepted_at is not null then p.name end, m.phone::text)
                              from public.space_members m
                              left join public.profiles p on p.id = m.user_id
                             where m.space_id = a.space_id and m.user_id = q.author_id
                             order by m.left_at desc nulls first
                             limit 1),
                   'note', q.note) order by q.created_at, q.author_id)
            from private.activity_questions q
           where q.activity_id = a.id)
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

revoke all on function public.activity_feed(timestamptz, bigint, int, uuid, boolean) from public, anon, authenticated;
grant execute on function public.activity_feed(timestamptz, bigint, int, uuid, boolean) to authenticated;
