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
-- postgres owns the table and could forge a row; the database owner can bypass any control here
-- (drop the trigger, edit the function), so it is outside the threat model.
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

-- The write barrier. Every client write (each mutating RPC, and anything RLS lets through directly)
-- starts by taking a key-share lock on the caller's auth row, which delete_account holds for
-- update. A write that got there first commits before the deletion starts and is ordinary history.
-- One that arrives during or after it waits, finds no auth user and is refused (42501, hint
-- account_deleted), so nothing is written in a deleted account's name: no profile details back on
-- the tombstone, no invite issued or accepted, no queued expense. Only the authenticated role with a
-- user id is a client write; GoTrue, migrations, cron and service_role are not. A writer that
-- already holds a row the deletion needs can deadlock with it; Postgres aborts one of the two, and
-- both are safe to retry.
create function private.guard_live_caller() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null or current_setting('role', true) is distinct from 'authenticated'
     or exists (select from private.account_deletions where user_id = me) then
    return null;
  end if;
  perform from auth.users where id = me for key share;
  if not found then
    raise exception 'this account has been deleted' using errcode = 'insufficient_privilege', hint = 'account_deleted';
  end if;
  return null;
end $$;

revoke execute on function private.guard_live_caller() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array[
    'public.profiles', 'public.friends', 'public.spaces', 'public.space_members', 'public.expenses',
    'public.expense_payers', 'public.expense_splits', 'public.recurring_expenses', 'public.loans',
    'public.loan_repayments', 'private.invite_links', 'private.invite_rate_limits']
  loop
    execute format('create trigger live_caller before insert or update or delete on %s '
                   'for each statement execute function private.guard_live_caller()', t);
  end loop;
end $$;

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
-- The auth row is locked first, for the whole call: that is the write barrier above, so the
-- revocations and the tombstone below cannot be overtaken by a write of the same user.
-- Concurrent sign-in: the same lock. A GoTrue verification that got there earlier
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

  insert into private.account_deletions (user_id) values (me);
  perform public.release_pending_claims(me, null);
  update public.profiles set name = 'Deleted user', upi_id = null, phone = null, deleted_at = now()
   where id = me and deleted_at is null;
  delete from public.friends where user_id = me;
  update public.friends set friend_id = null where friend_id = me;
  -- Links this user issued must not keep admitting people in their name.
  update private.invite_links set revoked_at = now()
   where issuer_id = me and redeemed_at is null and declined_at is null and revoked_at is null;
  delete from private.invite_rate_limits where user_id = me;
  -- Cascades to sessions, refresh tokens, idempotency keys and the lookup quota.
  delete from auth.users where id = me;
  delete from private.account_deletions where user_id = me;
end $$;
