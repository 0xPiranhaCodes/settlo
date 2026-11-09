-- Space mutations under concurrency (#59, PR #68 review): two sessions over dblink.
-- Idempotency keys (same user: replay waits, changed payload conflicts; other users never wait),
-- leave vs. a concurrent expense in both orders, and two owners leaving at once.
-- Fixtures are committed through a third session and removed at the end, as in 10_rpcs.
-- Space Q: owners O1 and O2; members M3, M4, M5. Nobody owes anything at the start.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

select plan(15);

create function pg_temp.conninfo() returns text language sql as $$
  select format('host=%s dbname=postgres user=postgres password=postgres', host(inet_server_addr()))
$$;
select dblink_connect('setup', pg_temp.conninfo());
select dblink_exec('setup', $$
  begin;
  insert into auth.users (id, phone, phone_confirmed_at) values
    ('00000000-0000-0000-0000-00000000d001', '919580000001', now()),
    ('00000000-0000-0000-0000-00000000d002', '919580000002', now()),
    ('00000000-0000-0000-0000-00000000d003', '919580000003', now()),
    ('00000000-0000-0000-0000-00000000d004', '919580000004', now()),
    ('00000000-0000-0000-0000-00000000d005', '919580000005', now());
  insert into public.profiles (id, phone) values
    ('00000000-0000-0000-0000-00000000d001', '+919580000001'), ('00000000-0000-0000-0000-00000000d002', '+919580000002'),
    ('00000000-0000-0000-0000-00000000d003', '+919580000003'), ('00000000-0000-0000-0000-00000000d004', '+919580000004'),
    ('00000000-0000-0000-0000-00000000d005', '+919580000005');
  insert into public.spaces (id, name, created_by) values
    ('00000000-0000-0000-0000-00000000d100', 'Race Q', '00000000-0000-0000-0000-00000000d001');
  insert into public.space_members (id, space_id, phone, user_id, role) values
    ('00000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d100', '+919580000001', '00000000-0000-0000-0000-00000000d001', 'owner'),
    ('00000000-0000-0000-0000-00000000d202', '00000000-0000-0000-0000-00000000d100', '+919580000002', '00000000-0000-0000-0000-00000000d002', 'owner'),
    ('00000000-0000-0000-0000-00000000d203', '00000000-0000-0000-0000-00000000d100', '+919580000003', '00000000-0000-0000-0000-00000000d003', 'member'),
    ('00000000-0000-0000-0000-00000000d204', '00000000-0000-0000-0000-00000000d100', '+919580000004', '00000000-0000-0000-0000-00000000d004', 'member'),
    ('00000000-0000-0000-0000-00000000d205', '00000000-0000-0000-0000-00000000d100', '+919580000005', '00000000-0000-0000-0000-00000000d005', 'member');
  commit;
$$);

create function pg_temp.begin_as(conn text, uid text) returns text language sql as $$
  select dblink_exec(conn, format($q$begin; set local role authenticated;
    set local request.jwt.claims to '{"sub": "%s", "role": "authenticated"}'$q$, uid));
$$;
-- Whether backend pid is waiting on a lock, polled for up to 10 s (pg_locks is read live).
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
-- The error a sent query ended with ('OK' if it succeeded); drains the connection.
create function pg_temp.outcome(conn text) returns text language plpgsql as $$
begin
  perform * from dblink_get_result(conn, false) t(r text);
  perform * from dblink_get_result(conn, false) t(r text);
  return dblink_error_message(conn);
end $$;
create function pg_temp.add_members(key text, phone text) returns text language sql as $$
  select format($q$select public.add_space_members('00000000-0000-0000-0000-00000000d100',
    '[{"phone": "%s"}]', '%s')::text$q$, phone, key)
$$;
create function pg_temp.leave(key text) returns text language sql as $$
  select format($q$select public.leave_space('00000000-0000-0000-0000-00000000d100', '%s')::text$q$, key)
$$;
-- An expense of 100 paid by `payer` and split to `taker`.
create function pg_temp.expense(key text, payer text, taker text) returns text language sql as $$
  select format($q$select public.add_expense('{"space_id": "00000000-0000-0000-0000-00000000d100",
    "idempotency_key": "%s", "description": "Race", "amount_minor": 100, "split_type": "exact",
    "payers": [{"member_id": "%s", "amount_minor": 100}],
    "splits": [{"member_id": "%s", "amount_minor": 100}]}')::text$q$, key, payer, taker)
$$;
create function pg_temp.balance(member text) returns bigint language sql as $$
  select balance_minor from public.space_member_balances where member_id = member::uuid
$$;

select dblink_connect('s1', pg_temp.conninfo());
select dblink_connect('s2', pg_temp.conninfo());
create temp table s2 as select pid from dblink('s2', 'select pg_backend_pid()') t(pid int);

-- Same user, same key, same payload: the second call waits for the first, then replays it.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000d003');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000d003');
select * from dblink('s1', pg_temp.add_members('00000000-0000-0000-0000-00000000d301', '+919580000091')) t(r text);
select dblink_send_query('s2', pg_temp.add_members('00000000-0000-0000-0000-00000000d301', '+919580000091'));
select ok(pg_temp.blocked((select pid from s2)), 'keys: a concurrent replay waits on the first, uncommitted, claim');
select dblink_exec('s1', 'commit');
select is(pg_temp.outcome('s2'), 'OK', 'keys: once the first commits, the concurrent replay succeeds');
select dblink_exec('s2', 'commit');
select is((select count(*)::int from public.space_members where phone = '+919580000091'), 1,
  'keys: the concurrent replay wrote nothing');

-- Same user, same key, changed payload: the second call waits, then conflicts.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000d003');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000d003');
select * from dblink('s1', pg_temp.add_members('00000000-0000-0000-0000-00000000d302', '+919580000092')) t(r text);
select dblink_send_query('s2', pg_temp.add_members('00000000-0000-0000-0000-00000000d302', '+919580000093'));
select ok(pg_temp.blocked((select pid from s2)), 'keys: a concurrent changed payload also waits');
select dblink_exec('s1', 'commit');
select matches(pg_temp.outcome('s2'), 'already used with a different payload',
  'keys: then it gets the idempotency conflict');
select dblink_exec('s2', 'rollback');

-- Another user with the same key does not wait and does not conflict (keys are per user).
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000d003');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000d004');
select * from dblink('s1', pg_temp.add_members('00000000-0000-0000-0000-00000000d303', '+919580000094')) t(r text);
select dblink_exec('s2', $$set local lock_timeout = '2s'$$);
select is((select r from dblink('s2', pg_temp.add_members('00000000-0000-0000-0000-00000000d303', '+919580000095')) t(r text)),
  '', 'keys: another user''s concurrent call with the same key neither waits nor conflicts');
select dblink_exec('s1', 'commit');
select dblink_exec('s2', 'commit');
select is((select count(*)::int from public.space_members where phone in ('+919580000094', '+919580000095')), 2,
  'keys: both users'' calls took effect');

-- Leave first: M3 leaves (uncommitted); O1's expense naming M3 waits, then is refused.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000d003');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000d001');
select * from dblink('s1', pg_temp.leave('00000000-0000-0000-0000-00000000d311')) t(r text);
select dblink_send_query('s2', pg_temp.expense('00000000-0000-0000-0000-00000000d312',
  '00000000-0000-0000-0000-00000000d201', '00000000-0000-0000-0000-00000000d203'));
select ok(pg_temp.blocked((select pid from s2)), 'leave race: an expense naming a leaving member waits for the leave');
select dblink_exec('s1', 'commit');
select matches(pg_temp.outcome('s2'), 'must be active members', 'leave race: then it is refused');
select dblink_exec('s2', 'rollback');
select ok((select left_at is not null from public.space_members where id = '00000000-0000-0000-0000-00000000d203')
          and pg_temp.balance('00000000-0000-0000-0000-00000000d203') = 0,
  'leave race: M3 left with a zero balance');

-- Expense first: M5 pays for M4 (uncommitted); M4's leave waits, then sees the balance.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000d001');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000d004');
select * from dblink('s1', pg_temp.expense('00000000-0000-0000-0000-00000000d321',
  '00000000-0000-0000-0000-00000000d205', '00000000-0000-0000-0000-00000000d204')) t(r text);
select dblink_send_query('s2', pg_temp.leave('00000000-0000-0000-0000-00000000d322'));
select ok(pg_temp.blocked((select pid from s2)), 'leave race: a leave waits for an uncommitted expense naming the member');
select dblink_exec('s1', 'commit');
select matches(pg_temp.outcome('s2'), 'cannot leave until it is settled', 'leave race: then it is refused for the new balance');
select dblink_exec('s2', 'rollback');

-- Two owners leave at once: the second waits on the space, then is the last owner.
select pg_temp.begin_as('s1', '00000000-0000-0000-0000-00000000d001');
select pg_temp.begin_as('s2', '00000000-0000-0000-0000-00000000d002');
select * from dblink('s1', pg_temp.leave('00000000-0000-0000-0000-00000000d331')) t(r text);
select dblink_send_query('s2', pg_temp.leave('00000000-0000-0000-0000-00000000d332'));
select ok(pg_temp.blocked((select pid from s2)), 'owners: a second owner''s leave waits for the first');
select dblink_exec('s1', 'commit');
select matches(pg_temp.outcome('s2'), 'last owner', 'owners: then it is refused as the last owner');
select dblink_exec('s2', 'rollback');
select is((select count(*)::int from public.space_members
            where space_id = '00000000-0000-0000-0000-00000000d100' and role = 'owner' and left_at is null), 1,
  'owners: the space keeps one owner');

select dblink_exec('setup', $$
  begin;
  delete from public.activity where space_id = '00000000-0000-0000-0000-00000000d100';
  delete from public.expense_splits where expense_id in (select id from public.expenses where space_id = '00000000-0000-0000-0000-00000000d100');
  delete from public.expense_payers where expense_id in (select id from public.expenses where space_id = '00000000-0000-0000-0000-00000000d100');
  delete from public.expenses where space_id = '00000000-0000-0000-0000-00000000d100';
  delete from public.space_members where space_id = '00000000-0000-0000-0000-00000000d100';
  delete from public.spaces where id = '00000000-0000-0000-0000-00000000d100';
  delete from auth.users where id::text like '00000000-0000-0000-0000-00000000d00_';
  commit;
$$);
select dblink_disconnect('setup');
select dblink_disconnect('s1');
select dblink_disconnect('s2');

select * from finish();
rollback;
