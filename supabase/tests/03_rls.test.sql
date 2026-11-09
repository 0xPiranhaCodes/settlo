-- RLS (#8): every public table has policies; a positive and a negative case per table.
-- Callers: A owner (linked by id), B member by phone only, C outsider, D departed member,
-- E unverified number recorded on a space and a loan, then verified. Space S2 is soft-deleted.
begin;
create extension if not exists pgtap with schema extensions;

select plan(87);

-- Rows a statement touched, run as the current role so RLS filtering is visible.
create function pg_temp.affected(q text) returns int language plpgsql as $$
declare
  n int;
begin
  execute q;
  get diagnostics n = row_count;
  return n;
end $$;

-- Fixtures (as postgres, past RLS).
insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000008001', '919000000001', now()),
  ('00000000-0000-0000-0000-000000008002', '919000000002', now()),
  ('00000000-0000-0000-0000-000000008003', '919000000003', now()),
  ('00000000-0000-0000-0000-000000008004', '919000000004', now()),
  ('00000000-0000-0000-0000-000000008005', '919000000005', null);
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000008001', '+919000000001', 'A'),
  ('00000000-0000-0000-0000-000000008002', '+919000000002', 'B'),
  ('00000000-0000-0000-0000-000000008003', '+919000000003', 'C'),
  ('00000000-0000-0000-0000-000000008004', '+919000000004', 'D');
insert into public.friends (user_id, friend_phone) values
  ('00000000-0000-0000-0000-000000008001', '+919000000003'),
  ('00000000-0000-0000-0000-000000008003', '+919000000001');

insert into public.spaces (id, name, kind, created_by) values
  ('00000000-0000-0000-0000-000000008101', 'Flat 4B', 'flat', '00000000-0000-0000-0000-000000008001'),
  ('00000000-0000-0000-0000-000000008102', 'Old trip', 'trip', '00000000-0000-0000-0000-000000008001');
insert into public.space_members (id, space_id, phone, user_id, role, left_at) values
  ('00000000-0000-0000-0000-000000008201', '00000000-0000-0000-0000-000000008101', '+919000000001', '00000000-0000-0000-0000-000000008001', 'owner', null),
  ('00000000-0000-0000-0000-000000008202', '00000000-0000-0000-0000-000000008101', '+919000000002', null, 'member', null),
  ('00000000-0000-0000-0000-000000008204', '00000000-0000-0000-0000-000000008101', '+919000000004', '00000000-0000-0000-0000-000000008004', 'member', now()),
  ('00000000-0000-0000-0000-000000008205', '00000000-0000-0000-0000-000000008101', '+919000000005', null, 'member', null),
  ('00000000-0000-0000-0000-000000008206', '00000000-0000-0000-0000-000000008102', '+919000000001', '00000000-0000-0000-0000-000000008001', 'owner', null);

insert into public.expenses (id, space_id, description, amount_minor) values
  ('00000000-0000-0000-0000-000000008301', '00000000-0000-0000-0000-000000008101', 'Groceries', 3000),
  ('00000000-0000-0000-0000-000000008302', '00000000-0000-0000-0000-000000008102', 'Hotel', 5000);
insert into public.expense_payers (expense_id, member_id, amount_minor) values
  ('00000000-0000-0000-0000-000000008301', '00000000-0000-0000-0000-000000008201', 3000),
  ('00000000-0000-0000-0000-000000008302', '00000000-0000-0000-0000-000000008206', 5000);
insert into public.expense_splits (expense_id, member_id, split_type, amount_minor) values
  ('00000000-0000-0000-0000-000000008301', '00000000-0000-0000-0000-000000008201', 'equal', 1500),
  ('00000000-0000-0000-0000-000000008301', '00000000-0000-0000-0000-000000008202', 'equal', 1500),
  ('00000000-0000-0000-0000-000000008302', '00000000-0000-0000-0000-000000008206', 'equal', 5000);
insert into public.recurring_expenses (id, space_id, description, amount_minor, template, recurrence, next_run_on)
values ('00000000-0000-0000-0000-000000008401', '00000000-0000-0000-0000-000000008101', 'Rent', 1500000, '{}', 'monthly', current_date);
update public.spaces set deleted_at = now() where id = '00000000-0000-0000-0000-000000008102';

-- L1: A lends to E's number (phone only). L2: C lends to B's number.
insert into public.loans (id, lender_phone, borrower_phone, lender_id, principal_minor, installment_minor, due_day, created_by) values
  ('00000000-0000-0000-0000-000000008501', '+919000000001', '+919000000005', '00000000-0000-0000-0000-000000008001',
   100000, 10000, 5, '00000000-0000-0000-0000-000000008001'),
  ('00000000-0000-0000-0000-000000008502', '+919000000003', '+919000000002', '00000000-0000-0000-0000-000000008003',
   50000, 5000, 1, '00000000-0000-0000-0000-000000008003');
insert into public.loan_repayments (id, loan_id, amount_minor, principal_minor, recorded_by)
values ('00000000-0000-0000-0000-000000008601', '00000000-0000-0000-0000-000000008501', 10000, 10000,
        '00000000-0000-0000-0000-000000008001');

-- Catch-all: RLS on, at least one policy, no anon privileges, hardened helpers.
select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and not c.relrowsecurity),
  null,
  'every public table has RLS enabled'
);
select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
      and not exists (select from pg_policy p where p.polrelid = c.oid)),
  null,
  'every public table has at least one policy'
);
select is(
  (select array_agg(c.relname::text order by c.relname) from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
      and has_table_privilege('anon', c.oid, 'select, insert, update, delete, truncate, references, trigger')),
  null,
  'anon has no privileges on any public table'
);
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('verified_uid', 'auth_phone', 'is_me', 'is_space_member', 'is_space_owner',
                        'space_has_members', 'can_bootstrap_space', 'is_expense_member', 'can_allocate',
                        'is_loan_party', 'can_see_profile')
      and not (p.prosecdef and p.proconfig @> array['search_path=""'])),
  null,
  'RLS helpers are security definer with a fixed empty search_path'
);
select is(
  (select count(*)::int from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname in ('is_space_member', 'is_loan_party')),
  2,
  'is_space_member and is_loan_party exist'
);

-- anon sees nothing.
set local role anon;
select throws_ok('select * from public.spaces', '42501', null, 'anon cannot read spaces');
select throws_ok('select * from public.loans', '42501', null, 'anon cannot read loans');
select throws_ok('select id from public.profiles', '42501', null, 'anon cannot read profiles');
reset role;

-- A: owner of S1, linked by user id.
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008001", "role": "authenticated"}';

select ok(public.is_space_member('00000000-0000-0000-0000-000000008101'), 'is_space_member: A is in S1');
select ok(not public.is_space_member('00000000-0000-0000-0000-000000008102'), 'is_space_member: soft-deleted S2 is excluded');
select ok(public.is_loan_party('00000000-0000-0000-0000-000000008501'), 'is_loan_party: A is the lender of L1');
select ok(not public.is_loan_party('00000000-0000-0000-0000-000000008502'), 'is_loan_party: A is not a party to L2');

select results_eq(
  'select id from public.spaces',
  $$values ('00000000-0000-0000-0000-000000008101'::uuid)$$,
  'spaces: A sees S1 but not soft-deleted S2'
);
select is(pg_temp.affected($$update public.spaces set name = 'Flat 4B Indiranagar' where id = '00000000-0000-0000-0000-000000008101'$$),
  1, 'spaces: owner A renames S1');
select is((select count(*)::int from public.space_members where space_id = '00000000-0000-0000-0000-000000008101'),
  4, 'space_members: A sees all four S1 members, including the departed one');
select is((select count(*)::int from public.space_members where space_id = '00000000-0000-0000-0000-000000008102'),
  0, 'space_members: A does not see members of soft-deleted S2');

select results_eq(
  'select id from public.profiles order by id',
  $$values ('00000000-0000-0000-0000-000000008001'::uuid), ('00000000-0000-0000-0000-000000008002'::uuid),
           ('00000000-0000-0000-0000-000000008004'::uuid)$$,
  'profiles: A sees self, phone-only co-member B and departed co-member D, not outsider C'
);
select throws_ok('select * from public.profiles', '42501', null, 'profiles: created_at is not exposed');
select is(pg_temp.affected($$update public.profiles set name = 'A K' where id = '00000000-0000-0000-0000-000000008001'$$),
  1, 'profiles: A updates own name');
select is(pg_temp.affected($$update public.profiles set name = 'x' where id = '00000000-0000-0000-0000-000000008002'$$),
  0, 'profiles: A cannot update B');
select throws_ok($$update public.profiles set phone = '+919000000009' where id = '00000000-0000-0000-0000-000000008001'$$,
  '42501', null, 'profiles: phone cannot be changed by the client');

select results_eq('select friend_phone::text from public.friends', $$values ('+919000000003'::text)$$,
  'friends: A sees only own list');
select lives_ok($$insert into public.friends (user_id, friend_phone) values ('00000000-0000-0000-0000-000000008001', '+919000000002')$$,
  'friends: A adds a friend');
select throws_ok($$insert into public.friends (user_id, friend_phone) values ('00000000-0000-0000-0000-000000008003', '+919000000002')$$,
  '42501', null, 'friends: A cannot write into C''s list');
select is(pg_temp.affected($$delete from public.friends where user_id = '00000000-0000-0000-0000-000000008003'$$),
  0, 'friends: A cannot delete C''s friends');

select results_eq('select id from public.expenses',
  $$values ('00000000-0000-0000-0000-000000008301'::uuid)$$,
  'expenses: A sees S1 expenses, not those of soft-deleted S2');
select lives_ok(
  $q$do $$ begin
    insert into public.expenses (id, space_id, description, amount_minor)
    values ('00000000-0000-0000-0000-000000008303', '00000000-0000-0000-0000-000000008101', 'Milk', 2000);
    insert into public.expense_payers (expense_id, member_id, amount_minor)
    values ('00000000-0000-0000-0000-000000008303', '00000000-0000-0000-0000-000000008201', 2000);
    insert into public.expense_splits (expense_id, member_id, split_type, amount_minor) values
      ('00000000-0000-0000-0000-000000008303', '00000000-0000-0000-0000-000000008201', 'equal', 1000),
      ('00000000-0000-0000-0000-000000008303', '00000000-0000-0000-0000-000000008202', 'equal', 1000);
  end $$$q$,
  'expenses: member A adds an expense with payers and splits'
);
select is((select created_by from public.expenses where id = '00000000-0000-0000-0000-000000008303'),
  '00000000-0000-0000-0000-000000008001'::uuid, 'expenses: created_by is the caller');
select throws_ok(
  $$insert into public.expenses (space_id, description, amount_minor)
    values ('00000000-0000-0000-0000-000000008102', 'Late hotel', 100)$$,
  '42501', null, 'expenses: no new expense in a soft-deleted space');
select throws_ok($$delete from public.expenses where id = '00000000-0000-0000-0000-000000008301'$$,
  '42501', null, 'expenses: clients cannot hard-delete');

select is((select count(*)::int from public.expense_payers), 2, 'expense_payers: A sees payers of S1 expenses only');
select is((select count(*)::int from public.expense_splits), 4, 'expense_splits: A sees splits of S1 expenses only');
select is(pg_temp.affected($$update public.expense_splits set amount_minor = amount_minor
                              where expense_id = '00000000-0000-0000-0000-000000008303'$$),
  2, 'expense_splits: A edits splits of an S1 expense');

select is((select count(*)::int from public.recurring_expenses), 1, 'recurring_expenses: A sees S1 recurring');
select lives_ok(
  $$insert into public.recurring_expenses (space_id, description, amount_minor, template, recurrence, next_run_on)
    values ('00000000-0000-0000-0000-000000008101', 'Wifi', 99900, '{}', 'monthly', current_date)$$,
  'recurring_expenses: A adds a recurring expense'
);

select ok(
  (select count(*) > 0 and bool_and(space_id = '00000000-0000-0000-0000-000000008101'
                                    or loan_id = '00000000-0000-0000-0000-000000008501')
     from public.activity),
  'activity: A sees S1 and L1 activity only'
);
select throws_ok($$insert into public.activity (space_id, action) values ('00000000-0000-0000-0000-000000008101', 'created')$$,
  '42501', null, 'activity: clients cannot insert');
select throws_ok($$update public.activity set action = 'deleted'$$,
  '42501', null, 'activity: clients cannot update');

select results_eq('select id from public.loans', $$values ('00000000-0000-0000-0000-000000008501'::uuid)$$,
  'loans: A sees L1, not L2');
select is((select count(*)::int from public.loan_repayments), 1, 'loan_repayments: A sees L1 repayments');
select lives_ok(
  $$insert into public.loan_repayments (id, loan_id, amount_minor, principal_minor)
    values ('00000000-0000-0000-0000-000000008602', '00000000-0000-0000-0000-000000008501', 10000, 10000)$$,
  'loan_repayments: lender A records a repayment'
);

-- B: member of S1 by phone only (user_id not linked).
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008002", "role": "authenticated"}';

select results_eq('select id from public.spaces', $$values ('00000000-0000-0000-0000-000000008101'::uuid)$$,
  'spaces: phone-only member B sees S1');
select is(pg_temp.affected($$update public.spaces set name = 'Mine' where id = '00000000-0000-0000-0000-000000008101'$$),
  0, 'spaces: non-owner B cannot rename S1');
select lives_ok(
  $$insert into public.space_members (space_id, phone) values ('00000000-0000-0000-0000-000000008101', '+919000000007')$$,
  'space_members: member B adds a member'
);
select throws_ok(
  $$insert into public.space_members (space_id, phone, role) values ('00000000-0000-0000-0000-000000008101', '+919000000008', 'owner')$$,
  '42501', null, 'space_members: member B cannot add an owner');
select lives_ok(
  $q$do $$ begin
    insert into public.expenses (id, space_id, description, amount_minor)
    values ('00000000-0000-0000-0000-000000008304', '00000000-0000-0000-0000-000000008101', 'Gas', 1000);
    insert into public.expense_payers (expense_id, member_id, amount_minor)
    values ('00000000-0000-0000-0000-000000008304', '00000000-0000-0000-0000-000000008202', 1000);
    insert into public.expense_splits (expense_id, member_id, split_type, amount_minor)
    values ('00000000-0000-0000-0000-000000008304', '00000000-0000-0000-0000-000000008202', 'exact', 1000);
  end $$$q$,
  'expenses: phone-only member B adds an expense'
);
select lives_ok('set constraints all immediate', 'expenses added under RLS pass the commit-time balance check');
set constraints all deferred;

-- C: verified outsider.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008003", "role": "authenticated"}';

select ok(not public.is_space_member('00000000-0000-0000-0000-000000008101'), 'is_space_member: outsider C is not in S1');
select ok(not public.is_loan_party('00000000-0000-0000-0000-000000008501'), 'is_loan_party: third party C is not on L1');
select is((select count(*)::int from public.spaces), 0, 'spaces: non-member C sees none');
select is((select count(*)::int from public.space_members), 0, 'space_members: non-member C sees none');
select is((select count(*)::int from public.expenses), 0, 'expenses: non-member C cannot read expenses');
select is((select count(*)::int from public.expense_payers), 0, 'expense_payers: non-member C sees none');
select is((select count(*)::int from public.expense_splits), 0, 'expense_splits: non-member C sees none');
select is((select count(*)::int from public.recurring_expenses), 0, 'recurring_expenses: non-member C sees none');
select is((select count(*)::int from public.activity), 0, 'activity: non-member third party C sees none');
select results_eq('select id from public.loans', $$values ('00000000-0000-0000-0000-000000008502'::uuid)$$,
  'loans: third party C cannot read L1');
select is((select count(*)::int from public.loan_repayments), 0, 'loan_repayments: third party C sees none');
select results_eq('select id from public.profiles order by id',
  $$values ('00000000-0000-0000-0000-000000008002'::uuid), ('00000000-0000-0000-0000-000000008003'::uuid)$$,
  'profiles: C sees self and loan counterparty B only');
select results_eq('select friend_phone::text from public.friends', $$values ('+919000000001'::text)$$,
  'friends: C sees only own list');

select throws_ok(
  $$insert into public.expenses (space_id, description, amount_minor)
    values ('00000000-0000-0000-0000-000000008101', 'Sneaky', 100)$$,
  '42501', null, 'expenses: non-member C cannot insert');
select throws_ok(
  $$insert into public.space_members (space_id, phone) values ('00000000-0000-0000-0000-000000008101', '+919000000003')$$,
  '42501', null, 'space_members: non-member C cannot join S1');
select throws_ok(
  $$insert into public.expense_payers (expense_id, member_id, amount_minor)
    values ('00000000-0000-0000-0000-000000008301', '00000000-0000-0000-0000-000000008201', 1)$$,
  '42501', null, 'expense_payers: non-member C cannot insert');
select is(pg_temp.affected($$delete from public.expense_splits where expense_id = '00000000-0000-0000-0000-000000008301'$$),
  0, 'expense_splits: non-member C cannot delete');
select throws_ok(
  $$insert into public.recurring_expenses (space_id, description, amount_minor, template, recurrence, next_run_on)
    values ('00000000-0000-0000-0000-000000008101', 'x', 1, '{}', 'monthly', current_date)$$,
  '42501', null, 'recurring_expenses: non-member C cannot insert');
select throws_ok(
  $$insert into public.loans (lender_phone, borrower_phone, principal_minor, installment_minor, due_day)
    values ('+919000000001', '+919000000002', 1000, 100, 1)$$,
  '42501', null, 'loans: C cannot create a loan between two others');
select throws_ok(
  $$insert into public.loan_repayments (loan_id, amount_minor, principal_minor)
    values ('00000000-0000-0000-0000-000000008501', 100, 100)$$,
  '42501', null, 'loan_repayments: third party C cannot record on L1');
select is(pg_temp.affected($$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-000000008003'
                              where id = '00000000-0000-0000-0000-000000008601'$$),
  0, 'loan_repayments: third party C cannot confirm');
select lives_ok(
  $$insert into public.loans (lender_phone, borrower_phone, principal_minor, installment_minor, due_day)
    values ('+919000000003', '+919000000004', 1000, 100, 1)$$,
  'loans: C creates a loan as lender by phone');

-- C creates a space: the creator may read it and add its first members, including an owner.
select lives_ok(
  $$insert into public.spaces (id, name) values ('00000000-0000-0000-0000-000000008103', 'C home') returning id$$,
  'spaces: a verified user creates a space and reads it back');
select lives_ok(
  $$insert into public.space_members (id, space_id, phone, role) values
      ('00000000-0000-0000-0000-000000008207', '00000000-0000-0000-0000-000000008103', '+919000000003', 'owner'),
      ('00000000-0000-0000-0000-000000008208', '00000000-0000-0000-0000-000000008103', '+919000000001', 'member')
    returning id$$,
  'space_members: the creator bootstraps the first members, including an owner');
select results_eq('select id from public.spaces', $$values ('00000000-0000-0000-0000-000000008103'::uuid)$$,
  'spaces: C sees the new space as its owner');

-- A cannot allocate an S1 expense to a member of C's space (the balance trigger cannot see it).
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008001", "role": "authenticated"}';
select throws_ok(
  $$insert into public.expense_splits (expense_id, member_id, split_type, amount_minor)
    values ('00000000-0000-0000-0000-000000008303', '00000000-0000-0000-0000-000000008207', 'equal', 0)$$,
  '42501', null, 'expense_splits: cannot name a member of another space');

-- D: departed member of S1.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008004", "role": "authenticated"}';

select is((select count(*)::int from public.spaces), 0, 'spaces: departed member D no longer sees S1');
select throws_ok(
  $$insert into public.expenses (space_id, description, amount_minor)
    values ('00000000-0000-0000-0000-000000008101', 'After leaving', 100)$$,
  '42501', null, 'expenses: departed member D cannot add an expense');
select is(pg_temp.affected($$update public.space_members set left_at = null where id = '00000000-0000-0000-0000-000000008204'$$),
  0, 'space_members: departed member D cannot rejoin by clearing left_at');

-- E: number recorded on S1 and L1, not yet verified.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008005", "role": "authenticated"}';

select is((select count(*)::int from public.spaces), 0, 'unverified E sees no spaces');
select is((select count(*)::int from public.loans), 0, 'unverified E sees no loans');
select is((select count(*)::int from public.activity), 0, 'unverified E sees no activity');
select throws_ok(
  $$insert into public.profiles (id, phone) values ('00000000-0000-0000-0000-000000008005', '+919000000005')$$,
  '42501', null, 'profiles: unverified E cannot create a profile');

-- E verifies the number; the profile would be created by sign-up linking (#9).
reset role;
update auth.users set phone_confirmed_at = now() where id = '00000000-0000-0000-0000-000000008005';
insert into public.profiles (id, phone) values ('00000000-0000-0000-0000-000000008005', '+919000000005');
set local role authenticated;

select results_eq('select id from public.loans', $$values ('00000000-0000-0000-0000-000000008501'::uuid)$$,
  'loans: phone-only borrower E reads L1 after verifying that phone');
select results_eq('select id from public.spaces', $$values ('00000000-0000-0000-0000-000000008101'::uuid)$$,
  'spaces: phone-only member E reads S1 after verifying');
select is(pg_temp.affected($$update public.loan_repayments set confirmed_by = '00000000-0000-0000-0000-000000008005'
                              where id = '00000000-0000-0000-0000-000000008601'$$),
  1, 'loan_repayments: borrower E confirms the lender''s repayment');
select is(pg_temp.affected($$update public.loans set closed_at = now() where id = '00000000-0000-0000-0000-000000008501'$$),
  0, 'loans: borrower E cannot close L1');

-- B leaves S1, then loses access.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008002", "role": "authenticated"}';
select is(pg_temp.affected($$update public.space_members set left_at = now() where id = '00000000-0000-0000-0000-000000008202'$$),
  1, 'space_members: B leaves S1');
select is((select count(*)::int from public.expenses), 0, 'expenses: B no longer reads S1 after leaving');

-- A closes L1 as lender.
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000008001", "role": "authenticated"}';
select is(pg_temp.affected($$update public.loans set closed_at = now() where id = '00000000-0000-0000-0000-000000008501'$$),
  1, 'loans: lender A closes L1');
reset role;

select * from finish();
rollback;
