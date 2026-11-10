-- delete_account against a concurrent sign-in (#74): two sessions over dblink, as in 14_membership_race.
-- GoTrue's verification is an update of the auth row whose deferred linking runs at its commit.
-- Whichever gets the auth row first, the account ends deleted and the number's unclaimed row unlinked.
-- A recorded D1's and D2's numbers in space R after they last verified, so the rows are still unlinked.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(7);

create function pg_temp.conninfo() returns text language sql as $$
  select format('host=%s dbname=postgres user=postgres password=postgres', host(inet_server_addr()))
$$;
select dblink_connect('setup', pg_temp.conninfo());
select dblink_exec('setup', $$
  begin;
  insert into auth.users (id, phone, phone_confirmed_at) values
    ('00000000-0000-0000-0000-0000000c0001', '919670000001', now()),
    ('00000000-0000-0000-0000-0000000c0002', '919670000002', now()),
    ('00000000-0000-0000-0000-0000000c0003', '919670000003', now());
  commit;
  begin;
  insert into public.spaces (id, name, created_by) values
    ('00000000-0000-0000-0000-0000000c0100', 'Race R', '00000000-0000-0000-0000-0000000c0001');
  insert into public.space_members (id, space_id, phone, user_id, role) values
    ('00000000-0000-0000-0000-0000000c0201', '00000000-0000-0000-0000-0000000c0100', '+919670000001', '00000000-0000-0000-0000-0000000c0001', 'owner'),
    ('00000000-0000-0000-0000-0000000c0202', '00000000-0000-0000-0000-0000000c0100', '+919670000002', null, 'member'),
    ('00000000-0000-0000-0000-0000000c0203', '00000000-0000-0000-0000-0000000c0100', '+919670000003', null, 'member');
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
-- What is left of a user: auth rows, tombstoned, profile phone, and who their Race R row is linked to.
create function pg_temp.state(uid uuid, member uuid) returns text language sql as $$
  select format('%s auth, deleted %s, phone %s, member %s',
    (select count(*) from auth.users where id = uid),
    (select deleted_at is not null from public.profiles where id = uid),
    (select coalesce(phone::text, 'none') from public.profiles where id = uid),
    (select coalesce(user_id::text, 'unlinked') from public.space_members where id = member))
$$;

select dblink_connect('s1', pg_temp.conninfo());
select dblink_connect('s2', pg_temp.conninfo());
create temp table pids as
  select (select pid from dblink('s1', 'select pg_backend_pid()') t(pid int)) as s1,
         (select pid from dblink('s2', 'select pg_backend_pid()') t(pid int)) as s2;

-- Sign-in first: D1 verifies again (uncommitted); D1's delete waits, then releases what it linked.
select dblink_exec('s1', $$begin; update auth.users set phone_confirmed_at = clock_timestamp()
  where id = '00000000-0000-0000-0000-0000000c0002'$$);
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-0000000c0002');
select dblink_send_query('s2', 'select public.delete_account()::text');
select ok(pg_temp.blocked((select s2 from pids)), 'sign-in first: the delete waits for the verification');
select dblink_exec('s1', 'commit');
select is(pg_temp.outcome('s2'), 'OK', 'sign-in first: then the delete goes through');
select dblink_exec('s2', 'commit');
select is(pg_temp.state('00000000-0000-0000-0000-0000000c0002', '00000000-0000-0000-0000-0000000c0202'),
  '0 auth, deleted t, phone none, member unlinked',
  'sign-in first: the account is deleted and the claim the sign-in linked is released');

-- Delete first: D2 deletes (uncommitted); the verification waits, then finds no user to verify.
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-0000000c0003');
select * from dblink('s2', 'select public.delete_account()::text') t(r text);
select dblink_exec('s1', 'begin');
select dblink_send_query('s1', $$update auth.users set phone_confirmed_at = clock_timestamp()
  where id = '00000000-0000-0000-0000-0000000c0003'$$);
select ok(pg_temp.blocked((select s1 from pids)), 'delete first: the verification waits for the delete');
select dblink_exec('s2', 'commit');
select is(pg_temp.outcome('s1'), 'OK', 'delete first: then the verification updates nothing');
select dblink_exec('s1', 'commit');
select is(pg_temp.state('00000000-0000-0000-0000-0000000c0003', '00000000-0000-0000-0000-0000000c0203'),
  '0 auth, deleted t, phone none, member unlinked',
  'delete first: the tombstone is not revived and nothing is linked to it');

-- Two deletes at once (a double tap that got past the app): the second waits, then is a no-op.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-0000000c0001');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-0000000c0001');
select * from dblink('s1', 'select public.delete_account()::text') t(r text);
select dblink_send_query('s2', 'select public.delete_account()::text');
select pg_temp.blocked((select s2 from pids));
select dblink_exec('s1', 'commit');
select is(pg_temp.outcome('s2'), 'OK', 'two deletes: the second returns normally');
select dblink_exec('s2', 'commit');

select dblink_exec('setup', $$
  begin;
  delete from public.space_members where space_id = '00000000-0000-0000-0000-0000000c0100';
  delete from public.spaces where id = '00000000-0000-0000-0000-0000000c0100';
  delete from public.profiles where id::text like '00000000-0000-0000-0000-0000000c000_';
  delete from auth.users where id::text like '00000000-0000-0000-0000-0000000c000_';
  commit;
$$);
select dblink_disconnect('setup');
select dblink_disconnect('s1');
select dblink_disconnect('s2');

select * from finish();
rollback;
