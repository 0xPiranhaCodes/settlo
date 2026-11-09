-- Confirm vs dispute of a settle-up under concurrency (#78): two sessions over dblink, as in
-- 16_loan_rpcs_race. A's two devices answer B's pending settle-up at once: whichever commits first
-- wins, and the other waits on the expense row, then is refused as not_pending. Balances count only
-- the confirmed one. Space S: A and B; R1 and R2 are B paying A 1000 and 2000, both pending.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(10);

create function pg_temp.conninfo() returns text language sql as $$
  select format('host=%s dbname=postgres user=postgres password=postgres', host(inet_server_addr()))
$$;
select dblink_connect('setup', pg_temp.conninfo());
select dblink_exec('setup', $$
  begin;
  insert into auth.users (id, phone, phone_confirmed_at) values
    ('00000000-0000-0000-0000-000000007901', '919790000001', now()),
    ('00000000-0000-0000-0000-000000007902', '919790000002', now());
  insert into public.profiles (id, phone) values
    ('00000000-0000-0000-0000-000000007901', '+919790000001'), ('00000000-0000-0000-0000-000000007902', '+919790000002');
  insert into public.spaces (id, name, kind, created_by) values
    ('00000000-0000-0000-0000-000000007910', 'Flat 79', 'flat', '00000000-0000-0000-0000-000000007901');
  insert into public.space_members (id, space_id, phone, user_id, role) values
    ('00000000-0000-0000-0000-000000007921', '00000000-0000-0000-0000-000000007910', '+919790000001',
     '00000000-0000-0000-0000-000000007901', 'owner'),
    ('00000000-0000-0000-0000-000000007922', '00000000-0000-0000-0000-000000007910', '+919790000002',
     '00000000-0000-0000-0000-000000007902', 'member');
  insert into public.expenses (id, space_id, description, amount_minor, is_settlement, created_by) values
    ('00000000-0000-0000-0000-000000007931', '00000000-0000-0000-0000-000000007910', 'Settle up', 1000, true,
     '00000000-0000-0000-0000-000000007902'),
    ('00000000-0000-0000-0000-000000007932', '00000000-0000-0000-0000-000000007910', 'Settle up', 2000, true,
     '00000000-0000-0000-0000-000000007902');
  insert into public.expense_payers (expense_id, member_id, amount_minor) values
    ('00000000-0000-0000-0000-000000007931', '00000000-0000-0000-0000-000000007922', 1000),
    ('00000000-0000-0000-0000-000000007932', '00000000-0000-0000-0000-000000007922', 2000);
  insert into public.expense_splits (expense_id, member_id, split_type, amount_minor) values
    ('00000000-0000-0000-0000-000000007931', '00000000-0000-0000-0000-000000007921', 'exact', 1000),
    ('00000000-0000-0000-0000-000000007932', '00000000-0000-0000-0000-000000007921', 'exact', 2000);
  commit;
$$);

create function pg_temp.begin_as(conn text, uid text) returns text language sql as $$
  select dblink_exec(conn, format($q$begin; set local role authenticated;
    set local request.jwt.claims to '{"sub": "%s", "role": "authenticated"}'$q$, uid));
$$;
create function pg_temp.blocked(pid int) returns boolean language plpgsql as $$
begin
  for i in 1..200 loop
    if exists (select from pg_locks l where l.pid = blocked.pid and not l.granted) then
      return true;
    end if;
    perform pg_sleep(0.05);
  end loop;
  return false;
end $$;
create function pg_temp.outcome(conn text) returns text language plpgsql as $$
begin
  perform * from dblink_get_result(conn, false) t(r text);
  perform * from dblink_get_result(conn, false) t(r text);
  return dblink_error_message(conn);
end $$;
create function pg_temp.confirm(expense text, key text) returns text language sql as $$
  select format($q$select public.confirm_settlement('%s', %s, '00000000-0000-0000-0000-000000007922', '%s')::text$q$,
                expense, (select amount_minor from public.expenses where id = expense::uuid), key)
$$;
create function pg_temp.dispute(expense text, key text) returns text language sql as $$
  select format($q$select public.dispute_settlement('%s', 'Not received', '%s')::text$q$, expense, key)
$$;
create function pg_temp.status(expense text) returns text language sql as $$
  select settlement_status from public.expenses where id = expense::uuid
$$;
-- A's balance; B's is its negation.
create function pg_temp.balance() returns bigint language sql as $$
  select balance_minor from public.space_member_balances where member_id = '00000000-0000-0000-0000-000000007921'
$$;

select is(pg_temp.balance(), 0::bigint, 'pending: neither settle-up counts');

select dblink_connect('s1', pg_temp.conninfo());
select dblink_connect('s2', pg_temp.conninfo());
create temp table s2 as select pid from dblink('s2', 'select pg_backend_pid()') t(pid int);

-- Confirm first: A confirms R1 (uncommitted); A's dispute of R1 waits, then is refused.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-000000007901');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-000000007901');
select * from dblink('s1', pg_temp.confirm('00000000-0000-0000-0000-000000007931',
  '00000000-0000-0000-0000-000000007941')) t(r text);
select dblink_send_query('s2', pg_temp.dispute('00000000-0000-0000-0000-000000007931',
  '00000000-0000-0000-0000-000000007942'));
select ok(pg_temp.blocked((select pid from s2)), 'confirm first: the dispute waits for the confirmation');
select dblink_exec('s1', 'commit');
select matches(pg_temp.outcome('s2'), 'no longer pending', 'confirm first: then the dispute is refused');
select dblink_exec('s2', 'rollback');
select is(pg_temp.status('00000000-0000-0000-0000-000000007931'), 'confirmed', 'confirm first: R1 is confirmed');
select is(pg_temp.balance(), -1000::bigint, 'confirm first: balances count R1');

-- Dispute first: A disputes R2 (uncommitted); A's confirmation of R2 waits, then is refused.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-000000007901');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-000000007901');
select * from dblink('s1', pg_temp.dispute('00000000-0000-0000-0000-000000007932',
  '00000000-0000-0000-0000-000000007943')) t(r text);
select dblink_send_query('s2', pg_temp.confirm('00000000-0000-0000-0000-000000007932',
  '00000000-0000-0000-0000-000000007944'));
select ok(pg_temp.blocked((select pid from s2)), 'dispute first: the confirmation waits for the dispute');
select dblink_exec('s1', 'commit');
select matches(pg_temp.outcome('s2'), 'no longer pending', 'dispute first: then the confirmation is refused');
select dblink_exec('s2', 'rollback');
select is(pg_temp.status('00000000-0000-0000-0000-000000007932'), 'disputed', 'dispute first: R2 is disputed');
select is(pg_temp.balance(), -1000::bigint, 'dispute first: balances do not count R2');
select is((select count(*)::int from public.activity
            where expense_id in ('00000000-0000-0000-0000-000000007931', '00000000-0000-0000-0000-000000007932')
              and action in ('confirmed', 'disputed')), 2, 'each settle-up logs exactly one answer');

select dblink_exec('setup', $$
  begin;
  delete from public.activity where space_id = '00000000-0000-0000-0000-000000007910';
  delete from public.expense_payers where expense_id::text like '00000000-0000-0000-0000-00000000793_';
  delete from public.expense_splits where expense_id::text like '00000000-0000-0000-0000-00000000793_';
  delete from public.expenses where space_id = '00000000-0000-0000-0000-000000007910';
  delete from public.space_members where space_id = '00000000-0000-0000-0000-000000007910';
  delete from public.spaces where id = '00000000-0000-0000-0000-000000007910';
  delete from private.idempotency_keys where user_id = '00000000-0000-0000-0000-000000007901';
  delete from public.profiles where id::text like '00000000-0000-0000-0000-00000000790_';
  delete from auth.users where id::text like '00000000-0000-0000-0000-00000000790_';
  commit;
$$);
select dblink_disconnect('setup');
select dblink_disconnect('s1');
select dblink_disconnect('s2');

select * from finish();
rollback;
