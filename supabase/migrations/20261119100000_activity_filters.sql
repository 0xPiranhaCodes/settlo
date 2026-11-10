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
-- shows the row, and so the note, only to accepted, active members of the space. Each note carries
-- when it was asked, so the app can count it as unread for the editor alone.

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

-- The app's phone redaction (redactPhones in packages/core/lib/export/names.dart), in full, so the
-- rule holds for any client of the API. An Indian phone number is 10 digits, optionally led by +91,
-- 91 or 0 (itself optionally in parentheses), with up to two spaces, dashes, dots or parentheses
-- between digits and no digit directly before or after. It is found in a folded copy of the text:
-- every Unicode decimal digit (Nd) becomes its ASCII digit, every space separator (Zs) a space,
-- every dash (Pd) a hyphen, and invisible format characters (Cf) are dropped, so none of them can
-- hide a number. Each match is replaced by •••• in the original text; the rest is returned as it
-- was. With p_keep_utr, a text that is nothing but 12 contiguous digits once trimmed is kept: as a
-- repayment's whole reference it is a UTR. An invisible character among them makes it not one.
-- The character tables are Unicode 16's.
create function private.redact_phones(p_text text, p_keep_utr boolean default false) returns text
language plpgsql immutable set search_path = '' as $$
declare
  -- The zero of every Nd digit set; each set is ten contiguous code points.
  c_zeros constant int[] := array[48,1632,1776,1984,2406,2534,2662,2790,2918,3046,3174,3302,3430,3558,3664,3792,
    3872,4160,4240,6112,6160,6470,6608,6784,6800,6992,7088,7232,7248,42528,43216,43264,43472,43504,43600,44016,
    65296,66720,68912,68928,69734,69872,69942,70096,70384,70736,70864,71248,71360,71376,71386,71472,71904,72016,
    72688,72784,73040,73120,73552,90416,92768,92864,93008,93552,118000,120782,120792,120802,120812,120822,123200,
    123632,124144,124401,125264,130032];
  -- Zs, Pd and Cf as inclusive ranges: first[i] to last[i].
  c_space_first constant int[] := array[32,160,5760,8192,8239,8287,12288];
  c_space_last constant int[] := array[32,160,5760,8202,8239,8287,12288];
  c_dash_first constant int[] := array[45,1418,1470,5120,6150,8208,11799,11802,11834,11840,11869,12316,12336,12448,
    65073,65112,65123,65293,68974,69293];
  c_dash_last constant int[] := array[45,1418,1470,5120,6150,8213,11799,11802,11835,11840,11869,12316,12336,12448,
    65074,65112,65123,65293,68974,69293];
  c_format_first constant int[] := array[173,1536,1564,1757,1807,2192,2274,6158,8203,8234,8288,8294,65279,65529,
    69821,69837,78896,113824,119155,917505,917536];
  c_format_last constant int[] := array[173,1541,1564,1757,1807,2193,2274,6158,8207,8238,8292,8303,65279,65531,
    69821,69837,78911,113827,119162,917505,917631];
  c_phone constant text := '(?<![0-9])\(?(?:(?:\+91|91|0)[ .()-]{0,2})?[0-9](?:[ .()-]{0,2}[0-9]){9}(?![0-9])';
  v_from text;      -- every digit, space and dash to fold
  v_to text;        -- what each folds to
  v_format text;    -- every invisible character; past the end of v_to, so translate drops them
  v_folded text;    -- p_text folded, without its invisible characters
  v_at int[];       -- v_at[i]: where character i of v_folded sits in p_text
  v_out text := '';
  v_next int := 1;  -- the first character of p_text not yet written
  v_start int;
  v_end int;
  n int := 1;
begin
  if p_text is null then
    return null;
  end if;
  select string_agg(chr(z.zero + k), '' order by z.o, k), string_agg(k::text, '' order by z.o, k)
    into v_from, v_to
    from unnest(c_zeros) with ordinality z(zero, o), generate_series(0, 9) k;
  select v_from || string_agg(chr(c), '' order by r.o, c), v_to || repeat(' ', count(*)::int)
    into v_from, v_to
    from unnest(c_space_first, c_space_last) with ordinality r(first, last, o), generate_series(r.first, r.last) c;
  select v_from || string_agg(chr(c), '' order by r.o, c), v_to || repeat('-', count(*)::int)
    into v_from, v_to
    from unnest(c_dash_first, c_dash_last) with ordinality r(first, last, o), generate_series(r.first, r.last) c;
  select string_agg(chr(c), '' order by r.o, c)
    into v_format
    from unnest(c_format_first, c_format_last) with ordinality r(first, last, o), generate_series(r.first, r.last) c;

  -- Invisible characters stay for this check, as non-digits.
  if p_keep_utr and btrim(translate(p_text, v_from, v_to), E' \t\n\r\f\v') ~ '^[0-9]{12}$' then
    return p_text;
  end if;

  select coalesce(string_agg(f.c, '' order by f.i), ''), coalesce(array_agg(f.i order by f.i), '{}')
    into v_folded, v_at
    from (select t.i::int as i, translate(t.c, v_from || v_format, v_to) as c
            from string_to_table(p_text, null) with ordinality t(c, i)) f
   where f.c <> '';
  loop
    v_start := regexp_instr(v_folded, c_phone, 1, n);
    exit when v_start = 0;
    v_end := regexp_instr(v_folded, c_phone, 1, n, 1);  -- one past the match
    v_out := v_out || substr(p_text, v_next, v_at[v_start] - v_next) || '••••';
    v_next := v_at[v_end - 1] + 1;
    n := n + 1;
  end loop;
  return v_out || substr(p_text, v_next);
end $$;
revoke execute on function private.redact_phones(text, boolean) from public, anon, authenticated;

create table private.activity_questions (
  activity_id bigint not null references public.activity (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  note text not null check (char_length(note) between 1 and 280),
  created_at timestamptz not null default now(),
  primary key (activity_id, author_id)
);
revoke all on table private.activity_questions from public, anon, authenticated;

-- One note per member per edit; asking again replaces it, so a replayed call is harmless. Phone
-- numbers are redacted here, on write, whatever the client did.
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
  insert into private.activity_questions (activity_id, author_id, note)
  values (p_activity_id, public.verified_uid(), private.redact_phones(v_note))
  -- A replay of the same note changes nothing; a new note counts as asked now, so its editor's
  -- bell rings again.
  on conflict (activity_id, author_id) do update set note = excluded.note, created_at = now()
    where activity_questions.note is distinct from excluded.note;
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
