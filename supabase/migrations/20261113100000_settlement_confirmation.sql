-- Two-sided confirmation for settle-ups (#78), on the loan repayment model (#87). A settlement is an
-- expense with is_settlement, one payer (who paid) and one split (the payee, who received). It is
-- pending until the payee confirms or disputes it, once and for good; when the payee records it (or
-- edits it while pending) it is confirmed at once. Only confirmed settlements count toward
-- space_member_balances; pending and disputed ones stay visible and never count.
--
-- Same RPC contract as #59 / #87: a fixed empty search_path, verified callers only, payload-bound
-- idempotency in private.idempotency_keys, codes 22023 / 42501 / PT409 with hints. confirm and
-- dispute are security definer so their shared step stays server-only; every check is on the
-- caller's verified_uid, as RLS would. The expense row is locked first, so of a concurrent confirm
-- and dispute the second waits, then finds it no longer pending.

-- Clients get no privilege on the new columns; only the RPCs below and store_allocations set them.
alter table public.expenses
  add column confirmed_by uuid references public.profiles (id) on delete restrict,
  add column confirmed_at timestamptz,
  add column disputed_by uuid references public.profiles (id) on delete restrict,
  add column disputed_at timestamptz,
  add column dispute_reason text,
  -- Derived so it can never disagree with the timestamps; null for spending.
  add column settlement_status text generated always as (
    case when not is_settlement then null
         when confirmed_at is not null then 'confirmed'
         when disputed_at is not null then 'disputed'
         else 'pending' end
  ) stored,
  add constraint expenses_settlement_answer
    check ((is_settlement or (confirmed_at is null and disputed_at is null))
           and (confirmed_at is null or disputed_at is null));

-- Settlements recorded before #78 already counted; they stay counted (no confirmer is known).
alter table public.expenses disable trigger user;
update public.expenses set confirmed_at = created_at where is_settlement;
alter table public.expenses enable trigger user;

-- Balances: settlements count only once confirmed. Fairness and categories never count them.
create or replace view public.space_member_balances with (security_invoker = true) as
select m.space_id, m.id as member_id, m.phone, m.user_id,
       p.paid as paid_minor,
       s.owed as owed_minor,
       p.paid - s.owed as balance_minor
from public.space_members m
cross join lateral (
  select coalesce(sum(ep.amount_minor), 0)::bigint as paid
  from public.expense_payers ep
  join public.expenses e on e.id = ep.expense_id
  where ep.member_id = m.id and e.deleted_at is null and (not e.is_settlement or e.confirmed_at is not null)
) p
cross join lateral (
  select coalesce(sum(es.amount_minor), 0)::bigint as owed
  from public.expense_splits es
  join public.expenses e on e.id = es.expense_id
  where es.member_id = m.id and e.deleted_at is null and (not e.is_settlement or e.confirmed_at is not null)
) s;

-- Pending settle-ups the caller can see, for Space and Activity 'Needs you' (#91): awaiting_me is
-- true when the caller is the payee and may answer (an accepted, active member).
create view public.pending_settlements with (security_invoker = true) as
select e.id as expense_id, e.space_id, e.amount_minor, e.spent_on, e.created_by, e.created_at,
       pp.member_id as payer_member_id, ps.member_id as payee_member_id,
       (m.accepted_at is not null and m.left_at is null and public.is_me(m.user_id, m.phone)) as awaiting_me
from public.expenses e
join public.expense_payers pp on pp.expense_id = e.id
join public.expense_splits ps on ps.expense_id = e.id
join public.space_members m on m.id = ps.member_id
where e.settlement_status = 'pending' and e.deleted_at is null;

revoke all on public.pending_settlements from public, anon, authenticated;
grant select on public.pending_settlements to authenticated;

-- A settlement stays a settlement (and spending stays spending), and a confirmed or disputed one is
-- final: no edit, delete or restore. Binds server code too; the answer itself starts from pending.
-- Named to fire after expenses_departed_members, whose hint wins for a departed member's expense.
create function public.guard_settlement() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.is_settlement is distinct from old.is_settlement then
    raise exception 'expense % cannot change between spending and a settle-up', old.id
      using errcode = '22023', hint = 'settlement_kind';
  end if;
  if old.confirmed_at is not null or old.disputed_at is not null then
    raise exception 'settle-up % is %; it can no longer change', old.id, old.settlement_status
      using errcode = '22023', hint = 'settlement_final';
  end if;
  return new;
end $$;

create trigger expenses_settlement_final
  before update on public.expenses
  for each row execute function public.guard_settlement();

-- History: 'confirmed' and 'disputed' join created / edited / deleted / restored (#59).
create or replace function public.log_expense_activity() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  act text;
begin
  if tg_op = 'INSERT' then
    act := 'created';
  elsif old.confirmed_at is null and new.confirmed_at is not null then
    act := 'confirmed';
  elsif old.disputed_at is null and new.disputed_at is not null then
    act := 'disputed';
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

-- store_allocations from #70, plus: a settlement has exactly one payer and one other payee
-- (settlement_shape), at most one is pending per payer and payee (settlement_pending), and when the
-- caller writing it is that payee it is confirmed at once.
create or replace function private.store_allocations(p_expense_id uuid, p jsonb, p_caller text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_space uuid := (select e.space_id from public.expenses e where e.id = p_expense_id and e.deleted_at is null);
begin
  if v_space is null or not public.can_edit_expense(p_expense_id) then
    raise exception '%: only the creator or a space owner may change expense %', p_caller, p_expense_id
      using errcode = '42501';
  end if;
  if (select e.is_settlement from public.expenses e where e.id = p_expense_id)
     and (jsonb_typeof(p -> 'payers') is distinct from 'array' or jsonb_array_length(p -> 'payers') <> 1
          or jsonb_typeof(p -> 'splits') is distinct from 'array' or jsonb_array_length(p -> 'splits') <> 1
          or p -> 'payers' -> 0 ->> 'member_id' = p -> 'splits' -> 0 ->> 'member_id') then
    raise exception '%: a settle-up is one payer paying one other member', p_caller
      using errcode = '22023', hint = 'settlement_shape';
  end if;
  -- One pending settle-up per payer and payee: a second would be the same payment recorded twice.
  -- The lock serialises concurrent records of a pair; the check then sees the other's commit.
  if (select e.is_settlement from public.expenses e where e.id = p_expense_id) then
    perform pg_advisory_xact_lock(hashtextextended(
      'settlement:' || (p -> 'payers' -> 0 ->> 'member_id') || ':' || (p -> 'splits' -> 0 ->> 'member_id'), 0));
    if exists (select from public.expenses x
                 join public.expense_payers xp on xp.expense_id = x.id
                 join public.expense_splits xs on xs.expense_id = x.id
                where x.id <> p_expense_id and x.settlement_status = 'pending' and x.deleted_at is null
                  and xp.member_id = (p -> 'payers' -> 0 ->> 'member_id')::uuid
                  and xs.member_id = (p -> 'splits' -> 0 ->> 'member_id')::uuid) then
      raise exception '%: a settle-up between these members is already waiting for the payee', p_caller
        using errcode = '22023', hint = 'settlement_pending';
    end if;
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

  -- The payee recording (or correcting) a settle-up is their confirmation.
  update public.expenses e set confirmed_by = public.verified_uid(), confirmed_at = now()
   where e.id = p_expense_id and e.settlement_status = 'pending'
     and exists (select from public.expense_splits s join public.space_members m on m.id = s.member_id
                  where s.expense_id = e.id and m.accepted_at is not null and m.left_at is null
                    and public.is_me(m.user_id, m.phone));
end $$;

-- Confirm or dispute: shared by the two RPCs below, its only callers (no client may execute it: it
-- does not check the reason or claim the key). Only the payee, only while pending and live.
-- A confirmation names the amount and payer the payee saw: an edit that lands first is refused as
-- settlement_changed rather than confirmed unseen.
create function private.answer_settlement(p_caller text, p_expense_id uuid, p_confirm boolean, p_reason text,
                                          p_amount_minor bigint default null, p_payer uuid default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  e public.expenses;
  v_payer uuid;
  v_payee uuid;
begin
  -- Locks out a concurrent answer, edit or delete until this one commits.
  select * into e from public.expenses where id = p_expense_id and is_settlement for update;
  if not found or not public.is_accepted_member(e.space_id) then
    raise exception '%: caller is not an accepted member of settle-up %''s space', p_caller, p_expense_id
      using errcode = '42501';
  end if;
  v_payer := (select member_id from public.expense_payers where expense_id = e.id);
  v_payee := (select member_id from public.expense_splits where expense_id = e.id);
  if not exists (select from public.space_members m
                  where m.id = v_payee and m.accepted_at is not null and m.left_at is null
                    and public.is_me(m.user_id, m.phone)) then
    raise exception '%: only the member who was paid may answer settle-up %', p_caller, p_expense_id
      using errcode = '42501', hint = 'not_payee';
  end if;
  if e.settlement_status <> 'pending' or e.deleted_at is not null then
    raise exception '%: settle-up % is no longer pending', p_caller, p_expense_id
      using errcode = '22023', hint = 'not_pending';
  end if;

  if p_confirm and (e.amount_minor is distinct from p_amount_minor or v_payer is distinct from p_payer) then
    raise exception '%: settle-up % changed since it was shown; reload it', p_caller, p_expense_id
      using errcode = '22023', hint = 'settlement_changed';
  end if;

  if p_confirm then
    -- Confirming changes both balances: like store_allocations, never a departed member's.
    perform from public.space_members m where m.id in (v_payer, v_payee) order by m.id for share;
    if exists (select from public.space_members m where m.id = v_payer and m.left_at is not null) then
      raise exception '%: settle-up % involves a member who has left', p_caller, p_expense_id
        using errcode = '22023', hint = 'departed_member';
    end if;
    update public.expenses set confirmed_by = public.verified_uid(), confirmed_at = now() where id = e.id;
  else
    update public.expenses set disputed_by = public.verified_uid(), disputed_at = now(), dispute_reason = p_reason
     where id = e.id;
  end if;
end $$;

-- The payee confirms a pending settle-up of p_amount_minor from p_payer_member_id, as shown to them;
-- it counts from now on. Final. The key is checked first, so a replay returns after the settle-up is
-- no longer pending.
create function public.confirm_settlement(p_expense_id uuid, p_amount_minor bigint, p_payer_member_id uuid,
                                          p_idempotency_key uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.verified_uid() is null then
    raise exception 'confirm_settlement: caller has no verified phone' using errcode = '42501';
  end if;
  if p_expense_id is null or p_amount_minor is null or p_payer_member_id is null or p_idempotency_key is null then
    raise exception 'confirm_settlement: expense id, amount, payer and idempotency key are required'
      using errcode = '22023';
  end if;
  if not private.claim_idempotency_key('confirm_settlement', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object('expense_id', p_expense_id, 'amount_minor', p_amount_minor,
                          'payer_member_id', p_payer_member_id)::text, 'UTF8')), 'hex')) then
    return;
  end if;
  perform private.answer_settlement('confirm_settlement', p_expense_id, true, null, p_amount_minor, p_payer_member_id);
end $$;

-- The payee disputes a pending settle-up with a reason. Final; it stays visible and never counts.
create function public.dispute_settlement(p_expense_id uuid, p_reason text, p_idempotency_key uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.verified_uid() is null then
    raise exception 'dispute_settlement: caller has no verified phone' using errcode = '42501';
  end if;
  if p_expense_id is null or p_idempotency_key is null then
    raise exception 'dispute_settlement: expense id and idempotency key are required' using errcode = '22023';
  end if;
  if coalesce(btrim(p_reason), '') = '' or length(btrim(p_reason)) > 500 then
    raise exception 'dispute_settlement: a reason of 1 to 500 characters is required' using errcode = '22023';
  end if;
  if not private.claim_idempotency_key('dispute_settlement', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object('expense_id', p_expense_id, 'reason', btrim(p_reason))::text, 'UTF8')), 'hex')) then
    return;
  end if;
  perform private.answer_settlement('dispute_settlement', p_expense_id, false, btrim(p_reason));
end $$;

revoke execute on function
  public.guard_settlement(), private.answer_settlement(text, uuid, boolean, text, bigint, uuid)
  from public, anon, authenticated;
revoke execute on function
  public.confirm_settlement(uuid, bigint, uuid, uuid), public.dispute_settlement(uuid, text, uuid)
  from public, anon;
grant execute on function
  public.confirm_settlement(uuid, bigint, uuid, uuid), public.dispute_settlement(uuid, text, uuid)
  to authenticated;
