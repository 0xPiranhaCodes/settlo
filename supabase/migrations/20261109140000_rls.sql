-- RLS (#8): policies on every public table, keyed by profile id or verified phone.
-- Identity: a caller is the holder of auth.uid() only once that user's phone is verified
-- (auth.users.phone_confirmed_at). Unverified callers match nothing. A row recorded against a
-- phone matches the verified holder of that phone until a user_id is linked (#9); once linked,
-- the user_id alone decides, so a recycled number cannot inherit someone else's history.
-- Departed members (left_at) and soft-deleted spaces match nothing (#8 follow-up from PR #21).
-- Least privilege: anon has no table privileges; authenticated gets only the commands and columns
-- each table needs. No client DELETE except allocations and friends: history is soft-deleted.
-- Activity stays trigger-written; clients can only read it.

-- The expense integrity triggers ran as the caller. Under RLS that fails open: a member could add an
-- unbalanced expense, then leave (or soft-delete the space) in the same transaction, and the
-- commit-time check would no longer see the expense and pass. They must see every row.
alter function public.check_expense_balance() security definer;
alter function public.freeze_deleted_expense() security definer;
revoke execute on function public.check_expense_balance(), public.freeze_deleted_expense()
  from public, anon, authenticated;

-- The caller's user id, or null unless their phone is verified.
create function public.verified_uid() returns uuid
language sql stable security definer set search_path = '' as $$
  select u.id from auth.users u
   where u.id = auth.uid() and u.phone_confirmed_at is not null and coalesce(u.phone, '') <> ''
$$;

-- The caller's verified phone in E.164 (auth.users stores it without the leading +), or null.
create function public.auth_phone() returns text
language sql stable security definer set search_path = '' as $$
  select case when u.phone like '+%' then u.phone else '+' || u.phone end
    from auth.users u
   where u.id = auth.uid() and u.phone_confirmed_at is not null and coalesce(u.phone, '') <> ''
$$;

-- Whether a (user_id, phone) pair recorded on a row is the caller.
create function public.is_me(p_user_id uuid, p_phone text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    p_user_id = public.verified_uid()
    or (p_user_id is null and p_phone = public.auth_phone()),
    false)
$$;

create function public.is_space_member(p_space_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select from public.space_members m
      join public.spaces s on s.id = m.space_id
     where m.space_id = p_space_id and s.deleted_at is null and m.left_at is null
       and public.is_me(m.user_id, m.phone))
$$;

create function public.is_space_owner(p_space_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select from public.space_members m
      join public.spaces s on s.id = m.space_id
     where m.space_id = p_space_id and s.deleted_at is null and m.left_at is null
       and m.role = 'owner' and public.is_me(m.user_id, m.phone))
$$;

create function public.space_has_members(p_space_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select from public.space_members m where m.space_id = p_space_id)
$$;

-- A new space has no members yet; its creator may read it and add its first members.
create function public.can_bootstrap_space(p_space_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select from public.spaces s
     where s.id = p_space_id and s.deleted_at is null and s.created_by = public.verified_uid()
       and not public.space_has_members(s.id))
$$;

create function public.is_expense_member(p_expense_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select from public.expenses e
     where e.id = p_expense_id and public.is_space_member(e.space_id))
$$;

-- A payer or split row must name a member of the expense's own space. Checked here because the
-- balance trigger runs as the caller and cannot see members of spaces the caller is not in.
create function public.can_allocate(p_expense_id uuid, p_member_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select from public.expenses e
      join public.space_members m on m.space_id = e.space_id
     where e.id = p_expense_id and m.id = p_member_id and public.is_space_member(e.space_id))
$$;

create function public.is_loan_party(p_loan_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select from public.loans l
     where l.id = p_loan_id
       and (public.is_me(l.lender_id, l.lender_phone) or public.is_me(l.borrower_id, l.borrower_phone)))
$$;

-- Self, anyone who is or was a member of a live space the caller is an active member of
-- (departed members still appear in shared history), and loan counterparties. Others count only
-- through a linked user_id, never a bare phone: anyone can record a space or loan against any number,
-- and that alone must not reveal the number's name or UPI id. A user_id is set only by its owner
-- (self-link below) or by sign-up linking (#9), which must link only claims the user accepts.
create function public.can_see_profile(p_profile_id uuid, p_phone text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_profile_id = public.verified_uid()
    or exists (
      select from public.space_members them
        join public.space_members me on me.space_id = them.space_id
        join public.spaces s on s.id = them.space_id
       where s.deleted_at is null and me.left_at is null and public.is_me(me.user_id, me.phone)
         and them.user_id = p_profile_id)
    or exists (
      select from public.loans l
       where (public.is_me(l.lender_id, l.lender_phone) and l.borrower_id = p_profile_id)
          or (public.is_me(l.borrower_id, l.borrower_phone) and l.lender_id = p_profile_id))
$$;

revoke execute on function
  public.verified_uid(), public.auth_phone(), public.is_me(uuid, text),
  public.is_space_member(uuid), public.is_space_owner(uuid), public.space_has_members(uuid),
  public.can_bootstrap_space(uuid),
  public.is_expense_member(uuid), public.can_allocate(uuid, uuid), public.is_loan_party(uuid),
  public.can_see_profile(uuid, text)
  from public, anon;
grant execute on function
  public.verified_uid(), public.auth_phone(), public.is_me(uuid, text),
  public.is_space_member(uuid), public.is_space_owner(uuid), public.space_has_members(uuid),
  public.can_bootstrap_space(uuid),
  public.is_expense_member(uuid), public.can_allocate(uuid, uuid), public.is_loan_party(uuid),
  public.can_see_profile(uuid, text)
  to authenticated;

-- Privileges: start from nothing, then grant per command and column.
revoke all on
  public.profiles, public.friends, public.spaces, public.space_members, public.expenses,
  public.expense_payers, public.expense_splits, public.recurring_expenses, public.activity,
  public.loans, public.loan_repayments
  from anon, authenticated;

-- created_at is not needed by clients, so profiles are read by column; select '*' is refused.
grant select (id, phone, name, upi_id), insert (id, phone, name, upi_id), update (name, upi_id)
  on public.profiles to authenticated;
-- friend_id is linked server-side (#9).
grant select, insert (user_id, friend_phone), delete on public.friends to authenticated;
grant select, insert (id, name, kind), update (name, kind, deleted_at) on public.spaces to authenticated;
-- Members leave or are removed by left_at. user_id is insertable only to link oneself (policy).
grant select, insert (id, space_id, phone, user_id, role), update (left_at) on public.space_members to authenticated;
grant select,
  insert (id, space_id, description, category, amount_minor, spent_on, is_settlement, idempotency_key),
  update (description, category, amount_minor, spent_on, is_settlement, deleted_at)
  on public.expenses to authenticated;
grant select, insert, update (amount_minor), delete on public.expense_payers to authenticated;
grant select, insert, update (split_type, amount_minor, shares, percent_bp), delete
  on public.expense_splits to authenticated;
grant select,
  insert (id, space_id, description, category, amount_minor, template, recurrence, next_run_on),
  update (description, category, amount_minor, template, recurrence, next_run_on, deleted_at)
  on public.recurring_expenses to authenticated;
grant select on public.activity to authenticated;
grant select,
  insert (id, lender_phone, borrower_phone, lender_id, borrower_id, principal_minor, interest_type,
          schedule_type, installment_minor, due_day, start_on),
  update (closed_at)
  on public.loans to authenticated;
-- The guard trigger stamps confirmed_at / disputed_at.
grant select,
  insert (id, loan_id, amount_minor, principal_minor, interest_minor, paid_on, method, reference),
  update (confirmed_by, disputed_by, dispute_reason)
  on public.loan_repayments to authenticated;

-- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (public.can_see_profile(id, phone));
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = public.verified_uid() and phone = public.auth_phone());
create policy profiles_update on public.profiles for update to authenticated
  using (id = public.verified_uid()) with check (id = public.verified_uid());

-- friends: each user's own list.
create policy friends_select on public.friends for select to authenticated
  using (user_id = public.verified_uid());
create policy friends_insert on public.friends for insert to authenticated
  with check (user_id = public.verified_uid());
create policy friends_delete on public.friends for delete to authenticated
  using (user_id = public.verified_uid());

-- spaces: members read; any verified user creates; owners rename and soft-delete.
-- The bootstrap clause is row-local so INSERT ... RETURNING sees the new space.
create policy spaces_select on public.spaces for select to authenticated
  using (public.is_space_member(id)
         or (created_by = public.verified_uid() and deleted_at is null
             and not public.space_has_members(id)));
create policy spaces_insert on public.spaces for insert to authenticated
  with check (created_by = public.verified_uid() and deleted_at is null);
create policy spaces_update on public.spaces for update to authenticated
  using (public.is_space_owner(id)) with check (public.is_space_owner(id));

-- space_members: members read and add members; only the creator's first insert may add owners.
-- A member may leave (own row); an owner may remove anyone.
create policy space_members_select on public.space_members for select to authenticated
  using (public.is_space_member(space_id) or public.can_bootstrap_space(space_id));
create policy space_members_insert on public.space_members for insert to authenticated
  with check (((public.is_space_member(space_id) and role = 'member') or public.can_bootstrap_space(space_id))
              and (user_id is null or (user_id = public.verified_uid() and phone = public.auth_phone())));
create policy space_members_update on public.space_members for update to authenticated
  using (public.is_space_member(space_id)
         and (public.is_me(user_id, phone) or public.is_space_owner(space_id)))
  with check (public.is_space_member(space_id)
              and (public.is_me(user_id, phone) or public.is_space_owner(space_id)));

-- expenses: active members of live spaces only.
create policy expenses_select on public.expenses for select to authenticated
  using (public.is_space_member(space_id));
create policy expenses_insert on public.expenses for insert to authenticated
  with check (public.is_space_member(space_id) and created_by = public.verified_uid());
create policy expenses_update on public.expenses for update to authenticated
  using (public.is_space_member(space_id)) with check (public.is_space_member(space_id));

-- expense_payers / expense_splits: follow the expense; rows must name a member of its space.
create policy expense_payers_select on public.expense_payers for select to authenticated
  using (public.is_expense_member(expense_id));
create policy expense_payers_insert on public.expense_payers for insert to authenticated
  with check (public.can_allocate(expense_id, member_id));
create policy expense_payers_update on public.expense_payers for update to authenticated
  using (public.is_expense_member(expense_id)) with check (public.can_allocate(expense_id, member_id));
create policy expense_payers_delete on public.expense_payers for delete to authenticated
  using (public.is_expense_member(expense_id));

create policy expense_splits_select on public.expense_splits for select to authenticated
  using (public.is_expense_member(expense_id));
create policy expense_splits_insert on public.expense_splits for insert to authenticated
  with check (public.can_allocate(expense_id, member_id));
create policy expense_splits_update on public.expense_splits for update to authenticated
  using (public.is_expense_member(expense_id)) with check (public.can_allocate(expense_id, member_id));
create policy expense_splits_delete on public.expense_splits for delete to authenticated
  using (public.is_expense_member(expense_id));

-- recurring_expenses
create policy recurring_expenses_select on public.recurring_expenses for select to authenticated
  using (public.is_space_member(space_id));
create policy recurring_expenses_insert on public.recurring_expenses for insert to authenticated
  with check (public.is_space_member(space_id) and created_by = public.verified_uid());
create policy recurring_expenses_update on public.recurring_expenses for update to authenticated
  using (public.is_space_member(space_id)) with check (public.is_space_member(space_id));

-- activity: read-only; rows are written by security-definer triggers.
create policy activity_select on public.activity for select to authenticated
  using (public.is_space_member(space_id) or public.is_loan_party(loan_id));

-- loans: parties read; a party creates; the lender closes. Row-local so RETURNING works.
create policy loans_select on public.loans for select to authenticated
  using (public.is_me(lender_id, lender_phone) or public.is_me(borrower_id, borrower_phone));
create policy loans_insert on public.loans for insert to authenticated
  with check (created_by = public.verified_uid()
              and (public.is_me(lender_id, lender_phone) or public.is_me(borrower_id, borrower_phone))
              and (lender_id is null or lender_id = public.verified_uid())
              and (borrower_id is null or borrower_id = public.verified_uid()));
create policy loans_update on public.loans for update to authenticated
  using (public.is_me(lender_id, lender_phone)) with check (public.is_me(lender_id, lender_phone));

-- loan_repayments: parties read and record; the guard trigger decides who may confirm or dispute.
create policy loan_repayments_select on public.loan_repayments for select to authenticated
  using (public.is_loan_party(loan_id));
create policy loan_repayments_insert on public.loan_repayments for insert to authenticated
  with check (public.is_loan_party(loan_id) and recorded_by = public.verified_uid());
create policy loan_repayments_update on public.loan_repayments for update to authenticated
  using (public.is_loan_party(loan_id)) with check (public.is_loan_party(loan_id));
