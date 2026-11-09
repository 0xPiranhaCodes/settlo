-- set_member_role under concurrency (#70): two sessions over dblink, as in 12_space_mutations_race.
-- A space never ends up without an owner: a leave waits for a concurrent promotion and then
-- succeeds, and a demotion waits for a concurrent owner's leave and then is refused.
-- Space R: owner A; members B and C. Nobody owes anything.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(6);

create function pg_temp.conninfo() returns text language sql as $$
  select format('host=%s dbname=postgres user=postgres password=postgres', host(inet_server_addr()))
$$;
select dblink_connect('setup', pg_temp.conninfo());
select dblink_exec('setup', $$
  begin;
  insert into auth.users (id, phone, phone_confirmed_at) values
    ('00000000-0000-0000-0000-00000000e001', '919570000001', now()),
    ('00000000-0000-0000-0000-00000000e002', '919570000002', now()),
    ('00000000-0000-0000-0000-00000000e003', '919570000003', now());
  insert into public.profiles (id, phone) values
    ('00000000-0000-0000-0000-00000000e001', '+919570000001'), ('00000000-0000-0000-0000-00000000e002', '+919570000002'),
    ('00000000-0000-0000-0000-00000000e003', '+919570000003');
  insert into public.spaces (id, name, created_by) values
    ('00000000-0000-0000-0000-00000000e100', 'Race R', '00000000-0000-0000-0000-00000000e001');
  insert into public.space_members (id, space_id, phone, user_id, role) values
    ('00000000-0000-0000-0000-00000000e201', '00000000-0000-0000-0000-00000000e100', '+919570000001', '00000000-0000-0000-0000-00000000e001', 'owner'),
    ('00000000-0000-0000-0000-00000000e202', '00000000-0000-0000-0000-00000000e100', '+919570000002', '00000000-0000-0000-0000-00000000e002', 'member'),
    ('00000000-0000-0000-0000-00000000e203', '00000000-0000-0000-0000-00000000e100', '+919570000003', '00000000-0000-0000-0000-00000000e003', 'member');
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
create function pg_temp.set_role(member text, role text, key text) returns text language sql as $$
  select format($q$select public.set_member_role('00000000-0000-0000-0000-00000000e100', '%s', '%s', '%s')::text$q$,
                member, role, key)
$$;
create function pg_temp.leave(key text) returns text language sql as $$
  select format($q$select public.leave_space('00000000-0000-0000-0000-00000000e100', '%s')::text$q$, key)
$$;
create function pg_temp.owners() returns int language sql as $$
  select count(*)::int from public.space_members
   where space_id = '00000000-0000-0000-0000-00000000e100' and role = 'owner' and left_at is null
$$;

select dblink_connect('s1', pg_temp.conninfo());
select dblink_connect('s2', pg_temp.conninfo());
create temp table s2 as select pid from dblink('s2', 'select pg_backend_pid()') t(pid int);

-- Promote first: sole owner A promotes B (uncommitted); A's leave waits, then succeeds.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000e001');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000e001');
select * from dblink('s1', pg_temp.set_role('00000000-0000-0000-0000-00000000e202', 'owner',
  '00000000-0000-0000-0000-00000000e301')) t(r text);
select dblink_send_query('s2', pg_temp.leave('00000000-0000-0000-0000-00000000e302'));
select ok(pg_temp.blocked((select pid from s2)), 'promote race: the sole owner''s leave waits for the promotion');
select dblink_exec('s1', 'commit');
select is(pg_temp.outcome('s2'), 'OK', 'promote race: once B is an owner, A leaves');
select dblink_exec('s2', 'commit');
select ok(pg_temp.owners() = 1
          and (select role = 'owner' from public.space_members where id = '00000000-0000-0000-0000-00000000e202'),
  'promote race: B is the one owner');

-- Leave first: B promotes C; C leaves (uncommitted); B's self-demotion waits, then is refused.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000e002');
select * from dblink('s1', pg_temp.set_role('00000000-0000-0000-0000-00000000e203', 'owner',
  '00000000-0000-0000-0000-00000000e311')) t(r text);
select dblink_exec('s1', 'commit');
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000e003');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000e002');
select * from dblink('s1', pg_temp.leave('00000000-0000-0000-0000-00000000e312')) t(r text);
select dblink_send_query('s2', pg_temp.set_role('00000000-0000-0000-0000-00000000e202', 'member',
  '00000000-0000-0000-0000-00000000e313'));
select ok(pg_temp.blocked((select pid from s2)), 'demote race: a demotion waits for another owner''s leave');
select dblink_exec('s1', 'commit');
select matches(pg_temp.outcome('s2'), 'last owner', 'demote race: then it is refused as the last owner');
select dblink_exec('s2', 'rollback');
select is(pg_temp.owners(), 1, 'demote race: the space keeps one owner');

select dblink_exec('setup', $$
  begin;
  delete from public.space_members where space_id = '00000000-0000-0000-0000-00000000e100';
  delete from public.spaces where id = '00000000-0000-0000-0000-00000000e100';
  delete from auth.users where id::text like '00000000-0000-0000-0000-00000000e00_';
  commit;
$$);
select dblink_disconnect('setup');
select dblink_disconnect('s1');
select dblink_disconnect('s2');

select * from finish();
rollback;
