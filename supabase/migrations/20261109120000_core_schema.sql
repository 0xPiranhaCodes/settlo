-- Core schema (#6): profiles, friends, spaces, members, expenses, payers, splits, recurring, activity.
-- Money is bigint paise (ADR 0003). RLS is enabled on every table with no policies; #8 adds them.
-- Shared history must survive: spaces and members are soft-deleted, and every FK from history
-- (spaces, members, expenses, payers, splits, recurring, activity) is ON DELETE RESTRICT.
-- Account deletion anonymises the profile instead of deleting it (follow-up in #9).

create domain public.e164 as text
  check (value ~ '^\+[1-9][0-9]{6,14}$');

create type public.space_kind as enum ('flat', 'trip', 'friend', 'other');
create type public.member_role as enum ('owner', 'member');
create type public.split_type as enum ('equal', 'exact', 'percent', 'shares');
create type public.recurrence as enum ('weekly', 'monthly', 'yearly');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  phone public.e164 not null unique,
  name text,
  upi_id text,
  created_at timestamptz not null default now()
);

-- Keyed by phone so a friend can be recorded before they join.
create table public.friends (
  user_id uuid not null references public.profiles (id) on delete cascade,
  friend_phone public.e164 not null,
  friend_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_phone)
);

create table public.spaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  kind public.space_kind not null default 'other',
  created_by uuid references public.profiles (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.space_members (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces (id) on delete restrict,
  phone public.e164 not null,
  user_id uuid references public.profiles (id) on delete restrict,
  role public.member_role not null default 'member',
  created_at timestamptz not null default now(),
  left_at timestamptz,
  unique (space_id, phone),
  unique (space_id, user_id)
);
create index space_members_user_id_idx on public.space_members (user_id);
create index space_members_phone_idx on public.space_members (phone);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces (id) on delete restrict,
  description text not null,
  category text,
  amount_minor bigint not null check (amount_minor > 0),
  spent_on date not null default current_date,
  is_settlement boolean not null default false,
  created_by uuid references public.profiles (id) on delete restrict default auth.uid(),
  -- Client-generated replay key for add_expense (#10, ADR 0004).
  idempotency_key uuid,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (space_id, idempotency_key)
);
create index expenses_space_id_idx on public.expenses (space_id, spent_on);

create table public.expense_payers (
  expense_id uuid not null references public.expenses (id) on delete restrict,
  member_id uuid not null references public.space_members (id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  primary key (expense_id, member_id)
);
create index expense_payers_member_id_idx on public.expense_payers (member_id);

-- amount_minor is the resolved paise owed; shares / percent_bp record how it was derived.
create table public.expense_splits (
  expense_id uuid not null references public.expenses (id) on delete restrict,
  member_id uuid not null references public.space_members (id) on delete restrict,
  split_type public.split_type not null,
  amount_minor bigint not null check (amount_minor >= 0),
  shares integer check (shares > 0),
  percent_bp integer check (percent_bp between 0 and 10000),
  primary key (expense_id, member_id),
  check ((split_type = 'shares') = (shares is not null)),
  check ((split_type = 'percent') = (percent_bp is not null))
);
create index expense_splits_member_id_idx on public.expense_splits (member_id);

-- template holds the add_expense payers/splits payload used to create each occurrence.
create table public.recurring_expenses (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces (id) on delete restrict,
  description text not null,
  category text,
  amount_minor bigint not null check (amount_minor > 0),
  template jsonb not null,
  recurrence public.recurrence not null,
  next_run_on date not null,
  created_by uuid references public.profiles (id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.activity (
  id bigint generated always as identity primary key,
  space_id uuid not null references public.spaces (id) on delete restrict,
  expense_id uuid references public.expenses (id) on delete restrict,
  actor_id uuid references public.profiles (id) on delete restrict default auth.uid(),
  action text not null check (action in ('created', 'edited', 'deleted', 'restored')),
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);
create index activity_space_id_idx on public.activity (space_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.friends enable row level security;
alter table public.spaces enable row level security;
alter table public.space_members enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_payers enable row level security;
alter table public.expense_splits enable row level security;
alter table public.recurring_expenses enable row level security;
alter table public.activity enable row level security;

-- Activity is trigger-written only, even once #8 adds read policies.
revoke insert, update, delete, truncate on public.activity from anon, authenticated;

-- Balance: sum(payers) = sum(splits) = amount_minor, checked at commit.
-- Soft-deleted expenses are checked too; they are frozen (below), so they stay balanced.
create function public.check_expense_balance() returns trigger
language plpgsql set search_path = '' as $$
declare
  e public.expenses;
  paid bigint;
  owed bigint;
begin
  -- tg_argv[0] names the column holding the expense id ('id' or 'expense_id').
  select * into e from public.expenses
   where id = (case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end ->> tg_argv[0])::uuid;
  if not found then
    return null;
  end if;

  select coalesce(sum(amount_minor), 0) into paid from public.expense_payers where expense_id = e.id;
  select coalesce(sum(amount_minor), 0) into owed from public.expense_splits where expense_id = e.id;
  if paid <> e.amount_minor or owed <> e.amount_minor then
    raise exception 'expense % unbalanced: amount %, payers %, splits %', e.id, e.amount_minor, paid, owed
      using errcode = 'check_violation';
  end if;

  if (select count(distinct split_type) from public.expense_splits where expense_id = e.id) > 1 then
    raise exception 'expense % mixes split types', e.id using errcode = 'check_violation';
  end if;

  if exists (
    select from (select member_id from public.expense_payers where expense_id = e.id
                 union all
                 select member_id from public.expense_splits where expense_id = e.id) x
    join public.space_members m on m.id = x.member_id
    where m.space_id <> e.space_id
  ) then
    raise exception 'expense % references members of another space', e.id using errcode = 'check_violation';
  end if;

  return null;
end $$;

create constraint trigger expenses_balanced
  after insert or update on public.expenses
  deferrable initially deferred for each row execute function public.check_expense_balance('id');
create constraint trigger expense_payers_balanced
  after insert or update or delete on public.expense_payers
  deferrable initially deferred for each row execute function public.check_expense_balance('expense_id');
create constraint trigger expense_splits_balanced
  after insert or update or delete on public.expense_splits
  deferrable initially deferred for each row execute function public.check_expense_balance('expense_id');

-- Activity log for expenses. Security definer so it can write past RLS and the revoke above.
create function public.log_expense_activity() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  act text;
begin
  if tg_op = 'INSERT' then
    act := 'created';
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
    case when tg_op = 'UPDATE' then to_jsonb(old) end,
    to_jsonb(new)
  );
  return null;
end $$;

revoke execute on function public.log_expense_activity() from public, anon, authenticated;

-- No DELETE case: activity.expense_id is RESTRICT, so an expense with history cannot be hard-deleted.
create trigger expenses_activity
  after insert or update on public.expenses
  for each row execute function public.log_expense_activity();

-- A soft-deleted expense is frozen: the only allowed change is restoring it (clearing deleted_at),
-- and its payers and splits cannot be added, changed or removed.
create function public.freeze_deleted_expense() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_table_name = 'expenses' then
    if old.deleted_at is not null
       and (new.deleted_at is not null or to_jsonb(new) - 'deleted_at' <> to_jsonb(old) - 'deleted_at') then
      raise exception 'expense % is deleted; only restoring it is allowed', old.id
        using errcode = 'object_not_in_prerequisite_state';
    end if;
  elsif exists (select from public.expenses
                 where deleted_at is not null and id in (old.expense_id, new.expense_id)) then
    raise exception 'expense % is deleted; its payers and splits are frozen', coalesce(new.expense_id, old.expense_id)
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $$;

create trigger expenses_frozen
  before update on public.expenses
  for each row execute function public.freeze_deleted_expense();
create trigger expense_payers_frozen
  before insert or update or delete on public.expense_payers
  for each row execute function public.freeze_deleted_expense();
create trigger expense_splits_frozen
  before insert or update or delete on public.expense_splits
  for each row execute function public.freeze_deleted_expense();
