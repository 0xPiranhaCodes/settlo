-- Phone linking (#9): when a number is verified, link what was recorded against it, as claims.
-- Identity: nothing about a number is revealed before it is verified. Verifying creates or updates
-- the profile and links user_id on space_members and lender_id / borrower_id on loans recorded
-- against the E.164 phone. A linked row is a claim until its holder accepts it (accepted_at), so the
-- app keeps balances blank until then; accept_claim / reject_claim are the only way to settle one.
-- 'This isn't me' unlinks the number from that membership or loan side for good and tells the
-- creator through activity. Account deletion anonymises the profile; history FKs are RESTRICT.

-- Review state. A row linked by its own holder (self-link, the creator's side) is accepted at insert.
alter table public.space_members
  add column accepted_at timestamptz,
  add column rejected_at timestamptz,
  add check (accepted_at is null or rejected_at is null),
  add check (rejected_at is null or (user_id is null and left_at is not null));

alter table public.loans
  add column lender_accepted_at timestamptz,
  add column borrower_accepted_at timestamptz,
  add column lender_rejected_at timestamptz,
  add column borrower_rejected_at timestamptz,
  add check (lender_accepted_at is null or lender_rejected_at is null),
  add check (borrower_accepted_at is null or borrower_rejected_at is null),
  add check (lender_rejected_at is null or lender_id is null),
  add check (borrower_rejected_at is null or borrower_id is null);

update public.space_members set accepted_at = created_at where user_id is not null;
update public.loans set lender_accepted_at = created_at where lender_id is not null;
update public.loans set borrower_accepted_at = created_at where borrower_id is not null;

alter table public.activity
  drop constraint activity_action_check,
  add constraint activity_action_check
    check (action in ('created', 'edited', 'deleted', 'restored', 'recorded', 'confirmed', 'disputed', 'rejected'));

-- Clients cannot write the review columns (no column grants); this stamps the creator's own side.
create function public.stamp_own_acceptance() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'space_members' then
    new.rejected_at := null;
    new.accepted_at := case when new.user_id is not null then coalesce(new.accepted_at, now()) end;
  else
    new.lender_rejected_at := null;
    new.borrower_rejected_at := null;
    new.lender_accepted_at := case
      when new.lender_id is not null
        or exists (select from public.profiles where id = new.created_by and phone = new.lender_phone)
      then coalesce(new.lender_accepted_at, now()) end;
    new.borrower_accepted_at := case
      when new.borrower_id is not null
        or exists (select from public.profiles where id = new.created_by and phone = new.borrower_phone)
      then coalesce(new.borrower_accepted_at, now()) end;
  end if;
  return new;
end $$;

revoke execute on function public.stamp_own_acceptance() from public, anon, authenticated;

create trigger space_members_acceptance
  before insert on public.space_members
  for each row execute function public.stamp_own_acceptance();
create trigger loans_acceptance
  before insert on public.loans
  for each row execute function public.stamp_own_acceptance();

-- Verification: create or update the profile, then link every live, unrejected row recorded against
-- the number. Deferred to commit, so it sees the auth row as GoTrue finally leaves it and runs after
-- anything else in that transaction; it re-reads the row because NEW may be stale by then.
create function public.link_verified_phone() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  u auth.users;
  e164 text;
begin
  select * into u from auth.users where id = new.id;
  if not found or u.phone_confirmed_at is null or coalesce(u.phone, '') = '' then
    return null;
  end if;
  e164 := case when u.phone like '+%' then u.phone else '+' || u.phone end;

  insert into public.profiles (id, phone) values (u.id, e164)
  on conflict (id) do update set phone = excluded.phone
    where public.profiles.phone is distinct from excluded.phone;

  update public.space_members set user_id = u.id
   where phone = e164 and user_id is null and left_at is null and rejected_at is null;
  update public.loans set lender_id = u.id
   where lender_phone = e164 and lender_id is null and lender_rejected_at is null;
  update public.loans set borrower_id = u.id
   where borrower_phone = e164 and borrower_id is null and borrower_rejected_at is null;
  return null;
end $$;

revoke execute on function public.link_verified_phone() from public, anon, authenticated;

create constraint trigger link_verified_phone
  after insert or update of phone, phone_confirmed_at on auth.users
  deferrable initially deferred
  for each row when (new.phone_confirmed_at is not null)
  execute function public.link_verified_phone();

-- A rejected loan side matches nobody: its id is cleared and the phone no longer counts.
create or replace function public.loan_side(p_loan_id uuid, p_user_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when l.lender_rejected_at is null and (p_user_id = l.lender_id or p.phone = l.lender_phone) then 'lender'
    when l.borrower_rejected_at is null and (p_user_id = l.borrower_id or p.phone = l.borrower_phone) then 'borrower'
  end
  from public.loans l
  left join public.profiles p on p.id = p_user_id
  where l.id = p_loan_id
$$;

create or replace function public.is_loan_party(p_loan_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select from public.loans l
     where l.id = p_loan_id
       and ((l.lender_rejected_at is null and public.is_me(l.lender_id, l.lender_phone))
            or (l.borrower_rejected_at is null and public.is_me(l.borrower_id, l.borrower_phone))))
$$;

-- As in #8, but a linked user counts only once they accepted the claim: linking on verification
-- must not reveal the holder's name or UPI id to whoever recorded the number.
create or replace function public.can_see_profile(p_profile_id uuid, p_phone text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_profile_id = public.verified_uid()
    or exists (
      select from public.space_members them
        join public.space_members me on me.space_id = them.space_id
        join public.spaces s on s.id = them.space_id
       where s.deleted_at is null and me.left_at is null and public.is_me(me.user_id, me.phone)
         and them.user_id = p_profile_id and them.accepted_at is not null)
    or exists (
      select from public.loans l
       where (l.lender_rejected_at is null and public.is_me(l.lender_id, l.lender_phone)
              and l.borrower_id = p_profile_id and l.borrower_accepted_at is not null)
          or (l.borrower_rejected_at is null and public.is_me(l.borrower_id, l.borrower_phone)
              and l.lender_id = p_profile_id and l.lender_accepted_at is not null))
$$;

drop policy loans_select on public.loans;
create policy loans_select on public.loans for select to authenticated
  using ((lender_rejected_at is null and public.is_me(lender_id, lender_phone))
         or (borrower_rejected_at is null and public.is_me(borrower_id, borrower_phone)));
drop policy loans_update on public.loans;
create policy loans_update on public.loans for update to authenticated
  using (lender_rejected_at is null and public.is_me(lender_id, lender_phone))
  with check (lender_rejected_at is null and public.is_me(lender_id, lender_phone));

-- Claims: p_kind is 'space_member' (p_id a space_members.id) or 'loan' (p_id a loans.id). Only the
-- verified holder of a pending claim may settle it; anything else is refused as not theirs.
create function public.accept_claim(p_kind text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  l public.loans;
begin
  if p_kind = 'space_member' then
    update public.space_members m set user_id = me, accepted_at = now()
     where m.id = p_id and m.accepted_at is null and m.left_at is null and m.rejected_at is null
       and public.is_me(m.user_id, m.phone);
    if found then
      return;
    end if;
  elsif p_kind = 'loan' then
    select * into l from public.loans where id = p_id for update;
    if l.lender_accepted_at is null and l.lender_rejected_at is null and public.is_me(l.lender_id, l.lender_phone) then
      update public.loans set lender_id = me, lender_accepted_at = now() where id = p_id;
      return;
    elsif l.borrower_accepted_at is null and l.borrower_rejected_at is null
          and public.is_me(l.borrower_id, l.borrower_phone) then
      update public.loans set borrower_id = me, borrower_accepted_at = now() where id = p_id;
      return;
    end if;
  end if;
  raise exception 'no pending claim % % for the current user', p_kind, p_id using errcode = 'insufficient_privilege';
end $$;

-- 'This isn't me'. The activity row names the number, not the caller, so the creator learns the
-- number was wrong without learning who holds it.
create function public.reject_claim(p_kind text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  m public.space_members;
  l public.loans;
begin
  if p_kind = 'space_member' then
    update public.space_members s set user_id = null, left_at = now(), rejected_at = now()
     where s.id = p_id and s.accepted_at is null and s.left_at is null and s.rejected_at is null
       and public.is_me(s.user_id, s.phone)
    returning * into m;
    if found then
      insert into public.activity (space_id, actor_id, action, after)
      values (m.space_id, null, 'rejected', jsonb_build_object('member_id', m.id, 'phone', m.phone));
      return;
    end if;
  elsif p_kind = 'loan' then
    select * into l from public.loans where id = p_id for update;
    if l.lender_accepted_at is null and l.lender_rejected_at is null and public.is_me(l.lender_id, l.lender_phone) then
      update public.loans set lender_id = null, lender_rejected_at = now() where id = p_id;
      insert into public.activity (loan_id, actor_id, action, after)
      values (p_id, null, 'rejected', jsonb_build_object('side', 'lender', 'phone', l.lender_phone));
      return;
    elsif l.borrower_accepted_at is null and l.borrower_rejected_at is null
          and public.is_me(l.borrower_id, l.borrower_phone) then
      update public.loans set borrower_id = null, borrower_rejected_at = now() where id = p_id;
      insert into public.activity (loan_id, actor_id, action, after)
      values (p_id, null, 'rejected', jsonb_build_object('side', 'borrower', 'phone', l.borrower_phone));
      return;
    end if;
  end if;
  raise exception 'no pending claim % % for the current user', p_kind, p_id using errcode = 'insufficient_privilege';
end $$;

-- Account deletion: the profile and its shared history stay; what identifies the person goes.
create function public.delete_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := public.verified_uid();
begin
  if me is null then
    raise exception 'not signed in with a verified phone' using errcode = 'insufficient_privilege';
  end if;
  update public.profiles set name = null, upi_id = null where id = me;
  delete from public.friends where user_id = me;
end $$;

revoke execute on function
  public.accept_claim(text, uuid), public.reject_claim(text, uuid), public.delete_account()
  from public, anon;
grant execute on function
  public.accept_claim(text, uuid), public.reject_claim(text, uuid), public.delete_account()
  to authenticated;
