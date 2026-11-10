-- The write barrier of delete_account (#74, PR #135 re-review): two or more sessions over dblink.
-- W shares space Q with A (W accepted; a pending row QP to invite) and is invited by A to space R.
-- While W's deletion is open, W's own update_profile, issue_invite, redeem_invite and add_expense
-- all wait for it and are then refused, so nothing is written in the deleted account's name.
-- V's add_expense that started before V's deletion commits first and stays as history.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(19);

create function pg_temp.conninfo() returns text language sql as $$
  select format('host=%s dbname=postgres user=postgres password=postgres', host(inet_server_addr()))
$$;
select dblink_connect('setup', pg_temp.conninfo());
select dblink_exec('setup', $$
  begin;
  insert into auth.users (id, phone, phone_confirmed_at) values
    ('00000000-0000-0000-0000-0000000b0001', '919680000001', now()),
    ('00000000-0000-0000-0000-0000000b0002', '919680000002', now()),
    ('00000000-0000-0000-0000-0000000b0003', '919680000003', now());
  commit;
  begin;
  update public.profiles set name = 'Asha' where id = '00000000-0000-0000-0000-0000000b0001';
  update public.profiles set name = 'Wren', upi_id = 'wren@okaxis' where id = '00000000-0000-0000-0000-0000000b0002';
  insert into public.spaces (id, name, created_by) values
    ('00000000-0000-0000-0000-0000000b0101', 'Barrier Q', '00000000-0000-0000-0000-0000000b0001'),
    ('00000000-0000-0000-0000-0000000b0102', 'Barrier R', '00000000-0000-0000-0000-0000000b0001');
  insert into public.space_members (id, space_id, phone, user_id, role) values
    ('00000000-0000-0000-0000-0000000b0201', '00000000-0000-0000-0000-0000000b0101', '+919680000001', '00000000-0000-0000-0000-0000000b0001', 'owner'),
    ('00000000-0000-0000-0000-0000000b0202', '00000000-0000-0000-0000-0000000b0101', '+919680000002', '00000000-0000-0000-0000-0000000b0002', 'member'),
    ('00000000-0000-0000-0000-0000000b0203', '00000000-0000-0000-0000-0000000b0101', '+919680000003', '00000000-0000-0000-0000-0000000b0003', 'member'),
    ('00000000-0000-0000-0000-0000000b0204', '00000000-0000-0000-0000-0000000b0101', '+919680000009', null, 'member'),
    ('00000000-0000-0000-0000-0000000b0205', '00000000-0000-0000-0000-0000000b0102', '+919680000001', '00000000-0000-0000-0000-0000000b0001', 'owner'),
    ('00000000-0000-0000-0000-0000000b0206', '00000000-0000-0000-0000-0000000b0102', '+919680000002', null, 'member');
  commit;
$$);

create function pg_temp.begin_as(conn text, uid text) returns text language sql as $$
  select dblink_exec(conn, format($q$begin; set local role authenticated;
    set local request.jwt.claims to '{"sub": "%s", "role": "authenticated"}'$q$, uid));
$$;
create function pg_temp.blocked(conn text) returns boolean language plpgsql as $$
declare
  p int;
begin
  select pid into p from pids where pids.conn = blocked.conn;
  for i in 1..200 loop
    if exists (select from pg_locks l where l.pid = p and not l.granted) then
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
create function pg_temp.add_expense(member text, what text) returns text language sql as $$
  select format($q$select public.add_expense('{"idempotency_key": "%s", "space_id": "00000000-0000-0000-0000-0000000b0101",
    "description": "%s", "amount_minor": 1000, "split_type": "equal",
    "payers": [{"member_id": "%s", "amount_minor": 1000}],
    "splits": [{"member_id": "00000000-0000-0000-0000-0000000b0201"}, {"member_id": "%s"}]}')::text$q$,
    gen_random_uuid(), what, member, member)
$$;

create temp table pids (conn text, pid int);
do $$
declare
  c text;
begin
  foreach c in array array['del', 'w1', 'w2', 'w3', 'w4'] loop
    perform dblink_connect(c, pg_temp.conninfo());
    insert into pids select c, pid from dblink(c, 'select pg_backend_pid()') t(pid int);
  end loop;
end $$;

-- A invites W's number to R; W could accept it with this token.
select pg_temp.begin_as('w1', '00000000-0000-0000-0000-0000000b0001');
create temp table invite as select token from dblink('w1', $$select public.issue_invite('space',
  '00000000-0000-0000-0000-0000000b0206', '00000000-0000-0000-0000-0000000b0301')$$) t(token text);
select dblink_exec('w1', 'commit');

-- Delete first: W's deletion is open; four writes of W's arrive.
select pg_temp.begin_as('del', '00000000-0000-0000-0000-0000000b0002');
select * from dblink('del', 'select public.delete_account()::text') t(r text);
select pg_temp.begin_as(c, '00000000-0000-0000-0000-0000000b0002') from unnest(array['w1', 'w2', 'w3', 'w4']) c;
select dblink_send_query('w1', $$select public.update_profile('RESTORED', 'restored@upi')::text$$);
select dblink_send_query('w2', $$select public.issue_invite('space', '00000000-0000-0000-0000-0000000b0204',
  '00000000-0000-0000-0000-0000000b0302')$$);
select dblink_send_query('w3', format($$select public.redeem_invite('%s', '00000000-0000-0000-0000-0000000b0303')$$,
  (select token from invite)));
select dblink_send_query('w4', pg_temp.add_expense('00000000-0000-0000-0000-0000000b0202', 'IN FLIGHT'));
select ok(pg_temp.blocked('w1'), 'update_profile waits for the open deletion');
select ok(pg_temp.blocked('w2'), 'issue_invite waits for the open deletion');
select ok(pg_temp.blocked('w3'), 'redeem_invite waits for the open deletion');
select ok(pg_temp.blocked('w4'), 'add_expense waits for the open deletion');
select dblink_exec('del', 'commit');
select matches(pg_temp.outcome('w1'), 'account has been deleted', 'then update_profile is refused');
select isnt(pg_temp.outcome('w2'), 'OK', 'then issue_invite is refused');
select isnt(pg_temp.outcome('w3'), 'OK', 'then redeem_invite is refused');
select matches(pg_temp.outcome('w4'), 'account has been deleted', 'then add_expense is refused');
select dblink_exec(c, 'rollback') from unnest(array['w1', 'w2', 'w3', 'w4']) c;

select results_eq(
  $$select name, upi_id, deleted_at is not null from public.profiles where id = '00000000-0000-0000-0000-0000000b0002'$$,
  $$values ('Deleted user', null::text, true)$$, 'the tombstone got no name or UPI id back');
select is((select count(*)::int from private.invite_links
            where issuer_id = '00000000-0000-0000-0000-0000000b0002' and revoked_at is null),
  0, 'the deleted account has no live invite link');
select results_eq(
  $$select user_id, accepted_at from public.space_members where id = '00000000-0000-0000-0000-0000000b0206'$$,
  $$values (null::uuid, null::timestamptz)$$, 'the invitation to R was not accepted in its name');
select is((select count(*)::int from public.expenses where description = 'IN FLIGHT'),
  0, 'the queued expense that arrived during the deletion was not written');

-- Afterwards: W's token still verifies as a JWT, and every write with it is refused.
select pg_temp.begin_as('w1', '00000000-0000-0000-0000-0000000b0002');
select dblink_send_query('w1', $$select public.update_profile('RESTORED', null)::text$$);
select isnt(pg_temp.outcome('w1'), 'OK', 'a deleted account cannot call update_profile');
select dblink_exec('w1', 'rollback');
select pg_temp.begin_as('w1', '00000000-0000-0000-0000-0000000b0002');
select dblink_send_query('w1', $$update public.profiles set name = 'RESTORED' where id = '00000000-0000-0000-0000-0000000b0002'$$);
select matches(pg_temp.outcome('w1'), 'account has been deleted', 'nor write its profile directly');
select dblink_exec('w1', 'rollback');
select pg_temp.begin_as('w1', '00000000-0000-0000-0000-0000000b0002');
select dblink_send_query('w1', pg_temp.add_expense('00000000-0000-0000-0000-0000000b0202', 'AFTER'));
select isnt(pg_temp.outcome('w1'), 'OK', 'nor add an expense');
select dblink_exec('w1', 'rollback');

-- Write first: V's add_expense is open; V's deletion waits for it, and the expense is history.
select pg_temp.begin_as('w1', '00000000-0000-0000-0000-0000000b0003');
select * from dblink('w1', pg_temp.add_expense('00000000-0000-0000-0000-0000000b0203', 'BEFORE')) t(r text);
select pg_temp.begin_as('del', '00000000-0000-0000-0000-0000000b0003');
select dblink_send_query('del', 'select public.delete_account()::text');
select ok(pg_temp.blocked('del'), 'a deletion waits for a write of the same user that started first');
select dblink_exec('w1', 'commit');
select is(pg_temp.outcome('del'), 'OK', 'then goes through');
select dblink_exec('del', 'commit');
select results_eq(
  $$select e.deleted_at is null, p.name from public.expenses e join public.profiles p on p.id = e.created_by
     where e.description = 'BEFORE'$$,
  $$values (true, 'Deleted user')$$, 'what was committed before the deletion stays, under the tombstone');
select is((select count(*)::int from private.account_deletions), 0, 'no right to tombstone is left behind');

select dblink_exec('setup', $$
  begin;
  delete from public.activity where space_id::text like '00000000-0000-0000-0000-0000000b010_';
  delete from public.expense_payers where member_id::text like '00000000-0000-0000-0000-0000000b020_';
  delete from public.expense_splits where member_id::text like '00000000-0000-0000-0000-0000000b020_';
  delete from public.expenses where space_id::text like '00000000-0000-0000-0000-0000000b010_';
  delete from private.invite_links where issuer_id::text like '00000000-0000-0000-0000-0000000b000_';
  delete from private.invite_rate_limits where user_id::text like '00000000-0000-0000-0000-0000000b000_';
  delete from public.space_members where space_id::text like '00000000-0000-0000-0000-0000000b010_';
  delete from public.spaces where id::text like '00000000-0000-0000-0000-0000000b010_';
  delete from auth.users where id::text like '00000000-0000-0000-0000-0000000b000_';
  delete from public.profiles where id::text like '00000000-0000-0000-0000-0000000b000_';
  commit;
$$);
select dblink_disconnect(c) from unnest(array['setup', 'del', 'w1', 'w2', 'w3', 'w4']) c;

select * from finish();
rollback;
