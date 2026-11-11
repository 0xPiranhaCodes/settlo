-- Recipient-only nudges and persisted opt-out (#107). No push credentials.
create table public.reminder_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true
);
alter table public.reminder_preferences enable row level security;
create policy reminder_preferences_select on public.reminder_preferences for select to authenticated
  using (user_id = public.verified_uid());
revoke all on public.reminder_preferences from anon, authenticated;
grant select on public.reminder_preferences to authenticated;
create trigger live_caller before insert or update or delete on public.reminder_preferences
  for each statement execute function private.guard_live_caller();

create function public.set_reminders(p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.verified_uid() is null then raise exception 'Not allowed' using errcode = '42501'; end if;
  if p_enabled is null then raise exception 'Choose on or off' using errcode = '22023'; end if;
  insert into public.reminder_preferences(user_id, enabled) values(public.verified_uid(), p_enabled)
  on conflict(user_id) do update set enabled = excluded.enabled;
end $$;
revoke all on function public.set_reminders(boolean) from public, anon;
grant execute on function public.set_reminders(boolean) to authenticated;

alter table public.activity add column recipient_id uuid references public.profiles(id) on delete restrict;
alter table public.activity drop constraint activity_action_check,
  add constraint activity_action_check check (action in
  ('created','edited','deleted','restored','recorded','confirmed','disputed','rejected','closed','reminded','due'));
-- Restrictive policy also covers direct table reads, not just the feed RPC.
create policy activity_recipient on public.activity as restrictive for select to authenticated
  using (recipient_id is null or recipient_id = public.verified_uid());

create table public.loan_reminders (
  loan_id uuid primary key references public.loans(id),
  sent_at timestamptz not null,
  sender_id uuid not null references public.profiles(id)
);
alter table public.loan_reminders enable row level security;
create policy loan_reminders_select on public.loan_reminders for select to authenticated
  using (exists (select from public.loans l where l.id = loan_id and
    ((l.lender_id = public.verified_uid() and l.lender_accepted_at is not null) or
     (l.borrower_id = public.verified_uid() and l.borrower_accepted_at is not null))));
revoke all on public.loan_reminders from anon, authenticated;
grant select on public.loan_reminders to authenticated;
create trigger live_caller before insert or update or delete on public.loan_reminders
  for each statement execute function private.guard_live_caller();

-- Lock the loan, so even the very first two concurrent sends share the same limit.
-- A retry returns the existing deadline; it never sends twice or extends the window.
create function public.remind_loan(p_loan_id uuid) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := public.verified_uid(); l public.loans; recipient uuid; last_at timestamptz; accepts_reminders boolean;
begin
  select * into l from public.loans where id = p_loan_id for update;
  if me is null or l.id is null or not coalesce((
    (l.lender_id = me and l.lender_accepted_at is not null) or
    (l.borrower_id = me and l.borrower_accepted_at is not null)), false) then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  recipient := case when l.lender_id = me then l.borrower_id else l.lender_id end;
  if l.closed_at is not null or recipient is null or l.lender_accepted_at is null or l.borrower_accepted_at is null
     or not exists(select from auth.users where id = recipient) then
    raise exception 'Reminder unavailable' using errcode = '22023';
  end if;
  select sent_at into last_at from public.loan_reminders where loan_id = l.id;
  if last_at > now() - interval '24 hours' then return last_at + interval '24 hours'; end if;
  -- Serialize opt-out and delivery on the preference row; absence means on.
  insert into public.reminder_preferences(user_id) values(recipient) on conflict do nothing;
  select enabled into accepts_reminders from public.reminder_preferences where user_id = recipient for update;
  insert into public.loan_reminders values(l.id, now(), me)
    on conflict(loan_id) do update set sent_at = excluded.sent_at, sender_id = excluded.sender_id;
  -- Opt-out consumes the same cooldown and response without revealing the preference.
  if accepts_reminders then
    insert into public.activity(loan_id, actor_id, recipient_id, action, after)
      values(l.id, me, recipient, 'reminded', jsonb_build_object('description', 'A gentle reminder to check your loan when you have a moment.'));
  end if;
  return now() + interval '24 hours';
end $$;
revoke all on function public.remind_loan(uuid) from public, anon;
grant execute on function public.remind_loan(uuid) to authenticated;

create table private.due_reminders (
  loan_id uuid references public.loans(id), due_on date, primary key(loan_id, due_on)
);
alter table private.due_reminders enable row level security;
revoke all on private.due_reminders from public, anon, authenticated;

-- Runs at 09:00 India time. The schedule is calendar-based, including December rollover.
-- Confirmed principal alone counts, matching loan_summaries; the last part-instalment is capped.
create function private.send_due_reminders(p_today date default (now() at time zone 'Asia/Kolkata')::date) returns void
language plpgsql security definer set search_path = '' as $$
declare
  today date := p_today;
  l public.loans; k int; repaid bigint; inserted int;
begin
  for l in select * from public.loans where closed_at is null and schedule_type = 'monthly'
      and borrower_accepted_at is not null and lender_accepted_at is not null
      and borrower_id is not null for update loop
    k := (extract(year from today)::int - extract(year from l.start_on)::int) * 12
         + extract(month from today)::int - extract(month from l.start_on)::int;
    if k < 1 or extract(day from today) <> l.due_day + 1
       or (k - 1)::bigint * l.installment_minor >= l.principal_minor then continue; end if;
    select coalesce(sum(principal_minor),0) into repaid from public.loan_repayments
      where loan_id = l.id and status = 'confirmed';
    if repaid >= least(k::bigint * l.installment_minor, l.principal_minor)
       or not exists(select from auth.users where id = l.borrower_id) then continue; end if;
    insert into public.reminder_preferences(user_id) values(l.borrower_id) on conflict do nothing;
    perform from public.reminder_preferences where user_id = l.borrower_id and enabled for update;
    if not found then continue; end if;
    insert into private.due_reminders values(l.id, today - 1) on conflict do nothing;
    get diagnostics inserted = row_count;
    if inserted = 1 then
      insert into public.activity(loan_id, actor_id, recipient_id, action, after)
        values(l.id, null, l.borrower_id, 'due', jsonb_build_object('description',
          'An instalment was due yesterday. Please check your loan when you can.'));
    end if;
  end loop;
end $$;
revoke all on function private.send_due_reminders(date) from public, anon, authenticated;
select cron.schedule('missed-instalment-reminders', '30 3 * * *', 'select private.send_due_reminders()');

create or replace function public.activity_feed(
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
             where a.loan_id = ml.id and (a.recipient_id is null or a.recipient_id = (select uid from me)) and (a.created_at, a.id) < (c.at, c.id)
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
                   'note', q.note, 'created_at', q.created_at) order by q.created_at, q.author_id)
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

