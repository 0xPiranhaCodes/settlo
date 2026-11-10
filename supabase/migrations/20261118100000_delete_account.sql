-- Account deletion (#74): delete_account now deletes the auth user, not only its phone, so the
-- sign-in is gone and the number is free at once. The profile stays as the #9 tombstone, named
-- 'Deleted user', because shared history (RESTRICT FKs) still points at it; other members' rows,
-- balances, activity and dispute reasons are not touched.

-- profiles.id cascaded from auth.users, which would take the tombstone with the auth user (or, with
-- history, refuse the delete). Triggers keep what the foreign key enforced for live profiles: a
-- live profile always has its auth user, and goes with it. The one profile without an auth user
-- is a tombstone, and only delete_account can make one.
alter table public.profiles drop constraint profiles_id_fkey;

-- The right to tombstone a profile, held only while delete_account runs: it adds the row, updates
-- the profile and removes the row in one transaction. Nothing but security definer code can write
-- here (private has no client or service_role privileges), so the marker cannot be set directly.
create table private.account_deletions (user_id uuid primary key);
alter table private.account_deletions enable row level security;
revoke all on table private.account_deletions from public, anon, authenticated;

create function public.check_profile_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.deleted_at is null then
    -- Locked as a foreign key would, so the auth user cannot go before this commits.
    perform from auth.users where id = new.id for key share;
    if not found then
      raise exception 'profile % has no auth user', new.id using errcode = 'foreign_key_violation';
    end if;
  elsif (tg_op = 'INSERT' or old.deleted_at is null)
        and not exists (select from private.account_deletions where user_id = new.id) then
    raise exception 'only delete_account may tombstone a profile' using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

create trigger profiles_user
  before insert or update of id, deleted_at on public.profiles
  for each row execute function public.check_profile_user();

create function public.guard_user_id_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.id is distinct from old.id and exists (select from public.profiles where id = old.id) then
    raise exception 'auth user % has a profile; its id cannot change', old.id
      using errcode = 'foreign_key_violation';
  end if;
  return new;
end $$;

create trigger guard_user_id_change
  before update of id on auth.users
  for each row execute function public.guard_user_id_change();

create function public.cascade_deleted_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.profiles where id = old.id and deleted_at is null;
  return null;
end $$;

revoke execute on function
  public.check_profile_user(), public.guard_user_id_change(), public.cascade_deleted_user()
  from public, anon, authenticated;

create trigger cascade_deleted_user
  after delete on auth.users
  for each row execute function public.cascade_deleted_user();

-- Acts on auth.uid() alone and takes no arguments, so a caller can delete only their own account.
-- Unverified callers may delete too: an account must be removable whatever state its phone is in.
-- Idempotent: every statement is a no-op the second time, so a retry after a lost response (the
-- access token outlives the auth user) returns normally.
-- Concurrent sign-in: the auth row is locked first. A GoTrue verification that got there earlier
-- commits, with its deferred linking, before anything here runs, so the claims it linked are
-- released below; one that arrives later finds no row to update. Signing in again afterwards makes
-- a new user, who is linked only to rows nobody had claimed (link_verified_phone, #9).
create or replace function public.delete_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'delete_account: not signed in' using errcode = 'insufficient_privilege';
  end if;
  perform from auth.users where id = me for update;

  perform public.release_pending_claims(me, null);
  insert into private.account_deletions (user_id) values (me);
  update public.profiles set name = 'Deleted user', upi_id = null, phone = null, deleted_at = now()
   where id = me and deleted_at is null;
  delete from private.account_deletions where user_id = me;
  delete from public.friends where user_id = me;
  update public.friends set friend_id = null where friend_id = me;
  -- Links this user issued must not keep admitting people in their name.
  update private.invite_links set revoked_at = now()
   where issuer_id = me and redeemed_at is null and declined_at is null and revoked_at is null;
  delete from private.invite_rate_limits where user_id = me;
  -- Cascades to sessions, refresh tokens, idempotency keys and the lookup quota.
  delete from auth.users where id = me;
end $$;
