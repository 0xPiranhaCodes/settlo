-- Space membership follow-ups (#70): set_member_role, re-adding a former member, and retention of
-- private idempotency keys. Same contract as #59: security invoker RPCs, a fixed empty search_path,
-- verified callers only, payload-bound keys, codes 22023 / 42501 / PT409.
-- Clients may update only left_at on space_members, so role changes and rejoining go through
-- security definer helpers in private that re-check the caller.

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

-- Re-adding a former member reactivates their row: history (created_at, past payers and splits)
-- stays on it, and it becomes a pending member again, to be accepted as a new claim. It keeps its
-- user_id, so an accepted former member gets the claim back rather than whoever now holds the number;
-- a row never linked (or rejected) is matched by phone like a new one.
-- A departed balance is frozen (#59), and normally zero. A non-zero one (a rejected claim departs
-- whatever its balance) is refused, so a rejoining member never inherits it.
create function private.rejoin_members(p_space_id uuid, p_members jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_accepted_member(p_space_id) then
    raise exception 'add_space_members: caller is not an active member of space %', p_space_id
      using errcode = '42501';
  end if;
  perform from public.space_members m join jsonb_array_elements(p_members) e on m.phone = e ->> 'phone'
   where m.space_id = p_space_id and m.left_at is not null
   order by m.id for update of m;
  if exists (select from public.space_members m join jsonb_array_elements(p_members) e on m.phone = e ->> 'phone'
               join public.space_member_balances b on b.member_id = m.id
              where m.space_id = p_space_id and m.left_at is not null and b.balance_minor <> 0) then
    raise exception 'add_space_members: a former member of space % left with a balance and cannot rejoin', p_space_id
      using errcode = '22023', hint = 'balance_not_zero';
  end if;
  update public.space_members m
     set left_at = null, rejected_at = null, accepted_at = null, role = 'member',
         name = coalesce(nullif(btrim(e ->> 'name'), ''), m.name)
    from jsonb_array_elements(p_members) e
   where m.space_id = p_space_id and m.phone = e ->> 'phone' and m.left_at is not null;
end $$;

-- add_space_members from #59; former members now rejoin instead of failing with former_member.
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
  perform private.rejoin_members(p_space_id, p_members);
  insert into public.space_members (space_id, phone, name, role)
  select p_space_id, (e ->> 'phone')::public.e164, nullif(btrim(e ->> 'name'), ''), 'member'
    from jsonb_array_elements(p_members) e
   where not exists (select from public.space_members m where m.space_id = p_space_id and m.phone = e ->> 'phone');
end $$;

-- Rejoining goes through add_space_members only: a direct left_at update could otherwise revive an
-- accepted row (skipping the new claim) or a departed balance.
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
  private.write_member_role(uuid, uuid, public.member_role), private.rejoin_members(uuid, jsonb),
  public.set_member_role(uuid, uuid, public.member_role, uuid)
  from public, anon;
grant execute on function
  private.write_member_role(uuid, uuid, public.member_role), private.rejoin_members(uuid, jsonb),
  public.set_member_role(uuid, uuid, public.member_role, uuid)
  to authenticated;
