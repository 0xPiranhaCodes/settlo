-- Activity feed order under concurrency (#91, PR #101 review): two sessions over dblink, as in
-- 16_loan_rpcs_race. created_at is the transaction's start, so a transaction that began first and
-- commits last gets the larger id but the earlier time. The feed orders by (created_at, id), so the
-- row that happened later comes first, and paging one row at a time returns each row once.
-- R is an accepted member of space S. A begins, B logs and commits, then A logs and commits.
-- Then the paging contract (docs/api.md): pages are strict for rows committed before the first page;
-- a transaction that commits after the client paged past its created_at is not in later pages and
-- appears on a reload from the top. C commits; A2 begins; B2 commits; the client pages [B2] then [C];
-- A2 commits between them in time.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(9);

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

-- Late commit: the client pages past A2's time before A2 commits.
select * from dblink('b', $$insert into public.activity (space_id, action, after)
  values ('00000000-0000-0000-0000-00000000d110', 'created', '{"description": "C"}') returning id::text$$) t(r text);
select pg_sleep(0.05);
select dblink_exec('a', 'begin');
select * from dblink('a', 'select now()::text') t(r text);
select pg_sleep(0.05);
select * from dblink('b', $$insert into public.activity (space_id, action, after)
  values ('00000000-0000-0000-0000-00000000d110', 'created', '{"description": "B2"}') returning id::text$$) t(r text);
set local role authenticated;
create temp table late_page1 as select f.created_at, f.id, f.description from public.activity_feed(null, null, 1) f;
create temp table late_page2 as select f.created_at, f.id, f.description from public.activity_feed(
  (select created_at from late_page1), (select id from late_page1), 1) f;
select is((select array_agg(description) from (select description from late_page1 union all
                                                 select description from late_page2) p), array['B2', 'C'],
  'late commit: the client pages B2, then C, while A2 is open');
reset role;
select * from dblink('a', $$insert into public.activity (space_id, action, after)
  values ('00000000-0000-0000-0000-00000000d110', 'created', '{"description": "A2"}') returning id::text$$) t(r text);
select dblink_exec('a', 'commit');
set local role authenticated;
select ok((pg_temp.row_of('A2')).created_at < (pg_temp.row_of('B2')).created_at
          and (pg_temp.row_of('A2')).created_at > (pg_temp.row_of('C')).created_at,
  'late commit: A2 is timed between B2 and C');
select is((select array_agg(f.description) from public.activity_feed(
             (select created_at from late_page2), (select id from late_page2), 30) f), array['B', 'A'],
  'late commit: continuing from C does not return A2 (documented: it waits for a refresh)');
select is((select array_agg(description) from public.activity_feed(null, null, 3)), array['B2', 'A2', 'C'],
  'late commit: reloading from the top shows A2 in its place');
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
