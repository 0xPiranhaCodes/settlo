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

-- Phone redaction for anything a member types that other members will read. It starts from the
-- app's rule (redactPhones in packages/core/lib/export/names.dart) and is stricter: the server is
-- the authority, and redacts at least everything the app does.
--
-- An Indian phone number is 10 digits, optionally led by +91, 91 or 0 (itself optionally in
-- parentheses), with up to two spaces, dashes, dots or parentheses between digits and no digit
-- directly before or after. It is looked for in a folded copy of the text, made so that nothing
-- can dress a number up or split it:
--   * NFKC first, which turns compatibility lookalikes (circled, superscript, subscript,
--     parenthesised and fullwidth digits) into plain ones;
--   * then every Unicode decimal digit (Nd) becomes its ASCII digit, every space separator (Zs) a
--     space and every dash (Pd) a hyphen;
--   * and nonspacing and enclosing marks (Mn, Me: combining marks such as U+034F, keycaps, and the
--     variation selectors U+FE00-FE0F and U+E0100-E01EF) and invisible format characters (Cf)
--     are dropped.
-- NFKC is applied a character at a time, so each folded character still knows which original
-- character it came from. That finds the same numbers as normalising the whole text: what
-- whole-text NFKC adds is composing a base with its marks, and the marks are dropped anyway.
-- Each match is replaced by •••• in the original text, from the first original character it
-- touches to the last; the rest is returned as it was.
--
-- With p_keep_utr, a text that is nothing but 12 contiguous Nd digits once trimmed is kept: as a
-- repayment's whole reference it is a UTR. Anything else among them, visible or not, makes it not
-- one. The character tables are Unicode 16's.
create function private.redact_phones(p_text text, p_keep_utr boolean default false) returns text
language plpgsql immutable set search_path = '' as $$
declare
  -- The zero of every Nd digit set; each set is ten contiguous code points.
  c_zeros constant int[] := array[48,1632,1776,1984,2406,2534,2662,2790,2918,3046,3174,3302,3430,3558,3664,3792,
    3872,4160,4240,6112,6160,6470,6608,6784,6800,6992,7088,7232,7248,42528,43216,43264,43472,43504,43600,44016,
    65296,66720,68912,68928,69734,69872,69942,70096,70384,70736,70864,71248,71360,71376,71386,71472,71904,72016,
    72688,72784,73040,73120,73552,90416,92768,92864,93008,93552,118000,120782,120792,120802,120812,120822,123200,
    123632,124144,124401,125264,130032];
  -- Zs and Pd as inclusive ranges: first[i] to last[i].
  c_space_first constant int[] := array[32,160,5760,8192,8239,8287,12288];
  c_space_last constant int[] := array[32,160,5760,8202,8239,8287,12288];
  c_dash_first constant int[] := array[45,1418,1470,5120,6150,8208,11799,11802,11834,11840,11869,12316,12336,12448,
    65073,65112,65123,65293,68974,69293];
  c_dash_last constant int[] := array[45,1418,1470,5120,6150,8213,11799,11802,11835,11840,11869,12316,12336,12448,
    65074,65112,65123,65293,68974,69293];
  -- Mn, Me and Cf, merged: what is dropped.
  c_drop_first constant int[] := array[
    173,768,1155,1425,1471,1473,1476,1479,1536,1552,1564,1611,1648,1750,1759,1767,1770,1807,1809,1840,1958,2027,2045,
    2070,2075,2085,2089,2137,2192,2199,2250,2362,2364,2369,2381,2385,2402,2433,2492,2497,2509,2530,2558,2561,2620,
    2625,2631,2635,2641,2672,2677,2689,2748,2753,2759,2765,2786,2810,2817,2876,2879,2881,2893,2901,2914,2946,3008,
    3021,3072,3076,3132,3134,3142,3146,3157,3170,3201,3260,3263,3270,3276,3298,3328,3387,3393,3405,3426,3457,3530,
    3538,3542,3633,3636,3655,3761,3764,3784,3864,3893,3895,3897,3953,3968,3974,3981,3993,4038,4141,4146,4153,4157,
    4184,4190,4209,4226,4229,4237,4253,4957,5906,5938,5970,6002,6068,6071,6086,6089,6109,6155,6277,6313,6432,6439,
    6450,6457,6679,6683,6742,6744,6752,6754,6757,6771,6783,6832,6912,6964,6966,6972,6978,7019,7040,7074,7080,7083,
    7142,7144,7149,7151,7212,7222,7376,7380,7394,7405,7412,7416,7616,8203,8234,8288,8294,8400,11503,11647,11744,12330,
    12441,42607,42612,42654,42736,43010,43014,43019,43045,43052,43204,43232,43263,43302,43335,43392,43443,43446,43452,
    43493,43561,43569,43573,43587,43596,43644,43696,43698,43703,43710,43713,43756,43766,44005,44008,44013,64286,65024,
    65056,65279,65529,66045,66272,66422,68097,68101,68108,68152,68159,68325,68900,68969,69291,69372,69446,69506,69633,
    69688,69744,69747,69759,69811,69817,69821,69826,69837,69888,69927,69933,70003,70016,70070,70089,70095,70191,70196,
    70198,70206,70209,70367,70371,70400,70459,70464,70502,70512,70587,70606,70608,70610,70625,70712,70722,70726,70750,
    70835,70842,70847,70850,71090,71100,71103,71132,71219,71229,71231,71339,71341,71344,71351,71453,71455,71458,71463,
    71727,71737,71995,71998,72003,72148,72154,72160,72193,72243,72251,72263,72273,72281,72330,72344,72752,72760,72767,
    72850,72874,72882,72885,73009,73018,73020,73023,73031,73104,73109,73111,73459,73472,73526,73536,73538,73562,78896,
    78919,90398,90413,92912,92976,94031,94095,94180,113821,113824,118528,118576,119143,119155,119173,119210,119362,
    121344,121403,121461,121476,121499,121505,122880,122888,122907,122915,122918,123023,123184,123566,123628,124140,
    124398,125136,125252,917505,917536,917760];
  c_drop_last constant int[] := array[
    173,879,1161,1469,1471,1474,1477,1479,1541,1562,1564,1631,1648,1757,1764,1768,1773,1807,1809,1866,1968,2035,2045,
    2073,2083,2087,2093,2139,2193,2207,2306,2362,2364,2376,2381,2391,2403,2433,2492,2500,2509,2531,2558,2562,2620,
    2626,2632,2637,2641,2673,2677,2690,2748,2757,2760,2765,2787,2815,2817,2876,2879,2884,2893,2902,2915,2946,3008,
    3021,3072,3076,3132,3136,3144,3149,3158,3171,3201,3260,3263,3270,3277,3299,3329,3388,3396,3405,3427,3457,3530,
    3540,3542,3633,3642,3662,3761,3772,3790,3865,3893,3895,3897,3966,3972,3975,3991,4028,4038,4144,4151,4154,4158,
    4185,4192,4212,4226,4230,4237,4253,4959,5908,5939,5971,6003,6069,6077,6086,6099,6109,6159,6278,6313,6434,6440,
    6450,6459,6680,6683,6742,6750,6752,6754,6764,6780,6783,6862,6915,6964,6970,6972,6978,7027,7041,7077,7081,7085,
    7142,7145,7149,7153,7219,7223,7378,7392,7400,7405,7412,7417,7679,8207,8238,8292,8303,8432,11505,11647,11775,12333,
    12442,42610,42621,42655,42737,43010,43014,43019,43046,43052,43205,43249,43263,43309,43345,43394,43443,43449,43453,
    43493,43566,43570,43574,43587,43596,43644,43696,43700,43704,43711,43713,43757,43766,44005,44008,44013,64286,65039,
    65071,65279,65531,66045,66272,66426,68099,68102,68111,68154,68159,68326,68903,68973,69292,69375,69456,69509,69633,
    69702,69744,69748,69761,69814,69818,69821,69826,69837,69890,69931,69940,70003,70017,70078,70092,70095,70193,70196,
    70199,70206,70209,70367,70378,70401,70460,70464,70508,70516,70592,70606,70608,70610,70626,70719,70724,70726,70750,
    70840,70842,70848,70851,71093,71101,71104,71133,71226,71229,71232,71339,71341,71349,71351,71453,71455,71461,71467,
    71735,71738,71996,71998,72003,72151,72155,72160,72202,72248,72254,72263,72278,72283,72342,72345,72758,72765,72767,
    72871,72880,72883,72886,73014,73018,73021,73029,73031,73105,73109,73111,73460,73473,73530,73536,73538,73562,78912,
    78933,90409,90415,92916,92982,94031,94098,94180,113822,113827,118573,118598,119145,119170,119179,119213,119364,
    121398,121452,121461,121476,121503,121519,122886,122904,122913,122916,122922,123023,123190,123566,123631,124143,
    124399,125142,125258,917505,917631,917999];
  c_phone constant text := '(?<![0-9])\(?(?:(?:\+91|91|0)[ .()-]{0,2})?[0-9](?:[ .()-]{0,2}[0-9]){9}(?![0-9])';
  v_from text;      -- every digit, space and dash to fold
  v_to text;        -- what each folds to
  v_drop text;      -- every mark and invisible character; past the end of v_to, so translate drops them
  v_folded text;    -- p_text folded, without them
  v_at int[];       -- v_at[i]: which character of p_text character i of v_folded came from
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
    into v_drop
    from unnest(c_drop_first, c_drop_last) with ordinality r(first, last, o), generate_series(r.first, r.last) c;

  -- Marks and invisible characters stay for this check, as non-digits.
  if p_keep_utr and btrim(translate(p_text, v_from, v_to), E' \t\n\r\f\v') ~ '^[0-9]{12}$' then
    return p_text;
  end if;

  -- One original character can fold to none (dropped), one, or several (U+2473 is '20').
  select coalesce(string_agg(g.c, '' order by f.i, g.j), ''), coalesce(array_agg(f.i::int order by f.i, g.j), '{}')
    into v_folded, v_at
    from string_to_table(p_text, null) with ordinality f(c, i)
    cross join lateral string_to_table(
      translate(normalize(f.c, NFKC), v_from || v_drop, v_to), null) with ordinality g(c, j);
  loop
    v_start := regexp_instr(v_folded, c_phone, 1, n);
    exit when v_start = 0;
    v_end := regexp_instr(v_folded, c_phone, 1, n, 1);  -- one past the match
    v_out := v_out || substr(p_text, v_next, greatest(v_at[v_start] - v_next, 0)) || '••••';
    -- Past the match's last character and whatever was dropped after it, so a mark that sat on
    -- the last digit is not left sitting on the dots.
    v_next := greatest(v_at[v_end - 1] + 1, coalesce(v_at[v_end], char_length(p_text) + 1));
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

-- The write barrier of delete_account (#74): a deleted account's late mark or question is refused.
create trigger live_caller before insert or update or delete on public.activity_seen
  for each statement execute function private.guard_live_caller();
create trigger live_caller before insert or update or delete on private.activity_questions
  for each statement execute function private.guard_live_caller();
