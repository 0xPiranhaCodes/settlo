-- Confirm vs dispute under concurrency (#87): two sessions over dblink, as in 14_membership_race.
-- B's two devices answer L's pending repayment at once: whichever commits first wins, and the other
-- waits on the repayment row, then is refused as not_pending. Neither can change a final answer.
-- Loan K: L lends B 30000; R1 10000 and R2 10000, both recorded by L.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(8);

create function pg_temp.conninfo() returns text language sql as $$
  select format('host=%s dbname=postgres user=postgres password=postgres', host(inet_server_addr()))
$$;
select dblink_connect('setup', pg_temp.conninfo());
select dblink_exec('setup', $$
  begin;
  insert into auth.users (id, phone, phone_confirmed_at) values
    ('00000000-0000-0000-0000-00000000f001', '919580000001', now()),
    ('00000000-0000-0000-0000-00000000f002', '919580000002', now());
  insert into public.profiles (id, phone) values
    ('00000000-0000-0000-0000-00000000f001', '+919580000001'), ('00000000-0000-0000-0000-00000000f002', '+919580000002');
  insert into public.loans (id, lender_phone, borrower_phone, lender_id, borrower_id, principal_minor,
                           schedule_type, created_by) values
    ('00000000-0000-0000-0000-00000000f100', '+919580000001', '+919580000002', '00000000-0000-0000-0000-00000000f001',
     '00000000-0000-0000-0000-00000000f002', 30000, 'flexible', '00000000-0000-0000-0000-00000000f001');
  insert into public.loan_repayments (id, loan_id, amount_minor, principal_minor, recorded_by) values
    ('00000000-0000-0000-0000-00000000f201', '00000000-0000-0000-0000-00000000f100', 10000, 10000,
     '00000000-0000-0000-0000-00000000f001'),
    ('00000000-0000-0000-0000-00000000f202', '00000000-0000-0000-0000-00000000f100', 10000, 10000,
     '00000000-0000-0000-0000-00000000f001');
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
create function pg_temp.confirm(repayment text, key text) returns text language sql as $$
  select format($q$select public.confirm_repayment('%s', '%s')::text$q$, repayment, key)
$$;
create function pg_temp.dispute(repayment text, key text) returns text language sql as $$
  select format($q$select public.dispute_repayment('%s', 'Not received', '%s')::text$q$, repayment, key)
$$;
create function pg_temp.status(repayment text) returns text language sql as $$
  select status from public.loan_repayments where id = repayment::uuid
$$;
create function pg_temp.repaid() returns bigint language sql as $$
  select repaid_minor from public.loan_summaries where loan_id = '00000000-0000-0000-0000-00000000f100'
$$;

select dblink_connect('s1', pg_temp.conninfo());
select dblink_connect('s2', pg_temp.conninfo());
create temp table s2 as select pid from dblink('s2', 'select pg_backend_pid()') t(pid int);

-- Confirm first: B confirms R1 (uncommitted); B's dispute of R1 waits, then is refused.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000f002');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000f002');
select * from dblink('s1', pg_temp.confirm('00000000-0000-0000-0000-00000000f201',
  '00000000-0000-0000-0000-00000000f301')) t(r text);
select dblink_send_query('s2', pg_temp.dispute('00000000-0000-0000-0000-00000000f201',
  '00000000-0000-0000-0000-00000000f302'));
select ok(pg_temp.blocked((select pid from s2)), 'confirm first: the dispute waits for the confirmation');
select dblink_exec('s1', 'commit');
select matches(pg_temp.outcome('s2'), 'no longer pending', 'confirm first: then the dispute is refused');
select dblink_exec('s2', 'rollback');
select is(pg_temp.status('00000000-0000-0000-0000-00000000f201'), 'confirmed', 'confirm first: R1 is confirmed');
select is(pg_temp.repaid(), 10000::bigint, 'confirm first: loan_summaries counts R1');

-- Dispute first: B disputes R2 (uncommitted); B's confirmation of R2 waits, then is refused.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000f002');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000f002');
select * from dblink('s1', pg_temp.dispute('00000000-0000-0000-0000-00000000f202',
  '00000000-0000-0000-0000-00000000f303')) t(r text);
select dblink_send_query('s2', pg_temp.confirm('00000000-0000-0000-0000-00000000f202',
  '00000000-0000-0000-0000-00000000f304'));
select ok(pg_temp.blocked((select pid from s2)), 'dispute first: the confirmation waits for the dispute');
select dblink_exec('s1', 'commit');
select matches(pg_temp.outcome('s2'), 'no longer pending', 'dispute first: then the confirmation is refused');
select dblink_exec('s2', 'rollback');
select is(pg_temp.status('00000000-0000-0000-0000-00000000f202'), 'disputed', 'dispute first: R2 is disputed');
select is(pg_temp.repaid(), 10000::bigint, 'dispute first: loan_summaries does not count R2');

select dblink_exec('setup', $$
  begin;
  delete from public.activity where loan_id = '00000000-0000-0000-0000-00000000f100';
  delete from public.loan_repayments where loan_id = '00000000-0000-0000-0000-00000000f100';
  delete from public.loans where id = '00000000-0000-0000-0000-00000000f100';
  delete from private.idempotency_keys where user_id = '00000000-0000-0000-0000-00000000f002';
  delete from public.profiles where id::text like '00000000-0000-0000-0000-00000000f00_';
  delete from auth.users where id::text like '00000000-0000-0000-0000-00000000f00_';
  commit;
$$);
select dblink_disconnect('setup');
select dblink_disconnect('s1');
select dblink_disconnect('s2');

select * from finish();
rollback;
