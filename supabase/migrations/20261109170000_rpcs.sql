-- RPCs (#10): create_space, add_expense (atomic, idempotent), lookup_phones (hashed, quota'd).
-- create_space and add_expense are security invoker: RLS (#8) stays the gate, and the functions
-- add validation, atomicity and idempotency on top. lookup_phones is security definer because it
-- must match profiles the caller cannot see; it returns only hashes the caller already holds.
--
-- Idempotency is payload-bound (ADR 0004): each key is stored with a SHA-256 fingerprint of the
-- normalised request. Same key and same payload returns the original id; same key and a different
-- payload (or someone else's key) raises SQLSTATE PT409 with hint 'idempotency_conflict', which
-- PostgREST answers as HTTP 409 and the offline queue surfaces as a conflict.

alter table public.spaces add column idempotency_hash text;
alter table public.expenses add column idempotency_hash text;
grant insert (idempotency_hash) on public.spaces, public.expenses to authenticated;

-- Server-only state, outside the PostgREST schemas and with no client privileges, so no client can
-- read or reset it. RLS is on with no policies as a second lock; only security definer code writes.
create schema private;
revoke all on schema private from public, anon, authenticated;

create table private.settings (
  key text primary key,
  value text not null
);
alter table private.settings enable row level security;
-- Hashes one verified user may look up per day (Asia/Kolkata). Change with an UPDATE; no deploy.
insert into private.settings (key, value) values ('lookup_phones_daily_hashes', '1000');

create table private.lookup_quota (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  hashes int not null check (hashes >= 0),
  primary key (user_id, day)
);
alter table private.lookup_quota enable row level security;

-- The label the creator gives a member who may not have joined yet. Never copied from profiles.
alter table public.space_members add column name text check (length(name) <= 100);
grant insert (name) on public.space_members to authenticated;

-- SHA-256 hex of an E.164 number ('+919000000001'), as the client computes it before lookup.
create function public.phone_hash(p_phone text) returns text
language sql immutable strict parallel safe set search_path = '' as $$
  select encode(sha256(convert_to(p_phone, 'UTF8')), 'hex')
$$;

-- Executable by everyone: it only hashes its input, and the index below evaluates it on every
-- profiles insert, whoever the inserting role is.
create index profiles_phone_hash_idx on public.profiles (public.phone_hash(phone));

-- Creates a space, the caller as its owner, and the given members, in one transaction.
-- p_members: [{"phone": "+91...", "name": "Rahul"}]; the caller's own phone is skipped.
-- p_idempotency_key becomes the space id, so the client can queue expenses against the space while
-- offline; a replay with the same payload returns it without writing.
create function public.create_space(
  p_name text,
  p_kind public.space_kind,
  p_members jsonb default '[]',
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  my_phone text := public.auth_phone();
  space_id uuid := coalesce(p_idempotency_key, gen_random_uuid());
  fingerprint text;
  m jsonb;
begin
  if me is null then
    raise exception 'create_space: caller has no verified phone' using errcode = '42501';
  end if;
  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'create_space: name is required' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_members, '[]')) <> 'array' then
    raise exception 'create_space: members must be an array' using errcode = '22023';
  end if;
  if exists (select from jsonb_array_elements(coalesce(p_members, '[]')) e
              where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'phone', '') = '') then
    raise exception 'create_space: every member needs a phone' using errcode = '22023';
  end if;
  if (select count(*) <> count(distinct e ->> 'phone') from jsonb_array_elements(coalesce(p_members, '[]')) e) then
    raise exception 'create_space: duplicate member phone' using errcode = '22023';
  end if;

  -- Member order does not change the result, so members are sorted by phone.
  fingerprint := encode(sha256(convert_to(jsonb_build_object(
    'name', btrim(p_name),
    'kind', p_kind,
    'members', (select coalesce(jsonb_agg(jsonb_build_object('phone', e ->> 'phone', 'name', nullif(btrim(e ->> 'name'), ''))
                                          order by e ->> 'phone'), '[]')
                  from jsonb_array_elements(coalesce(p_members, '[]')) e
                 where e ->> 'phone' is distinct from my_phone))::text, 'UTF8')), 'hex');

  -- Someone else's space with this id fails here with 42501: RLS checks before ON CONFLICT.
  insert into public.spaces (id, name, kind, idempotency_hash) values (space_id, btrim(p_name), p_kind, fingerprint)
  on conflict (id) do nothing;
  if not found then
    if exists (select from public.spaces s
                where s.id = space_id and s.created_by = me and s.idempotency_hash = fingerprint) then
      return space_id;
    end if;
    raise exception 'create_space: idempotency key % was already used with a different payload', p_idempotency_key
      using errcode = 'PT409', hint = 'idempotency_conflict';
  end if;

  insert into public.space_members (space_id, phone, user_id, role)
  values (space_id, my_phone, me, 'owner');

  for m in select e from jsonb_array_elements(coalesce(p_members, '[]')) e loop
    continue when m ->> 'phone' = my_phone;
    insert into public.space_members (space_id, phone, name, role)
    values (space_id, (m ->> 'phone')::public.e164, nullif(btrim(m ->> 'name'), ''), 'member');
  end loop;

  return space_id;
end $$;

-- Adds an expense with its payers and splits in one transaction; see docs/api.md for the payload.
-- Replaying an idempotency_key with the same payload returns the original expense id and writes
-- nothing, also when two calls race: the unique (space_id, idempotency_key) index makes the second
-- insert wait for the first and then do nothing. A different payload raises PT409 (see the top).
create function public.add_expense(p jsonb) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  v_space uuid;
  v_key uuid;
  v_amount bigint;
  v_type public.split_type;
  v_id uuid;
  v_existing record;
  fingerprint text;
  n int;
  share bigint;
  taker uuid;
begin
  if jsonb_typeof(p) <> 'object' then
    raise exception 'add_expense: payload must be an object' using errcode = '22023';
  end if;
  v_space := (p ->> 'space_id')::uuid;
  v_key := (p ->> 'idempotency_key')::uuid;
  v_amount := (p ->> 'amount_minor')::bigint;
  v_type := coalesce(p ->> 'split_type', 'equal')::public.split_type;

  if v_space is null or v_key is null then
    raise exception 'add_expense: space_id and idempotency_key are required' using errcode = '22023';
  end if;
  -- Excludes soft-deleted spaces, departed members and unverified callers.
  if me is null or not public.is_space_member(v_space) then
    raise exception 'add_expense: caller is not an active member of space %', v_space using errcode = '42501';
  end if;

  if v_amount is null or v_amount <= 0 then
    raise exception 'add_expense: amount_minor must be a positive integer' using errcode = '22023';
  end if;
  if coalesce(btrim(p ->> 'description'), '') = '' then
    raise exception 'add_expense: description is required' using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'payers') is distinct from 'array' or jsonb_array_length(p -> 'payers') = 0
     or jsonb_typeof(p -> 'splits') is distinct from 'array' or jsonb_array_length(p -> 'splits') = 0 then
    raise exception 'add_expense: payers and splits must be non-empty arrays' using errcode = '22023';
  end if;

  -- The normalised request: what would be stored, with the client's equal-split amounts dropped
  -- (the server recomputes them). Payer order does not matter; split order does (it decides the
  -- remainder), so splits keep theirs.
  fingerprint := encode(sha256(convert_to(jsonb_build_object(
    'space_id', v_space,
    'description', btrim(p ->> 'description'),
    'category', nullif(btrim(p ->> 'category'), ''),
    'amount_minor', v_amount,
    'spent_on', (p ->> 'spent_on')::date,
    'is_settlement', coalesce((p ->> 'is_settlement')::boolean, false),
    'split_type', v_type,
    'payers', (select jsonb_agg(jsonb_build_object('member_id', member_id, 'amount_minor', amount_minor) order by member_id)
                 from jsonb_to_recordset(p -> 'payers') x(member_id uuid, amount_minor bigint)),
    'splits', (select jsonb_agg(jsonb_build_object(
                        'member_id', member_id,
                        'amount_minor', case when v_type <> 'equal' then amount_minor end,
                        'percent_bp', case when v_type = 'percent' then percent_bp end,
                        'shares', case when v_type = 'shares' then shares end) order by ord)
                 from rows from (jsonb_to_recordset(p -> 'splits')
                                 as (member_id uuid, amount_minor bigint, percent_bp int, shares int))
                      with ordinality x(member_id, amount_minor, percent_bp, shares, ord))
  )::text, 'UTF8')), 'hex');

  select id, created_by, idempotency_hash into v_existing
    from public.expenses where space_id = v_space and idempotency_key = v_key;
  if found then
    if v_existing.created_by is distinct from me or v_existing.idempotency_hash is distinct from fingerprint then
      raise exception 'add_expense: idempotency key % was already used with a different payload', v_key
        using errcode = 'PT409', hint = 'idempotency_conflict';
    end if;
    return v_existing.id;
  end if;

  if exists (select from jsonb_to_recordset(p -> 'payers') x(member_id uuid) where member_id is null)
     or exists (select from jsonb_to_recordset(p -> 'splits') x(member_id uuid) where member_id is null)
     or (select count(*) <> count(distinct member_id) from jsonb_to_recordset(p -> 'payers') x(member_id uuid))
     or (select count(*) <> count(distinct member_id) from jsonb_to_recordset(p -> 'splits') x(member_id uuid)) then
    raise exception 'add_expense: every payer and split needs a distinct member_id' using errcode = '22023';
  end if;
  if exists (
    select from (select member_id from jsonb_to_recordset(p -> 'payers') x(member_id uuid)
                 union select member_id from jsonb_to_recordset(p -> 'splits') x(member_id uuid)) x
     where not exists (select from public.space_members m
                        where m.id = x.member_id and m.space_id = v_space and m.left_at is null)
  ) then
    raise exception 'add_expense: payers and splits must be active members of space %', v_space
      using errcode = '22023';
  end if;
  if exists (select from jsonb_to_recordset(p -> 'payers') x(amount_minor bigint)
              where amount_minor is null or amount_minor <= 0)
     or (select sum(amount_minor) from jsonb_to_recordset(p -> 'payers') x(amount_minor bigint)) <> v_amount then
    raise exception 'add_expense: payer amounts must be positive and sum to %', v_amount using errcode = '22023';
  end if;

  -- "The payer" of packages/core: the first split member (in array order) who is a payer, if any.
  select s.member_id into taker
    from rows from (jsonb_to_recordset(p -> 'splits') as (member_id uuid)) with ordinality s(member_id, ord)
   where s.member_id in (select member_id from jsonb_to_recordset(p -> 'payers') x(member_id uuid))
   order by s.ord limit 1;

  if v_type = 'equal' then
    -- Server recomputes, same rule as splitEqual (ADR 0003): everyone gets amount / n; the
    -- remainder goes to the payer, else the first split member.
    n := jsonb_array_length(p -> 'splits');
    share := v_amount / n;
    taker := coalesce(taker, (p -> 'splits' -> 0 ->> 'member_id')::uuid);
  else
    if exists (select from jsonb_to_recordset(p -> 'splits') x(amount_minor bigint)
                where amount_minor is null or amount_minor < 0)
       or (select sum(amount_minor) from jsonb_to_recordset(p -> 'splits') x(amount_minor bigint)) <> v_amount then
      raise exception 'add_expense: split amounts must be non-negative and sum to %', v_amount
        using errcode = '22023';
    end if;
    if v_type = 'percent'
       and (exists (select from jsonb_to_recordset(p -> 'splits') x(percent_bp int) where percent_bp is null)
            or (select sum(percent_bp) from jsonb_to_recordset(p -> 'splits') x(percent_bp int)) <> 10000) then
      raise exception 'add_expense: percent splits need percent_bp summing to 10000' using errcode = '22023';
    end if;
    if v_type = 'shares'
       and exists (select from jsonb_to_recordset(p -> 'splits') x(shares int) where shares is null or shares <= 0) then
      raise exception 'add_expense: shares splits need a positive shares value' using errcode = '22023';
    end if;
    -- percent and shares: the amounts must be exactly what splitPercent / splitShares produce.
    -- Each member gets floor(amount * w / total); the leftover paise go one each to the largest
    -- discarded fractions, ties to the payer first, then split order.
    if v_type in ('percent', 'shares') and exists (
      with s as (
        select x.member_id, x.amount_minor, x.ord,
               case when v_type = 'percent' then x.percent_bp else x.shares end::bigint as w
          from rows from (jsonb_to_recordset(p -> 'splits')
                          as (member_id uuid, amount_minor bigint, percent_bp int, shares int))
               with ordinality x(member_id, amount_minor, percent_bp, shares, ord)
      ), b as (
        -- sum() of bigint is numeric; cast back so the division is integer division.
        select s.*, v_amount * w / (sum(w) over ())::bigint as base, v_amount * w % (sum(w) over ())::bigint as frac
          from s
      ), r as (
        select b.*, v_amount - (sum(base) over ())::bigint as leftover,
               row_number() over (order by frac desc, member_id is distinct from taker, ord) as rn
          from b
      )
      select from r where amount_minor <> base + case when rn <= leftover then 1 else 0 end
    ) then
      raise exception 'add_expense: % split amounts do not match the server''s allocation', v_type
        using errcode = '22023';
    end if;
  end if;

  insert into public.expenses
    (space_id, description, category, amount_minor, spent_on, is_settlement, idempotency_key, idempotency_hash)
  values (v_space, btrim(p ->> 'description'), nullif(btrim(p ->> 'category'), ''), v_amount,
          coalesce((p ->> 'spent_on')::date, current_date), coalesce((p ->> 'is_settlement')::boolean, false),
          v_key, fingerprint)
  on conflict (space_id, idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    -- Lost a race with a concurrent call carrying the same key; it has committed by now.
    select id, created_by, idempotency_hash into v_existing
      from public.expenses where space_id = v_space and idempotency_key = v_key;
    if v_existing.created_by is distinct from me or v_existing.idempotency_hash is distinct from fingerprint then
      raise exception 'add_expense: idempotency key % was already used with a different payload', v_key
        using errcode = 'PT409', hint = 'idempotency_conflict';
    end if;
    return v_existing.id;
  end if;

  insert into public.expense_payers (expense_id, member_id, amount_minor)
  select v_id, member_id, amount_minor from jsonb_to_recordset(p -> 'payers') x(member_id uuid, amount_minor bigint);
  insert into public.expense_splits (expense_id, member_id, split_type, amount_minor, shares, percent_bp)
  select v_id, member_id, v_type,
         case when v_type = 'equal' then share + case when member_id = taker then v_amount % n else 0 end
              else amount_minor end,
         case when v_type = 'shares' then shares end,
         case when v_type = 'percent' then percent_bp end
    from jsonb_to_recordset(p -> 'splits') x(member_id uuid, amount_minor bigint, shares int, percent_bp int);

  return v_id;
end $$;

-- Contact discovery. Takes SHA-256 hex hashes of E.164 numbers (public.phone_hash) and returns only
-- those that belong to a registered, verified user; unknown hashes return nothing. Raw numbers are
-- never sent or returned. At most 500 hashes per call: the client batches its contacts.
-- A phone hash is not a secret (the number space is small enough to enumerate), so every hash sent,
-- matched or not, is charged to a per-user daily quota (private.lookup_quota) before the lookup.
-- Over the quota the call fails with PT429 (HTTP 429) and is not charged.
create function public.lookup_phones(p_hashes text[])
returns table (phone_hash text, user_id uuid, name text)
language plpgsql volatile security definer set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  quota int := (select s.value::int from private.settings s where s.key = 'lookup_phones_daily_hashes');
  today date := (now() at time zone 'Asia/Kolkata')::date;
  n int := coalesce(cardinality(p_hashes), 0);
begin
  if me is null then
    raise exception 'lookup_phones: caller has no verified phone' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_hashes), 0) > 500 then
    raise exception 'lookup_phones: at most 500 hashes per call' using errcode = '54000';
  end if;
  if exists (select from unnest(p_hashes) h where h is null or h !~ '^[0-9a-fA-F]{64}$') then
    raise exception 'lookup_phones: every hash must be 64 hex characters' using errcode = '22023';
  end if;

  -- Charged atomically: the row lock serialises concurrent calls by the same user.
  insert into private.lookup_quota as q (user_id, day, hashes) values (me, today, n)
  on conflict on constraint lookup_quota_pkey do update set hashes = q.hashes + excluded.hashes
  where q.hashes + excluded.hashes <= quota;
  if not found or n > quota then
    raise exception 'lookup_phones: daily quota of % hashes exceeded', quota
      using errcode = 'PT429', hint = 'lookup_quota_exceeded';
  end if;

  return query
  select public.phone_hash(p.phone), p.id, p.name
    from public.profiles p
    join auth.users u on u.id = p.id
   where public.phone_hash(p.phone) = any (select lower(h) from unnest(p_hashes) h)
     and u.phone_confirmed_at is not null
     -- The profile's phone must still be the user's verified auth phone.
     and p.phone = case when u.phone like '+%' then u.phone else '+' || u.phone end;
end $$;

revoke execute on function
  public.create_space(text, public.space_kind, jsonb, uuid), public.add_expense(jsonb),
  public.lookup_phones(text[])
  from public, anon;
grant execute on function
  public.create_space(text, public.space_kind, jsonb, uuid), public.add_expense(jsonb),
  public.lookup_phones(text[])
  to authenticated;
