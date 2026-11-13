-- #257: the name the creator types for the other party. Like space_members.name, it is the creator's
-- label for someone who may not have joined yet, never copied from profiles; clients show it to the
-- creator until the other party has a profile name.
alter table public.loans add column counterparty_name text check (length(counterparty_name) <= 100);
grant insert (counterparty_name) on public.loans to authenticated;

-- Creates a loan between the caller and a counterparty phone; see docs/api.md for the payload.
-- The counterparty may have no account: their side is a pending claim until they verify and accept
-- (#9). v1 is interest free. Returns the loan id, which is the idempotency key.
create or replace function public.create_loan(p jsonb) returns uuid
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
  v_name text;
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
  v_name := nullif(btrim(p ->> 'counterparty_name'), '');

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

  fingerprint := encode(sha256(convert_to((jsonb_build_object(
    'direction', p ->> 'direction',
    'counterparty_phone', v_other,
    'principal_minor', v_principal,
    'installment_minor', v_installment,
    'due_day', v_due_day,
    'start_on', (p ->> 'start_on')::date)
    -- Only when sent, so a payload without a name keeps the fingerprint it had before #257.
    || case when v_name is null then '{}' else jsonb_build_object('counterparty_name', v_name) end
    )::text, 'UTF8')), 'hex');
  if not private.claim_idempotency_key('create_loan', v_key, fingerprint) then
    return v_key;
  end if;

  -- The claim is new; a row with this id is a replay after the purge, or a conflict.
  select id, created_by, idempotency_hash into v_existing from public.loans where id = v_key;
  if not found then
    insert into public.loans (id, lender_phone, borrower_phone, principal_minor, schedule_type, installment_minor,
                              due_day, start_on, counterparty_name, idempotency_hash)
    values (v_key,
            case when v_lent then my_phone else v_other end,
            case when v_lent then v_other else my_phone end,
            v_principal,
            case when v_installment is null then 'flexible' else 'monthly' end::public.loan_schedule_type,
            v_installment, v_due_day,
            coalesce((p ->> 'start_on')::date, (now() at time zone 'Asia/Kolkata')::date),
            v_name, fingerprint)
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
