-- Account deletion (#74): delete_account now deletes the auth user, not only its phone, so the
-- sign-in is gone and the number is free at once. The profile stays as the #9 tombstone, named
-- 'Deleted user', because shared history (RESTRICT FKs) still points at it; other members' rows,
-- balances, activity and dispute reasons are not touched.

-- profiles.id cascaded from auth.users, which would take the tombstone with the auth user (or, with
-- history, refuse the delete). A trigger keeps the cascade for live profiles only.
alter table public.profiles drop constraint profiles_id_fkey;

create function public.cascade_deleted_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.profiles where id = old.id and deleted_at is null;
  return null;
end $$;

revoke execute on function public.cascade_deleted_user() from public, anon, authenticated;

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
end $$;
