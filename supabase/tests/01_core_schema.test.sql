-- Core schema (#6): deferred expense balance, activity log, frozen soft deletes, RESTRICT history,
-- E.164 phones, RLS on by default. Includes regression tests for each exploit in the PR #21 review.
begin;
create extension if not exists pgtap with schema extensions;

select plan(30);

insert into public.spaces (id, name, kind)
values ('00000000-0000-0000-0000-00000000a001', 'Flat 4B', 'flat');
insert into public.space_members (id, space_id, phone, role) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a001', '+919000000001', 'owner'),
  ('00000000-0000-0000-0000-00000000b002', '00000000-0000-0000-0000-00000000a001', '+919000000002', 'member'),
  ('00000000-0000-0000-0000-00000000b003', '00000000-0000-0000-0000-00000000a001', '+919000000003', 'member');

-- Balanced: ₹100.00 paid by member 1, split 3334/3333/3333 (remainder to the payer).
insert into public.expenses (id, space_id, description, amount_minor)
values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000a001', 'Groceries', 10000);
insert into public.expense_payers (expense_id, member_id, amount_minor)
values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000b001', 10000);
insert into public.expense_splits (expense_id, member_id, split_type, amount_minor) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000b001', 'equal', 3334),
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000b002', 'equal', 3333),
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000b003', 'equal', 3333);

-- SET CONSTRAINTS ALL IMMEDIATE runs the deferred checks exactly as COMMIT would.
select lives_ok('set constraints all immediate', 'balanced insert passes the commit-time check');
set constraints all deferred;

savepoint unbalanced;
select lives_ok(
  $$insert into public.expenses (id, space_id, description, amount_minor)
    values ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-00000000a001', 'Rent', 5000)$$,
  'unbalanced insert is accepted mid-transaction (check is deferred)'
);
select throws_ok(
  'set constraints all immediate',
  '23514', null,
  'unbalanced insert fails at commit'
);
rollback to savepoint unbalanced;
set constraints all deferred;

select throws_ok(
  $q$do $$ begin
    insert into public.expenses (id, space_id, description, amount_minor)
    values ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-00000000a001', 'Taxi', 900);
    insert into public.expense_payers values
      ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-00000000b001', 900);
    insert into public.expense_splits (expense_id, member_id, split_type, amount_minor) values
      ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-00000000b002', 'exact', 400);
    set constraints all immediate;
  end $$$q$,
  '23514', null,
  'splits that do not sum to the amount fail at commit'
);
set constraints all deferred;

select throws_ok(
  $q$do $$ begin
    update public.expenses set amount_minor = 12000 where id = '00000000-0000-0000-0000-00000000c001';
    set constraints all immediate;
  end $$$q$,
  '23514', null,
  'editing the amount without payers and splits fails at commit'
);
set constraints all deferred;

-- Edit writes before/after activity.
update public.expenses set description = 'Groceries and milk'
 where id = '00000000-0000-0000-0000-00000000c001';
select results_eq(
  $$select action, before->>'description', after->>'description' from public.activity
     where expense_id = '00000000-0000-0000-0000-00000000c001' order by id$$,
  $$values ('created'::text, null::text, 'Groceries'::text),
           ('edited', 'Groceries', 'Groceries and milk')$$,
  'insert and edit write activity, the edit with before/after'
);

select throws_ok(
  $$insert into public.space_members (space_id, phone)
    values ('00000000-0000-0000-0000-00000000a001', '9876543210')$$,
  '23514', null,
  'phone CHECK rejects a number without +country code'
);
select throws_ok(
  $$insert into public.space_members (space_id, phone)
    values ('00000000-0000-0000-0000-00000000a001', '+91 98765 43210')$$,
  '23514', null,
  'phone CHECK rejects spaces'
);

select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0,
  'RLS is enabled on every public table'
);

select ok(
  not has_table_privilege('authenticated', 'public.activity', 'insert'),
  'authenticated cannot insert activity directly'
);

select is(
  (select count(*)::int from pg_constraint
    where contype = 'f' and confdeltype <> 'r'
      and conrelid in ('public.spaces'::regclass, 'public.space_members'::regclass, 'public.expenses'::regclass,
                       'public.expense_payers'::regclass, 'public.expense_splits'::regclass,
                       'public.recurring_expenses'::regclass, 'public.activity'::regclass)),
  0,
  'every FK from a history table is ON DELETE RESTRICT'
);

-- Review exploit 1: soft-delete an expense, then corrupt its allocations and make it unrestorable.
update public.expenses set deleted_at = now() where id = '00000000-0000-0000-0000-00000000c001';
select is(
  (select action from public.activity where expense_id = '00000000-0000-0000-0000-00000000c001' order by id desc limit 1),
  'deleted',
  'soft delete is logged as deleted'
);
select throws_ok($$update public.expense_payers set amount_minor = 1 where expense_id = '00000000-0000-0000-0000-00000000c001'$$,
  '55000', null, 'deleted expense: payer UPDATE is rejected');
select throws_ok($$delete from public.expense_payers where expense_id = '00000000-0000-0000-0000-00000000c001'$$,
  '55000', null, 'deleted expense: payer DELETE is rejected');
select throws_ok($$insert into public.expense_payers values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000b002', 1)$$,
  '55000', null, 'deleted expense: payer INSERT is rejected');
select throws_ok($$update public.expense_splits set amount_minor = 1 where expense_id = '00000000-0000-0000-0000-00000000c001'$$,
  '55000', null, 'deleted expense: split UPDATE is rejected');
select throws_ok($$delete from public.expense_splits where expense_id = '00000000-0000-0000-0000-00000000c001'$$,
  '55000', null, 'deleted expense: split DELETE is rejected');
select throws_ok($$update public.expenses set amount_minor = 999999 where id = '00000000-0000-0000-0000-00000000c001'$$,
  '55000', null, 'deleted expense: amount UPDATE is rejected');
select throws_ok($$update public.expenses set deleted_at = now() - interval '1 day' where id = '00000000-0000-0000-0000-00000000c001'$$,
  '55000', null, 'deleted expense: changing deleted_at (other than clearing it) is rejected');
select throws_ok($$delete from public.space_members where id = '00000000-0000-0000-0000-00000000b002'$$,
  '23503', null, 'member on a soft-deleted expense cannot be hard-deleted');

select lives_ok($$update public.expenses set deleted_at = null where id = '00000000-0000-0000-0000-00000000c001'$$,
  'restoring a soft-deleted expense is allowed');
select lives_ok('set constraints all immediate', 'restored expense is still balanced at commit');
set constraints all deferred;
select is(
  (select action from public.activity where expense_id = '00000000-0000-0000-0000-00000000c001' order by id desc limit 1),
  'restored',
  'restore is logged as restored'
);
select throws_ok($$delete from public.space_members where id = '00000000-0000-0000-0000-00000000b003'$$,
  '23503', null, 'member on a live expense cannot be hard-deleted');

-- Review exploit 2: deleting a space wiped its ledger and audit trail.
select throws_ok($$delete from public.spaces where id = '00000000-0000-0000-0000-00000000a001'$$,
  '23503', null, 'space with history cannot be hard-deleted');
select throws_ok($$delete from public.expenses where id = '00000000-0000-0000-0000-00000000c001'$$,
  '23503', null, 'expense with activity cannot be hard-deleted');
select lives_ok($$update public.space_members set left_at = now() where id = '00000000-0000-0000-0000-00000000b003'$$,
  'a member leaves by soft delete');
select lives_ok($$update public.spaces set deleted_at = now() where id = '00000000-0000-0000-0000-00000000a001'$$,
  'a space is removed by soft delete');
select is(
  (select count(*)::int from public.activity where space_id = '00000000-0000-0000-0000-00000000a001'),
  4,
  'shared history survives: created, edited, deleted, restored'
);

-- Review exploit 3: deleting the account erased attribution on history it created.
insert into auth.users (id, phone) values ('00000000-0000-0000-0000-00000000d001', '919000000009');
insert into public.profiles (id, phone) values ('00000000-0000-0000-0000-00000000d001', '+919000000009');
insert into public.recurring_expenses (space_id, description, amount_minor, template, recurrence, next_run_on, created_by)
values ('00000000-0000-0000-0000-00000000a001', 'Rent', 1500000, '{}', 'monthly', current_date,
        '00000000-0000-0000-0000-00000000d001');
select throws_ok($$delete from auth.users where id = '00000000-0000-0000-0000-00000000d001'$$,
  '23503', null, 'deleting an account whose profile has history fails');

select * from finish();
rollback;
