-- Loan RPCs (#87): create_loan, record_repayment, confirm_repayment, dispute_repayment.
-- Same contract as add_expense (#10, ADR 0004) and #59: security invoker so RLS stays the gate, a
-- fixed empty search_path, verified callers only, payload-bound idempotency, codes 22023 / 42501 /
-- PT409 with hints. The two-sided confirmation itself stays in the #7 triggers (guard_loan_repayment),
-- so a direct table write is held to the same rules; the RPCs add validation, idempotency, clean
-- error codes, closing and loan activity on top.
--
-- Confirmation model (reused by settle-ups, #78): a record is pending until the other side confirms
-- or disputes it, once and for good. Callers of the recorder's side get 42501 hint own_record; a
-- record already confirmed or disputed gets 22023 hint not_pending. Confirm and dispute are one
-- conditional UPDATE (`where confirmed_at is null and disputed_at is null`), so of two concurrent
-- calls the second waits on the row lock, matches nothing and is refused as not_pending.

-- create_loan and record_repayment use the key as the new row's id (as create_space), so the client
-- can queue repayments against a loan it created offline. The fingerprint is stored on the row.
alter table public.loans add column idempotency_hash text;
alter table public.loan_repayments add column idempotency_hash text;
grant insert (idempotency_hash) on public.loans, public.loan_repayments to authenticated;

alter table public.activity
  drop constraint activity_action_check,
  add constraint activity_action_check
    check (action in ('created', 'edited', 'deleted', 'restored', 'recorded', 'confirmed', 'disputed', 'rejected',
                      'closed'));

-- Loan activity: 'created' with the new loan, 'closed' (or 'edited' if reopened) with before/after.
-- Repayments already log 'recorded' / 'confirmed' / 'disputed' (#7).
create function public.log_loan_activity() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.activity (loan_id, actor_id, action, before, after)
  values (
    new.id,
    case when tg_op = 'INSERT' then new.created_by else auth.uid() end,
    case when tg_op = 'INSERT' then 'created' when new.closed_at is not null then 'closed' else 'edited' end,
    case when tg_op = 'UPDATE' then to_jsonb(old) end,
    to_jsonb(new)
  );
  return null;
end $$;

create trigger loans_activity
  after insert on public.loans
  for each row execute function public.log_loan_activity();
create trigger loans_closed_activity
  after update of closed_at on public.loans
  for each row when (old.closed_at is distinct from new.closed_at)
  execute function public.log_loan_activity();

-- A loan closes when its confirmed repayments reach the principal. The guard (#7) already refuses a
-- confirmation past it, under a lock on the loan, so equality is the only way to get here.
create function public.close_repaid_loan() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.loans l set closed_at = now()
   where l.id = new.loan_id and l.closed_at is null
     and l.principal_minor = (select sum(r.principal_minor) from public.loan_repayments r
                               where r.loan_id = new.loan_id and r.confirmed_at is not null);
  return null;
end $$;

-- Named to fire after loan_repayments_activity, so 'confirmed' is logged before 'closed'.
create trigger loan_repayments_close
  after update on public.loan_repayments
  for each row when (old.confirmed_at is null and new.confirmed_at is not null)
  execute function public.close_repaid_loan();

-- Creates a loan between the caller and a counterparty phone; see docs/api.md for the payload.
-- The counterparty may have no account: their side is a pending claim until they verify and accept
-- (#9). v1 is interest free. Returns the loan id, which is the idempotency key.
create function public.create_loan(p jsonb) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  my_phone text := public.auth_phone();
  v_key uuid;
  v_other public.e164;
  v_principal bigint;
  v_installment bigint;
  v_due_day smallint;
  v_lent boolean;
  v_existing record;
  fingerprint text;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    raise exception 'create_loan: payload must be an object' using errcode = '22023';
  end if;
  if me is null then
    raise exception 'create_loan: caller has no verified phone' using errcode = '42501';
  end if;
  v_key := (p ->> 'idempotency_key')::uuid;
  v_other := (p ->> 'counterparty_phone')::public.e164;
  v_principal := (p ->> 'principal_minor')::bigint;
  v_installment := (p ->> 'installment_minor')::bigint;
  v_due_day := (p ->> 'due_day')::smallint;

  if v_key is null or v_other is null then
    raise exception 'create_loan: idempotency_key and counterparty_phone are required' using errcode = '22023';
  end if;
  if p ->> 'direction' is null or p ->> 'direction' not in ('lent', 'borrowed') then
    raise exception 'create_loan: direction must be lent or borrowed' using errcode = '22023';
  end if;
  v_lent := p ->> 'direction' = 'lent';
  if v_other = my_phone then
    raise exception 'create_loan: the counterparty must be someone else' using errcode = '22023';
  end if;
  if coalesce(p ->> 'interest_type', 'none') <> 'none' then
    raise exception 'create_loan: loans are interest free in v1' using errcode = '22023', hint = 'interest_not_supported';
  end if;
  if v_principal is null or v_principal <= 0 then
    raise exception 'create_loan: principal_minor must be a positive integer' using errcode = '22023';
  end if;
  -- Both or neither: with neither the loan is flexible.
  if (v_installment is null) <> (v_due_day is null) then
    raise exception 'create_loan: installment_minor and due_day go together' using errcode = '22023';
  end if;
  if v_installment <= 0 or v_installment > v_principal then
    raise exception 'create_loan: installment_minor must be between 1 and principal_minor' using errcode = '22023';
  end if;
  if v_due_day not between 1 and 28 then
    raise exception 'create_loan: due_day must be between 1 and 28' using errcode = '22023';
  end if;

  fingerprint := encode(sha256(convert_to(jsonb_build_object(
    'direction', p ->> 'direction',
    'counterparty_phone', v_other,
    'principal_minor', v_principal,
    'installment_minor', v_installment,
    'due_day', v_due_day,
    'start_on', (p ->> 'start_on')::date)::text, 'UTF8')), 'hex');

  select id, created_by, idempotency_hash into v_existing from public.loans where id = v_key;
  if not found then
    insert into public.loans (id, lender_phone, borrower_phone, principal_minor, schedule_type, installment_minor,
                              due_day, start_on, idempotency_hash)
    values (v_key,
            case when v_lent then my_phone else v_other end,
            case when v_lent then v_other else my_phone end,
            v_principal,
            case when v_installment is null then 'flexible' else 'monthly' end::public.loan_schedule_type,
            v_installment, v_due_day,
            coalesce((p ->> 'start_on')::date, (now() at time zone 'Asia/Kolkata')::date),
            fingerprint)
    on conflict (id) do nothing;
    if found then
      return v_key;
    end if;
    -- Lost a race with a concurrent call carrying the same key, or the id is a loan we cannot see.
    select id, created_by, idempotency_hash into v_existing from public.loans where id = v_key;
  end if;
  if v_existing.created_by is distinct from me or v_existing.idempotency_hash is distinct from fingerprint then
    raise exception 'create_loan: idempotency key % was already used with a different payload', v_key
      using errcode = 'PT409', hint = 'idempotency_conflict';
  end if;
  return v_key;
end $$;

-- Records a repayment by either accepted party, pending until the other party confirms it. Returns
-- the repayment id, which is the idempotency key. v1 is interest free: it is all principal.
create function public.record_repayment(p jsonb) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  v_loan uuid;
  v_key uuid;
  v_amount bigint;
  v_method public.repayment_method;
  l public.loans;
  v_existing record;
  fingerprint text;
begin
  if jsonb_typeof(p) is distinct from 'object' then
    raise exception 'record_repayment: payload must be an object' using errcode = '22023';
  end if;
  v_loan := (p ->> 'loan_id')::uuid;
  v_key := (p ->> 'idempotency_key')::uuid;
  v_amount := (p ->> 'amount_minor')::bigint;
  v_method := (p ->> 'method')::public.repayment_method;
  if v_loan is null or v_key is null then
    raise exception 'record_repayment: loan_id and idempotency_key are required' using errcode = '22023';
  end if;
  -- Excludes unverified callers, outsiders, pending claimants and rejected sides.
  if me is null or not public.is_accepted_party(v_loan) then
    raise exception 'record_repayment: caller is not an accepted party to loan %', v_loan using errcode = '42501';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'record_repayment: amount_minor must be a positive integer' using errcode = '22023';
  end if;

  fingerprint := encode(sha256(convert_to(jsonb_build_object(
    'loan_id', v_loan,
    'amount_minor', v_amount,
    'paid_on', (p ->> 'paid_on')::date,
    'method', v_method,
    'reference', nullif(btrim(p ->> 'reference'), ''))::text, 'UTF8')), 'hex');

  -- A replay returns before the state checks: the loan may have closed since.
  select id, recorded_by, idempotency_hash into v_existing from public.loan_repayments where id = v_key;
  if not found then
    select * into l from public.loans where id = v_loan;
    if l.closed_at is not null then
      raise exception 'record_repayment: loan % is closed', v_loan using errcode = '22023', hint = 'loan_closed';
    end if;
    -- Pending repayments do not count: one may yet be disputed. Confirming re-checks (guard, #7).
    if v_amount > l.principal_minor - (select coalesce(sum(r.principal_minor), 0) from public.loan_repayments r
                                        where r.loan_id = v_loan and r.confirmed_at is not null) then
      raise exception 'record_repayment: % is more than is outstanding on loan %', v_amount, v_loan
        using errcode = '22023', hint = 'overpayment';
    end if;

    insert into public.loan_repayments (id, loan_id, amount_minor, principal_minor, paid_on, method, reference,
                                        idempotency_hash)
    values (v_key, v_loan, v_amount, v_amount,
            coalesce((p ->> 'paid_on')::date, (now() at time zone 'Asia/Kolkata')::date),
            v_method, nullif(btrim(p ->> 'reference'), ''), fingerprint)
    on conflict (id) do nothing;
    if found then
      return v_key;
    end if;
    select id, recorded_by, idempotency_hash into v_existing from public.loan_repayments where id = v_key;
  end if;
  if v_existing.recorded_by is distinct from me or v_existing.idempotency_hash is distinct from fingerprint then
    raise exception 'record_repayment: idempotency key % was already used with a different payload', v_key
      using errcode = 'PT409', hint = 'idempotency_conflict';
  end if;
  return v_key;
end $$;

-- Confirm or dispute: shared by the two RPCs below. Only the party opposite the recorder, and only
-- while the repayment is pending. Security definer because loan_side is server-only; it checks the
-- caller itself, and the guard trigger (#7) re-checks all of it on the UPDATE.
create function private.settle_repayment(p_caller text, p_repayment_id uuid, p_confirm boolean, p_reason text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  r public.loan_repayments;
begin
  select * into r from public.loan_repayments where id = p_repayment_id;
  if not found or not public.is_accepted_party(r.loan_id) then
    raise exception '%: caller is not an accepted party to repayment %', p_caller, p_repayment_id
      using errcode = '42501';
  end if;
  if public.loan_side(r.loan_id, me) = public.loan_side(r.loan_id, r.recorded_by) then
    raise exception '%: repayment % was recorded by your side; the other party confirms it', p_caller, p_repayment_id
      using errcode = '42501', hint = 'own_record';
  end if;

  begin
    if p_confirm then
      update public.loan_repayments set confirmed_by = me
       where id = p_repayment_id and confirmed_at is null and disputed_at is null;
    else
      update public.loan_repayments set disputed_by = me, dispute_reason = p_reason
       where id = p_repayment_id and confirmed_at is null and disputed_at is null;
    end if;
  exception when check_violation then
    raise exception '%: confirming repayment % would repay more than the principal', p_caller, p_repayment_id
      using errcode = '22023', hint = 'overpayment';
  end;
  if not found then
    raise exception '%: repayment % is no longer pending', p_caller, p_repayment_id
      using errcode = '22023', hint = 'not_pending';
  end if;
end $$;

-- The other party confirms a pending repayment. Final; closes the loan once it is fully repaid.
-- The key is checked first, so a replay returns after the repayment is no longer pending.
create function public.confirm_repayment(p_repayment_id uuid, p_idempotency_key uuid) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if public.verified_uid() is null then
    raise exception 'confirm_repayment: caller has no verified phone' using errcode = '42501';
  end if;
  if p_repayment_id is null or p_idempotency_key is null then
    raise exception 'confirm_repayment: repayment id and idempotency key are required' using errcode = '22023';
  end if;
  if not private.claim_idempotency_key('confirm_repayment', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object('repayment_id', p_repayment_id)::text, 'UTF8')), 'hex')) then
    return;
  end if;
  perform private.settle_repayment('confirm_repayment', p_repayment_id, true, null);
end $$;

-- The other party disputes a pending repayment with a reason. Final; it stays visible and never counts.
create function public.dispute_repayment(p_repayment_id uuid, p_reason text, p_idempotency_key uuid) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if public.verified_uid() is null then
    raise exception 'dispute_repayment: caller has no verified phone' using errcode = '42501';
  end if;
  if p_repayment_id is null or p_idempotency_key is null then
    raise exception 'dispute_repayment: repayment id and idempotency key are required' using errcode = '22023';
  end if;
  if coalesce(btrim(p_reason), '') = '' or length(btrim(p_reason)) > 500 then
    raise exception 'dispute_repayment: a reason of 1 to 500 characters is required' using errcode = '22023';
  end if;
  if not private.claim_idempotency_key('dispute_repayment', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object('repayment_id', p_repayment_id, 'reason', btrim(p_reason))::text, 'UTF8')), 'hex')) then
    return;
  end if;
  perform private.settle_repayment('dispute_repayment', p_repayment_id, false, btrim(p_reason));
end $$;

revoke execute on function public.log_loan_activity(), public.close_repaid_loan() from public, anon, authenticated;
revoke execute on function
  public.create_loan(jsonb), public.record_repayment(jsonb), private.settle_repayment(text, uuid, boolean, text),
  public.confirm_repayment(uuid, uuid), public.dispute_repayment(uuid, text, uuid)
  from public, anon;
grant execute on function
  public.create_loan(jsonb), public.record_repayment(jsonb), private.settle_repayment(text, uuid, boolean, text),
  public.confirm_repayment(uuid, uuid), public.dispute_repayment(uuid, text, uuid)
  to authenticated;
