-- Loans (#7): loans and loan_repayments with two-sided confirmation.
-- Money is bigint paise (ADR 0003). RLS is enabled with no policies; #8 adds them.
-- A repayment is recorded by one party and confirmed or disputed by the other; either outcome is final.
-- Repayments and their activity are ON DELETE RESTRICT, so a loan with repayments cannot be hard-deleted.

-- v1 is interest-free; simple and reducing are reserved (CHECK below) pending a legal read.
create type public.loan_interest_type as enum ('none', 'simple', 'reducing');
-- flexible: no fixed instalment or due day.
create type public.loan_schedule_type as enum ('monthly', 'flexible');
create type public.repayment_method as enum ('upi', 'cash', 'bank', 'other');

-- Parties are keyed by phone so a loan can be recorded against a number that has not joined.
create table public.loans (
  id uuid primary key default gen_random_uuid(),
  lender_phone public.e164 not null,
  borrower_phone public.e164 not null,
  lender_id uuid references public.profiles (id) on delete restrict,
  borrower_id uuid references public.profiles (id) on delete restrict,
  principal_minor bigint not null check (principal_minor > 0),
  interest_type public.loan_interest_type not null default 'none',
  schedule_type public.loan_schedule_type not null default 'monthly',
  installment_minor bigint check (installment_minor > 0),
  due_day smallint check (due_day between 1 and 28),
  start_on date not null default current_date,
  closed_at timestamptz,
  created_by uuid references public.profiles (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  check (lender_phone <> borrower_phone),
  check (installment_minor <= principal_minor),
  check ((schedule_type = 'monthly') = (installment_minor is not null and due_day is not null)),
  check ((schedule_type = 'flexible') = (installment_minor is null and due_day is null)),
  constraint loans_interest_free_v1 check (interest_type = 'none')
);
create index loans_lender_phone_idx on public.loans (lender_phone);
create index loans_borrower_phone_idx on public.loans (borrower_phone);
create index loans_lender_id_idx on public.loans (lender_id);
create index loans_borrower_id_idx on public.loans (borrower_id);

-- status is derived so it can never disagree with the timestamps.
create table public.loan_repayments (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references public.loans (id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  principal_minor bigint not null check (principal_minor >= 0),
  interest_minor bigint not null default 0 check (interest_minor >= 0),
  paid_on date not null default current_date,
  method public.repayment_method,
  reference text,
  recorded_by uuid not null references public.profiles (id) on delete restrict default auth.uid(),
  confirmed_by uuid references public.profiles (id) on delete restrict,
  confirmed_at timestamptz,
  disputed_by uuid references public.profiles (id) on delete restrict,
  disputed_at timestamptz,
  dispute_reason text,
  status text generated always as (
    case when confirmed_at is not null then 'confirmed'
         when disputed_at is not null then 'disputed'
         else 'pending' end
  ) stored,
  created_at timestamptz not null default now(),
  check (amount_minor = principal_minor + interest_minor),
  check ((confirmed_by is null) = (confirmed_at is null)),
  check ((disputed_by is null) = (disputed_at is null)),
  check (confirmed_at is null or disputed_at is null),
  check (dispute_reason is null or disputed_at is not null)
);
create index loan_repayments_loan_id_idx on public.loan_repayments (loan_id, paid_on);

-- Activity now covers loans too: a row belongs to exactly one space or one loan.
alter table public.activity
  alter column space_id drop not null,
  add column loan_id uuid references public.loans (id) on delete restrict,
  add column repayment_id uuid references public.loan_repayments (id) on delete restrict,
  drop constraint activity_action_check,
  add constraint activity_action_check
    check (action in ('created', 'edited', 'deleted', 'restored', 'recorded', 'confirmed', 'disputed')),
  add constraint activity_space_xor_loan check ((space_id is null) <> (loan_id is null));
create index activity_loan_id_idx on public.activity (loan_id, created_at desc);

alter table public.loans enable row level security;
alter table public.loan_repayments enable row level security;

-- 'lender', 'borrower' or null: which side of the loan a user is on, by profile id or verified phone.
create function public.loan_side(p_loan_id uuid, p_user_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when p_user_id = l.lender_id or p.phone = l.lender_phone then 'lender'
    when p_user_id = l.borrower_id or p.phone = l.borrower_phone then 'borrower'
  end
  from public.loans l
  left join public.profiles p on p.id = p_user_id
  where l.id = p_loan_id
$$;

revoke execute on function public.loan_side(uuid, uuid) from public, anon, authenticated;

-- Linked ids must match the party's phone, the creator must be a party, and parties never change.
-- Security definer so it can read profiles past RLS.
create function public.check_loan_parties() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE'
     and (new.lender_phone <> old.lender_phone or new.borrower_phone <> old.borrower_phone
          or new.created_by is distinct from old.created_by) then
    raise exception 'loan % parties cannot change', old.id using errcode = 'object_not_in_prerequisite_state';
  end if;

  if new.lender_id is not null
     and not exists (select from public.profiles where id = new.lender_id and phone = new.lender_phone) then
    raise exception 'lender_id does not match lender_phone' using errcode = 'check_violation';
  end if;
  if new.borrower_id is not null
     and not exists (select from public.profiles where id = new.borrower_id and phone = new.borrower_phone) then
    raise exception 'borrower_id does not match borrower_phone' using errcode = 'check_violation';
  end if;

  if tg_op = 'INSERT' then
    if auth.uid() is not null and new.created_by is distinct from auth.uid() then
      raise exception 'created_by must be the current user' using errcode = 'insufficient_privilege';
    end if;
    if new.created_by is not null
       and new.created_by is distinct from new.lender_id and new.created_by is distinct from new.borrower_id
       and not exists (select from public.profiles where id = new.created_by
                         and phone in (new.lender_phone, new.borrower_phone)) then
      raise exception 'loan creator must be the lender or the borrower' using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end $$;

revoke execute on function public.check_loan_parties() from public, anon, authenticated;

create trigger loans_parties
  before insert or update on public.loans
  for each row execute function public.check_loan_parties();

-- Two-sided confirmation. A repayment is inserted pending by a party; the only change ever allowed
-- is the other party confirming or disputing it, once. Only confirmed repayments count toward
-- the loan: confirming cannot take confirmed principal past the loan principal.
create function public.guard_loan_repayment() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  l public.loans;
  actor uuid;
  actor_side text;
  confirmed bigint;
begin
  -- Lock the loan so concurrent confirmations are checked against each other.
  select * into l from public.loans where id = new.loan_id for update;

  if tg_op = 'INSERT' then
    if auth.uid() is not null and new.recorded_by is distinct from auth.uid() then
      raise exception 'recorded_by must be the current user' using errcode = 'insufficient_privilege';
    end if;
    if public.loan_side(l.id, new.recorded_by) is null then
      raise exception 'repayment must be recorded by a party to loan %', l.id using errcode = 'insufficient_privilege';
    end if;
    if l.closed_at is not null then
      raise exception 'loan % is closed', l.id using errcode = 'object_not_in_prerequisite_state';
    end if;
    if l.interest_type = 'none' and new.interest_minor <> 0 then
      raise exception 'loan % is interest free', l.id using errcode = 'check_violation';
    end if;
    if new.confirmed_by is not null or new.disputed_by is not null then
      raise exception 'a repayment is recorded pending' using errcode = 'check_violation';
    end if;
    new.confirmed_at := null;
    new.disputed_at := null;
    return new;
  end if;

  if old.confirmed_at is not null or old.disputed_at is not null then
    raise exception 'repayment % is %; confirmation and dispute are final', old.id, old.status
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  -- status is excluded: a stored generated column is still null in a BEFORE trigger.
  if to_jsonb(new) - array['confirmed_by', 'confirmed_at', 'disputed_by', 'disputed_at', 'dispute_reason', 'status']
     <> to_jsonb(old) - array['confirmed_by', 'confirmed_at', 'disputed_by', 'disputed_at', 'dispute_reason', 'status'] then
    raise exception 'repayment % can only be confirmed or disputed', old.id
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if new.confirmed_by is not null and new.disputed_by is null then
    actor := new.confirmed_by;
    new.confirmed_at := now();
    new.disputed_at := null;
    new.dispute_reason := null;
  elsif new.disputed_by is not null and new.confirmed_by is null then
    actor := new.disputed_by;
    new.disputed_at := now();
    new.confirmed_at := null;
  else
    raise exception 'repayment % must be either confirmed or disputed', old.id
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if auth.uid() is not null and actor is distinct from auth.uid() then
    raise exception 'confirmed_by/disputed_by must be the current user' using errcode = 'insufficient_privilege';
  end if;
  actor_side := public.loan_side(l.id, actor);
  if actor_side is null or actor_side = public.loan_side(l.id, new.recorded_by) then
    raise exception 'repayment % must be confirmed or disputed by the other party', old.id
      using errcode = 'insufficient_privilege';
  end if;

  if new.confirmed_by is not null then
    select coalesce(sum(principal_minor), 0) into confirmed
      from public.loan_repayments where loan_id = l.id and confirmed_at is not null;
    if confirmed + new.principal_minor > l.principal_minor then
      raise exception 'confirming repayment % would repay % of a % principal', old.id,
        confirmed + new.principal_minor, l.principal_minor using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;

revoke execute on function public.guard_loan_repayment() from public, anon, authenticated;

create trigger loan_repayments_guard
  before insert or update on public.loan_repayments
  for each row execute function public.guard_loan_repayment();

-- No DELETE case: activity.repayment_id is RESTRICT, so a repayment cannot be hard-deleted.
create function public.log_repayment_activity() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.activity (loan_id, repayment_id, actor_id, action, before, after)
  values (
    new.loan_id,
    new.id,
    case when tg_op = 'INSERT' then new.recorded_by else coalesce(new.confirmed_by, new.disputed_by) end,
    case when tg_op = 'INSERT' then 'recorded' when new.confirmed_at is not null then 'confirmed' else 'disputed' end,
    case when tg_op = 'UPDATE' then to_jsonb(old) end,
    to_jsonb(new)
  );
  return null;
end $$;

revoke execute on function public.log_repayment_activity() from public, anon, authenticated;

create trigger loan_repayments_activity
  after insert or update on public.loan_repayments
  for each row execute function public.log_repayment_activity();
