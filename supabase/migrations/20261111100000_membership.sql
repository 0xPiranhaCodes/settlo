-- Space membership follow-ups (#70): set_member_role, re-adding a former member, and retention of
-- private idempotency keys. Same contract as #59: security invoker RPCs, a fixed empty search_path,
-- verified callers only, payload-bound keys, codes 22023 / 42501 / PT409.
-- Clients may update only left_at on space_members, so role changes go through a security definer
-- helper in private that re-checks the caller.

-- Changes a member's role. Lock order matches a leave (the member row, then the space row in
-- guard_member_leave), and the owner checks run after both locks, so a concurrent leave, promotion
-- or demotion is seen and the space is never left without an accepted, active owner.
create function private.write_member_role(p_space_id uuid, p_member_id uuid, p_role public.member_role)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  m public.space_members;
begin
  if not public.is_space_owner(p_space_id) then
    raise exception 'set_member_role: only an owner of space % may change roles', p_space_id using errcode = '42501';
  end if;
  select * into m from public.space_members s
   where s.id = p_member_id and s.space_id = p_space_id and s.left_at is null
     for update;
  if not found then
    raise exception 'set_member_role: % is not an active member of space %', p_member_id, p_space_id
      using errcode = '22023';
  end if;
  perform from public.spaces s where s.id = p_space_id for no key update;
  if not public.is_space_owner(p_space_id) then
    raise exception 'set_member_role: only an owner of space % may change roles', p_space_id using errcode = '42501';
  end if;

  if p_role = 'owner' and m.accepted_at is null then
    raise exception 'set_member_role: member % has not accepted yet', m.id using errcode = '22023', hint = 'not_accepted';
  end if;
  if p_role = 'member' and m.role = 'owner' and not exists (
    select from public.space_members o
     where o.space_id = p_space_id and o.id <> m.id and o.role = 'owner'
       and o.left_at is null and o.accepted_at is not null) then
    raise exception 'member % is the last owner of space % and cannot be demoted', m.id, p_space_id
      using errcode = '22023', hint = 'last_owner';
  end if;
  update public.space_members set role = p_role where id = m.id;
end $$;

-- An owner promotes a member to owner or demotes an owner (themselves included) to member. Setting
-- the current role is a no-op. The key is checked before ownership, so a replay still returns after
-- the caller has handed over and been demoted.
create function public.set_member_role(p_space_id uuid, p_member_id uuid, p_role public.member_role,
                                       p_idempotency_key uuid) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
begin
  if me is null then
    raise exception 'set_member_role: caller has no verified phone' using errcode = '42501';
  end if;
  if p_space_id is null or p_member_id is null or p_role is null or p_idempotency_key is null then
    raise exception 'set_member_role: space id, member id, role and idempotency key are required'
      using errcode = '22023';
  end if;
  if not private.claim_idempotency_key('set_member_role', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object('space_id', p_space_id, 'member_id', p_member_id, 'role', p_role)::text, 'UTF8')), 'hex')) then
    return;
  end if;
  perform private.write_member_role(p_space_id, p_member_id, p_role);
end $$;

-- Re-adding a former member creates a fresh membership: a new row and id, pending until accepted.
-- The departed row stays departed with its history, so an old allocation can never count for the
-- new membership. One active row per phone and per user; departed rows may repeat.
alter table public.space_members
  drop constraint space_members_space_id_phone_key,
  drop constraint space_members_space_id_user_id_key;
create unique index space_members_active_phone_key on public.space_members (space_id, phone) where left_at is null;
create unique index space_members_active_user_key on public.space_members (space_id, user_id) where left_at is null;

-- A departed membership's balance is frozen for good: no edit, delete or restore may change an
-- expense whose payers or splits include one. As #59, with the hint renamed departed_member.
create or replace function private.store_allocations(p_expense_id uuid, p jsonb, p_caller text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_space uuid := (select e.space_id from public.expenses e where e.id = p_expense_id and e.deleted_at is null);
begin
  if v_space is null or not public.can_edit_expense(p_expense_id) then
    raise exception '%: only the creator or a space owner may change expense %', p_caller, p_expense_id
      using errcode = '42501';
  end if;
  perform from public.space_members m
   where m.id in (select x.member_id from public.expense_payers x where x.expense_id = p_expense_id
                  union select x.member_id from public.expense_splits x where x.expense_id = p_expense_id
                  union select (e ->> 'member_id')::uuid from jsonb_array_elements(p -> 'payers') e
                  union select (e ->> 'member_id')::uuid from jsonb_array_elements(p -> 'splits') e)
   order by m.id for share;
  if exists (select from public.space_members m
              where m.left_at is not null
                and m.id in (select x.member_id from public.expense_payers x where x.expense_id = p_expense_id
                             union select x.member_id from public.expense_splits x where x.expense_id = p_expense_id)) then
    raise exception '%: expense % involves a member who has left', p_caller, p_expense_id
      using errcode = '22023', hint = 'departed_member';
  end if;

  delete from public.expense_payers where expense_id = p_expense_id;
  delete from public.expense_splits where expense_id = p_expense_id;
  with a as (select * from public.resolve_allocations(p, v_space, p_caller)),
  payers as (
    insert into public.expense_payers (expense_id, member_id, amount_minor)
    select p_expense_id, a.member_id, a.amount_minor from a where a.kind = 'payer'
  )
  insert into public.expense_splits (expense_id, member_id, split_type, amount_minor, shares, percent_bp)
  select p_expense_id, a.member_id, coalesce(p ->> 'split_type', 'equal')::public.split_type,
         a.amount_minor, a.shares, a.percent_bp
    from a where a.kind = 'split';
end $$;

create or replace function public.guard_expense_members() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform from public.space_members m
   where m.id in (select x.member_id from public.expense_payers x where x.expense_id = new.id
                  union select x.member_id from public.expense_splits x where x.expense_id = new.id)
   order by m.id for share;
  if exists (select from public.space_members m
              where m.left_at is not null
                and m.id in (select x.member_id from public.expense_payers x where x.expense_id = new.id
                             union select x.member_id from public.expense_splits x where x.expense_id = new.id)) then
    raise exception 'expense % involves a member who has left', new.id using errcode = '22023', hint = 'departed_member';
  end if;
  return new;
end $$;

-- add_space_members from #59; a former member's phone now gets a new row instead of failing with former_member.
create or replace function public.add_space_members(p_space_id uuid, p_members jsonb, p_idempotency_key uuid) returns void
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
  if not private.claim_idempotency_key('add_space_members', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object(
         'space_id', p_space_id,
         'members', (select jsonb_agg(jsonb_build_object('phone', e ->> 'phone', 'name', nullif(btrim(e ->> 'name'), ''))
                                      order by e ->> 'phone')
                       from jsonb_array_elements(p_members) e))::text, 'UTF8')), 'hex')) then
    return;
  end if;

  if exists (select from public.space_members m join jsonb_array_elements(p_members) e on m.phone = e ->> 'phone'
              where m.space_id = p_space_id and m.left_at is null) then
    raise exception 'add_space_members: a phone is already a member of space %', p_space_id
      using errcode = '22023', hint = 'already_member';
  end if;
  insert into public.space_members (space_id, phone, name, role)
  select p_space_id, (e ->> 'phone')::public.e164, nullif(btrim(e ->> 'name'), ''), 'member'
    from jsonb_array_elements(p_members) e;
end $$;

-- A departed row stays departed: a direct left_at update back to null would revive its allocations
-- (and skip the new claim). Rejoining is a new row from add_space_members.
create function public.guard_member_rejoin() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'member % left space %; re-add them with add_space_members', new.id, new.space_id
    using errcode = '42501';
end $$;

create trigger space_members_rejoin
  before update of left_at on public.space_members
  for each row when (old.left_at is not null and new.left_at is null and current_user = 'authenticated')
  execute function public.guard_member_rejoin();

-- Retention (ADR 0004): keys in private.idempotency_keys are kept for 30 days from first use, then
-- purged daily. A replay inside the window returns without writing; after it, the call runs as new.
-- add_expense and create_space keep their keys on the rows they create, which are never purged.
create index idempotency_keys_created_at_idx on private.idempotency_keys (created_at);

create function private.purge_idempotency_keys() returns integer
language sql security definer set search_path = '' as $$
  with gone as (delete from private.idempotency_keys where created_at < now() - interval '30 days' returning 1)
  select count(*)::int from gone
$$;

create extension if not exists pg_cron;
select cron.schedule('purge-idempotency-keys', '17 3 * * *', 'select private.purge_idempotency_keys()');

revoke execute on function public.guard_member_rejoin() from public, anon, authenticated;
revoke execute on function private.purge_idempotency_keys() from public, anon, authenticated;
revoke execute on function
  private.write_member_role(uuid, uuid, public.member_role), public.set_member_role(uuid, uuid, public.member_role, uuid)
  from public, anon;
grant execute on function
  private.write_member_role(uuid, uuid, public.member_role), public.set_member_role(uuid, uuid, public.member_role, uuid)
  to authenticated;
