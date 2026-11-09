-- Space and expense mutations (#59): update_expense, delete_expense, add_space_members,
-- leave_space, update_profile. Same contract as add_expense (#10, ADR 0004): security invoker so
-- RLS stays the gate, a fixed empty search_path, verified callers only, and payload-bound
-- idempotency (same key and payload returns without writing; anything else is PT409).
--
-- Edits and deletes are allowed to the expense's creator or a space owner. The policies are
-- tightened to match, so a direct table write cannot do what the RPC refuses.

-- Keys for mutations that do not create a row to hold them (add_expense and create_space keep
-- theirs on the row they create). Server-only, like private.lookup_quota.
create table private.idempotency_keys (
  key uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  fingerprint text not null,
  created_at timestamptz not null default now()
);
alter table private.idempotency_keys enable row level security;

-- Records p_key for the caller. True: first use, go ahead. False: a replay of the same mutation,
-- return without writing. Anything else (another kind, payload or user) raises PT409. A concurrent
-- call with the same key waits on the primary key until the first commits or rolls back, and the
-- claim rolls back with the mutation if it fails. Security definer: it writes private state.
-- Callable directly, but it can only burn the caller's own keys.
create function public.claim_idempotency_key(p_kind text, p_key uuid, p_fingerprint text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  k private.idempotency_keys;
begin
  if me is null then
    raise exception 'claim_idempotency_key: caller has no verified phone' using errcode = '42501';
  end if;
  insert into private.idempotency_keys (key, user_id, kind, fingerprint) values (p_key, me, p_kind, p_fingerprint)
  on conflict (key) do nothing;
  if found then
    return true;
  end if;
  select * into k from private.idempotency_keys where key = p_key;
  if k.user_id = me and k.kind = p_kind and k.fingerprint = p_fingerprint then
    return false;
  end if;
  raise exception '%: idempotency key % was already used with a different payload', p_kind, p_key
    using errcode = 'PT409', hint = 'idempotency_conflict';
end $$;

-- add_expense's checks, split in two so update_expense shares them.
-- normalise_expense: the basic field checks, then the normalised request that is fingerprinted.
create function public.normalise_expense(p jsonb, p_space uuid, p_caller text) returns jsonb
language plpgsql stable security invoker set search_path = '' as $$
declare
  v_amount bigint := (p ->> 'amount_minor')::bigint;
  v_type public.split_type := coalesce(p ->> 'split_type', 'equal')::public.split_type;
begin
  if v_amount is null or v_amount <= 0 then
    raise exception '%: amount_minor must be a positive integer', p_caller using errcode = '22023';
  end if;
  if coalesce(btrim(p ->> 'description'), '') = '' then
    raise exception '%: description is required', p_caller using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'payers') is distinct from 'array' or jsonb_array_length(p -> 'payers') = 0
     or jsonb_typeof(p -> 'splits') is distinct from 'array' or jsonb_array_length(p -> 'splits') = 0 then
    raise exception '%: payers and splits must be non-empty arrays', p_caller using errcode = '22023';
  end if;

  -- What would be stored, with the client's equal-split amounts dropped (the server recomputes
  -- them). Payer order does not matter; split order does (it decides the remainder).
  return jsonb_build_object(
    'space_id', p_space,
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
                      with ordinality x(member_id, amount_minor, percent_bp, shares, ord)));
end $$;

-- resolve_allocations: validates payers and splits against the space and returns the rows to
-- store, kind 'payer' or 'split', with equal splits recomputed (ADR 0003, see docs/api.md).
create function public.resolve_allocations(p jsonb, p_space uuid, p_caller text)
returns table (kind text, member_id uuid, amount_minor bigint, shares int, percent_bp int)
language plpgsql stable security invoker set search_path = '' as $$
#variable_conflict use_column
declare
  v_amount bigint := (p ->> 'amount_minor')::bigint;
  v_type public.split_type := coalesce(p ->> 'split_type', 'equal')::public.split_type;
  n int;
  share bigint;
  taker uuid;
begin
  if exists (select from jsonb_to_recordset(p -> 'payers') x(member_id uuid) where member_id is null)
     or exists (select from jsonb_to_recordset(p -> 'splits') x(member_id uuid) where member_id is null)
     or (select count(*) <> count(distinct member_id) from jsonb_to_recordset(p -> 'payers') x(member_id uuid))
     or (select count(*) <> count(distinct member_id) from jsonb_to_recordset(p -> 'splits') x(member_id uuid)) then
    raise exception '%: every payer and split needs a distinct member_id', p_caller using errcode = '22023';
  end if;
  if exists (
    select from (select member_id from jsonb_to_recordset(p -> 'payers') x(member_id uuid)
                 union select member_id from jsonb_to_recordset(p -> 'splits') x(member_id uuid)) x
     where not exists (select from public.space_members m
                        where m.id = x.member_id and m.space_id = p_space and m.left_at is null)
  ) then
    raise exception '%: payers and splits must be active members of space %', p_caller, p_space
      using errcode = '22023';
  end if;
  if exists (select from jsonb_to_recordset(p -> 'payers') x(amount_minor bigint)
              where amount_minor is null or amount_minor <= 0)
     or (select sum(amount_minor) from jsonb_to_recordset(p -> 'payers') x(amount_minor bigint)) <> v_amount then
    raise exception '%: payer amounts must be positive and sum to %', p_caller, v_amount using errcode = '22023';
  end if;

  -- "The payer" of packages/core: the first split member (in array order) who is a payer, if any.
  select s.member_id into taker
    from rows from (jsonb_to_recordset(p -> 'splits') as (member_id uuid)) with ordinality s(member_id, ord)
   where s.member_id in (select member_id from jsonb_to_recordset(p -> 'payers') x(member_id uuid))
   order by s.ord limit 1;

  if v_type = 'equal' then
    -- Everyone gets amount / n; the remainder goes to the payer, else the first split member.
    n := jsonb_array_length(p -> 'splits');
    share := v_amount / n;
    taker := coalesce(taker, (p -> 'splits' -> 0 ->> 'member_id')::uuid);
  else
    if exists (select from jsonb_to_recordset(p -> 'splits') x(amount_minor bigint)
                where amount_minor is null or amount_minor < 0)
       or (select sum(amount_minor) from jsonb_to_recordset(p -> 'splits') x(amount_minor bigint)) <> v_amount then
      raise exception '%: split amounts must be non-negative and sum to %', p_caller, v_amount
        using errcode = '22023';
    end if;
    if v_type = 'percent'
       and (exists (select from jsonb_to_recordset(p -> 'splits') x(percent_bp int) where percent_bp is null)
            or (select sum(percent_bp) from jsonb_to_recordset(p -> 'splits') x(percent_bp int)) <> 10000) then
      raise exception '%: percent splits need percent_bp summing to 10000', p_caller using errcode = '22023';
    end if;
    if v_type = 'shares'
       and exists (select from jsonb_to_recordset(p -> 'splits') x(shares int) where shares is null or shares <= 0) then
      raise exception '%: shares splits need a positive shares value', p_caller using errcode = '22023';
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
      raise exception '%: % split amounts do not match the server''s allocation', p_caller, v_type
        using errcode = '22023';
    end if;
  end if;

  return query
  select 'payer', x.member_id, x.amount_minor, null::int, null::int
    from jsonb_to_recordset(p -> 'payers') x(member_id uuid, amount_minor bigint)
  union all
  select 'split', x.member_id,
         case when v_type = 'equal' then share + case when x.member_id = taker then v_amount % n else 0 end
              else x.amount_minor end,
         case when v_type = 'shares' then x.shares end,
         case when v_type = 'percent' then x.percent_bp end
    from jsonb_to_recordset(p -> 'splits') x(member_id uuid, amount_minor bigint, shares int, percent_bp int);
end $$;

-- add_expense from #10, unchanged in behaviour, on the shared helpers.
create or replace function public.add_expense(p jsonb) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  v_space uuid;
  v_key uuid;
  v_id uuid;
  v_existing record;
  fingerprint text;
begin
  if jsonb_typeof(p) <> 'object' then
    raise exception 'add_expense: payload must be an object' using errcode = '22023';
  end if;
  v_space := (p ->> 'space_id')::uuid;
  v_key := (p ->> 'idempotency_key')::uuid;

  if v_space is null or v_key is null then
    raise exception 'add_expense: space_id and idempotency_key are required' using errcode = '22023';
  end if;
  -- Excludes soft-deleted spaces, departed members and unverified callers.
  if me is null or not public.is_space_member(v_space) then
    raise exception 'add_expense: caller is not an active member of space %', v_space using errcode = '42501';
  end if;

  fingerprint := encode(sha256(convert_to(public.normalise_expense(p, v_space, 'add_expense')::text, 'UTF8')), 'hex');

  select id, created_by, idempotency_hash into v_existing
    from public.expenses where space_id = v_space and idempotency_key = v_key;
  if found then
    if v_existing.created_by is distinct from me or v_existing.idempotency_hash is distinct from fingerprint then
      raise exception 'add_expense: idempotency key % was already used with a different payload', v_key
        using errcode = 'PT409', hint = 'idempotency_conflict';
    end if;
    return v_existing.id;
  end if;

  insert into public.expenses
    (space_id, description, category, amount_minor, spent_on, is_settlement, idempotency_key, idempotency_hash)
  values (v_space, btrim(p ->> 'description'), nullif(btrim(p ->> 'category'), ''), (p ->> 'amount_minor')::bigint,
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

  perform public.store_allocations(v_id, p, v_space, 'add_expense');
  return v_id;
end $$;

-- Writes the resolved payers and splits of an expense that has none.
create function public.store_allocations(p_expense_id uuid, p jsonb, p_space uuid, p_caller text) returns void
language sql security invoker set search_path = '' as $$
  with a as (select * from public.resolve_allocations(p, p_space, p_caller)),
  payers as (
    insert into public.expense_payers (expense_id, member_id, amount_minor)
    select p_expense_id, a.member_id, a.amount_minor from a where a.kind = 'payer'
  )
  insert into public.expense_splits (expense_id, member_id, split_type, amount_minor, shares, percent_bp)
  select p_expense_id, a.member_id, coalesce(p ->> 'split_type', 'equal')::public.split_type,
         a.amount_minor, a.shares, a.percent_bp
    from a where a.kind = 'split';
$$;

-- Whether the caller may edit or delete the expense: an accepted member of its live space who
-- created it or owns the space.
create function public.can_edit_expense(p_expense_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select from public.expenses e
     where e.id = p_expense_id and public.is_accepted_member(e.space_id)
       and (e.created_by = public.verified_uid() or public.is_space_owner(e.space_id)))
$$;

drop policy expenses_update on public.expenses;
create policy expenses_update on public.expenses for update to authenticated
  using (public.can_edit_expense(id)) with check (public.can_edit_expense(id));

drop policy expense_payers_insert on public.expense_payers;
create policy expense_payers_insert on public.expense_payers for insert to authenticated
  with check (public.can_allocate(expense_id, member_id) and public.can_edit_expense(expense_id));
drop policy expense_payers_update on public.expense_payers;
create policy expense_payers_update on public.expense_payers for update to authenticated
  using (public.can_edit_expense(expense_id))
  with check (public.can_allocate(expense_id, member_id) and public.can_edit_expense(expense_id));
drop policy expense_payers_delete on public.expense_payers;
create policy expense_payers_delete on public.expense_payers for delete to authenticated
  using (public.can_edit_expense(expense_id));

drop policy expense_splits_insert on public.expense_splits;
create policy expense_splits_insert on public.expense_splits for insert to authenticated
  with check (public.can_allocate(expense_id, member_id) and public.can_edit_expense(expense_id));
drop policy expense_splits_update on public.expense_splits;
create policy expense_splits_update on public.expense_splits for update to authenticated
  using (public.can_edit_expense(expense_id))
  with check (public.can_allocate(expense_id, member_id) and public.can_edit_expense(expense_id));
drop policy expense_splits_delete on public.expense_splits;
create policy expense_splits_delete on public.expense_splits for delete to authenticated
  using (public.can_edit_expense(expense_id));

-- History: an edit or delete logs the expense's payers and splits in `before`, so the activity row
-- holds the full prior state. update_expense changes the row before its allocations, so this sees
-- the old ones; the new ones are the current rows (and the next edit's `before`).
create or replace function public.log_expense_activity() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  act text;
begin
  if tg_op = 'INSERT' then
    act := 'created';
  elsif old.deleted_at is null and new.deleted_at is not null then
    act := 'deleted';
  elsif old.deleted_at is not null and new.deleted_at is null then
    act := 'restored';
  else
    act := 'edited';
  end if;

  insert into public.activity (space_id, expense_id, action, before, after)
  values (
    new.space_id,
    new.id,
    act,
    case when tg_op = 'UPDATE' then to_jsonb(old) || jsonb_build_object(
      'payers', (select jsonb_agg(jsonb_build_object('member_id', member_id, 'amount_minor', amount_minor)
                                  order by member_id)
                   from public.expense_payers where expense_id = old.id),
      'splits', (select jsonb_agg(jsonb_build_object('member_id', member_id, 'split_type', split_type,
                                                     'amount_minor', amount_minor, 'shares', shares,
                                                     'percent_bp', percent_bp) order by member_id)
                   from public.expense_splits where expense_id = old.id)) end,
    to_jsonb(new)
  );
  return null;
end $$;

-- Replaces an expense's fields, payers and splits. p is add_expense's payload plus expense_id;
-- space_id comes from the expense. Omitting spent_on keeps the current date.
create function public.update_expense(p jsonb) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  v_id uuid;
  v_key uuid;
  e public.expenses;
begin
  if jsonb_typeof(p) <> 'object' then
    raise exception 'update_expense: payload must be an object' using errcode = '22023';
  end if;
  v_id := (p ->> 'expense_id')::uuid;
  v_key := (p ->> 'idempotency_key')::uuid;
  if v_id is null or v_key is null then
    raise exception 'update_expense: expense_id and idempotency_key are required' using errcode = '22023';
  end if;
  select * into e from public.expenses where id = v_id;
  if me is null or not found or not public.can_edit_expense(v_id) then
    raise exception 'update_expense: only the creator or a space owner may edit expense %', v_id
      using errcode = '42501';
  end if;

  if not public.claim_idempotency_key('update_expense', v_key, encode(sha256(convert_to(
       (public.normalise_expense(p, e.space_id, 'update_expense') || jsonb_build_object('expense_id', v_id))::text,
       'UTF8')), 'hex')) then
    return v_id;
  end if;
  if e.deleted_at is not null then
    raise exception 'update_expense: expense % is deleted', v_id using errcode = '22023';
  end if;

  update public.expenses
     set description = btrim(p ->> 'description'), category = nullif(btrim(p ->> 'category'), ''),
         amount_minor = (p ->> 'amount_minor')::bigint, spent_on = coalesce((p ->> 'spent_on')::date, e.spent_on),
         is_settlement = coalesce((p ->> 'is_settlement')::boolean, false)
   where id = v_id;
  delete from public.expense_payers where expense_id = v_id;
  delete from public.expense_splits where expense_id = v_id;
  perform public.store_allocations(v_id, p, e.space_id, 'update_expense');
  return v_id;
end $$;

-- Soft-deletes an expense; it stops counting and is frozen (#6).
create function public.delete_expense(p_expense_id uuid, p_idempotency_key uuid) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  e public.expenses;
begin
  if p_expense_id is null or p_idempotency_key is null then
    raise exception 'delete_expense: expense id and idempotency key are required' using errcode = '22023';
  end if;
  select * into e from public.expenses where id = p_expense_id;
  if me is null or not found or not public.can_edit_expense(p_expense_id) then
    raise exception 'delete_expense: only the creator or a space owner may delete expense %', p_expense_id
      using errcode = '42501';
  end if;
  if not public.claim_idempotency_key('delete_expense', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object('expense_id', p_expense_id)::text, 'UTF8')), 'hex')) then
    return;
  end if;
  if e.deleted_at is not null then
    raise exception 'delete_expense: expense % is already deleted', p_expense_id using errcode = '22023';
  end if;
  update public.expenses set deleted_at = now() where id = p_expense_id;
end $$;

-- Adds members by phone, as create_space does. p_members: [{"phone": "+91...", "name": "Rahul"}].
create function public.add_space_members(p_space_id uuid, p_members jsonb, p_idempotency_key uuid) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
begin
  if p_space_id is null or p_idempotency_key is null then
    raise exception 'add_space_members: space id and idempotency key are required' using errcode = '22023';
  end if;
  if me is null or not public.is_accepted_member(p_space_id) then
    raise exception 'add_space_members: caller is not an active member of space %', p_space_id
      using errcode = '42501';
  end if;
  if jsonb_typeof(p_members) is distinct from 'array' or jsonb_array_length(p_members) = 0 then
    raise exception 'add_space_members: members must be a non-empty array' using errcode = '22023';
  end if;
  if exists (select from jsonb_array_elements(p_members) e
              where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'phone', '') = '') then
    raise exception 'add_space_members: every member needs a phone' using errcode = '22023';
  end if;
  if (select count(*) <> count(distinct e ->> 'phone') from jsonb_array_elements(p_members) e) then
    raise exception 'add_space_members: duplicate member phone' using errcode = '22023';
  end if;

  -- Member order does not change the result, so members are sorted by phone.
  if not public.claim_idempotency_key('add_space_members', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object(
         'space_id', p_space_id,
         'members', (select jsonb_agg(jsonb_build_object('phone', e ->> 'phone', 'name', nullif(btrim(e ->> 'name'), ''))
                                      order by e ->> 'phone')
                       from jsonb_array_elements(p_members) e))::text, 'UTF8')), 'hex')) then
    return;
  end if;

  -- Includes departed members: re-adding one is not supported yet (unique space_id, phone).
  if exists (select from public.space_members m join jsonb_array_elements(p_members) e on m.phone = e ->> 'phone'
              where m.space_id = p_space_id) then
    raise exception 'add_space_members: a phone is already a member of space %', p_space_id using errcode = '22023';
  end if;
  insert into public.space_members (space_id, phone, name, role)
  select p_space_id, (e ->> 'phone')::public.e164, nullif(btrim(e ->> 'name'), ''), 'member'
    from jsonb_array_elements(p_members) e;
end $$;

-- A member may leave, and an owner may remove anyone, only at a zero balance. Enforced on the table
-- so a direct update of left_at is held to it too. Like RLS it binds clients (authenticated), not
-- server code: rejecting a claim ("this isn't me") departs whatever the balance.
create function public.guard_member_leave() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  bal bigint := (select b.balance_minor from public.space_member_balances b where b.member_id = new.id);
begin
  if bal <> 0 then
    raise exception 'member % has a balance of % and cannot leave until it is settled', new.id, bal
      using errcode = '22023', hint = 'balance_not_zero';
  end if;
  return new;
end $$;

create trigger space_members_leave_balance
  before update of left_at on public.space_members
  for each row when (old.left_at is null and new.left_at is not null and current_user = 'authenticated')
  execute function public.guard_member_leave();

-- Leaves the space, or with p_member_id removes that member (owners only). The key is checked
-- before membership so a replay still returns after the caller has left.
create function public.leave_space(p_space_id uuid, p_idempotency_key uuid, p_member_id uuid default null) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  m public.space_members;
begin
  if me is null then
    raise exception 'leave_space: caller has no verified phone' using errcode = '42501';
  end if;
  if p_space_id is null or p_idempotency_key is null then
    raise exception 'leave_space: space id and idempotency key are required' using errcode = '22023';
  end if;
  if not public.claim_idempotency_key('leave_space', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object('space_id', p_space_id, 'member_id', p_member_id)::text, 'UTF8')), 'hex')) then
    return;
  end if;
  if not public.is_accepted_member(p_space_id) then
    raise exception 'leave_space: caller is not an active member of space %', p_space_id using errcode = '42501';
  end if;

  select * into m from public.space_members s
   where s.space_id = p_space_id and s.left_at is null
     and (s.id = p_member_id or (p_member_id is null and public.is_me(s.user_id, s.phone)));
  if not found then
    raise exception 'leave_space: % is not an active member of space %', p_member_id, p_space_id
      using errcode = '22023';
  end if;
  if not (public.is_me(m.user_id, m.phone) or public.is_space_owner(p_space_id)) then
    raise exception 'leave_space: only an owner may remove another member' using errcode = '42501';
  end if;
  update public.space_members set left_at = now() where id = m.id;
end $$;

-- UPI VPA: handle@psp. Also checked on profiles, so a direct write cannot store a bad one.
-- Executable by everyone: it only tests its input, and the check runs as whoever writes profiles.
create function public.is_vpa(p_upi_id text) returns boolean
language sql immutable strict parallel safe set search_path = '' as $$
  select p_upi_id ~ '^[A-Za-z0-9._-]{1,255}@[A-Za-z]{2,64}$'
$$;
alter table public.profiles add constraint profiles_upi_id_vpa check (public.is_vpa(upi_id));

-- Sets the caller's name and UPI id. A null or blank p_upi_id clears it. Naturally idempotent:
-- a replay writes the same values.
create function public.update_profile(p_name text, p_upi_id text) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  upi text := nullif(btrim(p_upi_id), '');
begin
  if me is null then
    raise exception 'update_profile: caller has no verified phone' using errcode = '42501';
  end if;
  if coalesce(btrim(p_name), '') = '' or length(btrim(p_name)) > 100 then
    raise exception 'update_profile: name is required, at most 100 characters' using errcode = '22023';
  end if;
  if not public.is_vpa(upi) then
    raise exception 'update_profile: % is not a valid UPI id', upi using errcode = '22023', hint = 'invalid_vpa';
  end if;
  update public.profiles set name = btrim(p_name), upi_id = upi where id = me;
  if not found then
    raise exception 'update_profile: caller has no profile' using errcode = '42501';
  end if;
end $$;

revoke execute on function public.guard_member_leave() from public, anon, authenticated;
revoke execute on function
  public.claim_idempotency_key(text, uuid, text), public.normalise_expense(jsonb, uuid, text),
  public.resolve_allocations(jsonb, uuid, text), public.store_allocations(uuid, jsonb, uuid, text),
  public.can_edit_expense(uuid),
  public.update_expense(jsonb), public.delete_expense(uuid, uuid), public.add_space_members(uuid, jsonb, uuid),
  public.leave_space(uuid, uuid, uuid), public.update_profile(text, text)
  from public, anon;
grant execute on function
  public.claim_idempotency_key(text, uuid, text), public.normalise_expense(jsonb, uuid, text),
  public.resolve_allocations(jsonb, uuid, text), public.store_allocations(uuid, jsonb, uuid, text),
  public.can_edit_expense(uuid),
  public.update_expense(jsonb), public.delete_expense(uuid, uuid), public.add_space_members(uuid, jsonb, uuid),
  public.leave_space(uuid, uuid, uuid), public.update_profile(text, text)
  to authenticated;
