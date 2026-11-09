-- Activity feed order under concurrency (#91, PR #101 review): two sessions over dblink, as in
-- 16_loan_rpcs_race. created_at is the transaction's start, so a transaction that began first and
-- commits last gets the larger id but the earlier time. The feed orders by (created_at, id), so the
-- row that happened later comes first, and paging one row at a time returns each row once.
-- R is an accepted member of space S. A begins, B logs and commits, then A logs and commits.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(5);

create function pg_temp.conninfo() returns text language sql as $$
  select format('host=%s dbname=postgres user=postgres password=postgres', host(inet_server_addr()))
$$;
select dblink_connect('setup', pg_temp.conninfo());
select dblink_exec('setup', $$
  begin;
  insert into auth.users (id, phone, phone_confirmed_at) values
    ('00000000-0000-0000-0000-00000000d101', '919130000001', now());
  insert into public.profiles (id, phone, name) values
    ('00000000-0000-0000-0000-00000000d101', '+919130000001', 'Ravi');
  insert into public.spaces (id, name, kind, created_by) values
    ('00000000-0000-0000-0000-00000000d110', 'Flat D1', 'flat', '00000000-0000-0000-0000-00000000d101');
  insert into public.space_members (space_id, phone, user_id, role, accepted_at) values
    ('00000000-0000-0000-0000-00000000d110', '+919130000001', '00000000-0000-0000-0000-00000000d101', 'owner', now());
  commit;
$$);

select dblink_connect('a', pg_temp.conninfo());
select dblink_connect('b', pg_temp.conninfo());
-- A's transaction starts (and fixes its now()) before B's.
select dblink_exec('a', 'begin');
select * from dblink('a', 'select now()::text') t(r text);
select pg_sleep(0.05);
select * from dblink('b', $$insert into public.activity (space_id, action, after)
  values ('00000000-0000-0000-0000-00000000d110', 'created', '{"description": "B"}') returning id::text$$) t(r text);
select * from dblink('a', $$insert into public.activity (space_id, action, after)
  values ('00000000-0000-0000-0000-00000000d110', 'created', '{"description": "A"}') returning id::text$$) t(r text);
select dblink_exec('a', 'commit');

create function pg_temp.row_of(d text) returns public.activity language sql security definer as $$
  select * from public.activity where space_id = '00000000-0000-0000-0000-00000000d110' and after ->> 'description' = d
$$;
select ok((pg_temp.row_of('A')).id > (pg_temp.row_of('B')).id
          and (pg_temp.row_of('A')).created_at < (pg_temp.row_of('B')).created_at,
  'fixture: A has the larger id but the earlier time');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d101", "role": "authenticated"}', true);
select is((select array_agg(description) from public.activity_feed()), array['B', 'A'],
  'order: the later event comes first, whatever its id');
select is((select array_agg(description) from public.activity_feed(null, null, 1)), array['B'],
  'pages of one: page 1 is B');
select is((select array_agg(f.description) from public.activity_feed(
             (pg_temp.row_of('B')).created_at, (pg_temp.row_of('B')).id, 1) f), array['A'],
  'pages of one: page 2 is A, not B again');
select is((select count(*)::int from public.activity_feed(
             (pg_temp.row_of('A')).created_at, (pg_temp.row_of('A')).id, 1)), 0,
  'pages of one: nothing after A');
reset role;

select dblink_exec('setup', $$
  begin;
  delete from public.activity where space_id = '00000000-0000-0000-0000-00000000d110';
  delete from public.space_members where space_id = '00000000-0000-0000-0000-00000000d110';
  delete from public.spaces where id = '00000000-0000-0000-0000-00000000d110';
  delete from public.profiles where id = '00000000-0000-0000-0000-00000000d101';
  delete from auth.users where id = '00000000-0000-0000-0000-00000000d101';
  commit;
$$);
select dblink_disconnect('setup');
select dblink_disconnect('a');
select dblink_disconnect('b');

select * from finish();
rollback;
