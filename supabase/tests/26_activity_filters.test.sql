-- Activity filters, unread and 'Question this' (#109): activity_feed's filters, mark_activity_seen
-- and question_activity.
-- Callers: A owns S1 and S2; B is an accepted member of S1; D is a member of S1 who later leaves;
-- P has an account but is still a pending member of S1; O is a member of S2 only; anon has no
-- session. A spends in both spaces, edits one expense in each, and lends B L1.
begin;
create extension if not exists pgtap with schema extensions;

select plan(46);

insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-000000009301', '919930000001', now()),
  ('00000000-0000-0000-0000-000000009302', '919930000002', now()),
  ('00000000-0000-0000-0000-000000009303', '919930000003', now()),
  ('00000000-0000-0000-0000-000000009304', '919930000004', now()),
  ('00000000-0000-0000-0000-000000009305', '919930000005', now());
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-000000009301', '+919930000001', 'Asha'),
  ('00000000-0000-0000-0000-000000009302', '+919930000002', 'Bilal'),
  ('00000000-0000-0000-0000-000000009303', '+919930000003', 'Dev'),
  ('00000000-0000-0000-0000-000000009304', '+919930000004', 'Priya'),
  ('00000000-0000-0000-0000-000000009305', '+919930000005', 'Omar');
insert into public.spaces (id, name, kind, created_by) values
  ('00000000-0000-0000-0000-000000009310', 'Flat 93', 'flat', '00000000-0000-0000-0000-000000009301'),
  ('00000000-0000-0000-0000-000000009311', 'Trip 93', 'trip', '00000000-0000-0000-0000-000000009301');
insert into public.space_members (id, space_id, phone, user_id, role) values
  ('00000000-0000-0000-0000-000000009321', '00000000-0000-0000-0000-000000009310', '+919930000001', '00000000-0000-0000-0000-000000009301', 'owner'),
  ('00000000-0000-0000-0000-000000009322', '00000000-0000-0000-0000-000000009310', '+919930000002', '00000000-0000-0000-0000-000000009302', 'member'),
  ('00000000-0000-0000-0000-000000009323', '00000000-0000-0000-0000-000000009310', '+919930000003', '00000000-0000-0000-0000-000000009303', 'member'),
  ('00000000-0000-0000-0000-000000009324', '00000000-0000-0000-0000-000000009310', '+919930000004', null, 'member'),
  ('00000000-0000-0000-0000-000000009325', '00000000-0000-0000-0000-000000009311', '+919930000001', '00000000-0000-0000-0000-000000009301', 'owner'),
  ('00000000-0000-0000-0000-000000009326', '00000000-0000-0000-0000-000000009311', '+919930000005', '00000000-0000-0000-0000-000000009305', 'member');

create function pg_temp.login(u text) returns text language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true)
$$;
-- A pays [what] alone in [space] as [member]; the key's last two digits are [n].
create function pg_temp.spend(space text, member text, n int, what text) returns uuid language sql as $$
  select public.add_expense(jsonb_build_object(
    'space_id', space, 'idempotency_key', '00000000-0000-0000-0000-0000000093' || lpad(n::text, 2, '0'),
    'description', what, 'amount_minor', 1000,
    'payers', jsonb_build_array(jsonb_build_object('member_id', member, 'amount_minor', 1000)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', member))))
$$;
create function pg_temp.edit(space text, member text, n int, expense uuid, what text) returns void language sql as $$
  select public.update_expense(jsonb_build_object(
    'expense_id', expense, 'idempotency_key', '00000000-0000-0000-0000-0000000093' || lpad(n::text, 2, '0'),
    'description', what, 'amount_minor', 2000,
    'payers', jsonb_build_array(jsonb_build_object('member_id', member, 'amount_minor', 2000)),
    'splits', jsonb_build_array(jsonb_build_object('member_id', member))))
$$;
-- The caller's feed under a filter as kind:action, oldest first.
create function pg_temp.feed(space uuid default null, loans boolean default false) returns text language sql as $$
  select string_agg(kind || ':' || action, ' ' order by id) from public.activity_feed(null, null, 100, space, loans)
$$;
-- Every id of the caller's filtered feed, read two rows at a time by the keyset cursor.
create function pg_temp.paged(space uuid default null, loans boolean default false) returns bigint[]
language plpgsql as $$
declare
  ids bigint[] := '{}'; at timestamptz; last bigint; r record; n int;
begin
  loop
    n := 0;
    for r in select f.id, f.created_at from public.activity_feed(at, last, 2, space, loans) f loop
      ids := ids || r.id; at := r.created_at; last := r.id; n := n + 1;
    end loop;
    exit when n < 2;
  end loop;
  return ids;
end $$;
-- The caller's view of the notes on S1's edit, as name:by_me:note in order.
create function pg_temp.notes() returns text language sql as $$
  select string_agg(concat_ws(':', q ->> 'name', q ->> 'by_me', q ->> 'note'), ' | ')
    from public.activity_feed() f, jsonb_array_elements(f.questions) q
   where f.space_id = '00000000-0000-0000-0000-000000009310'
$$;
grant execute on all functions in schema pg_temp to public;

-- Hardening.
select ok(not has_function_privilege('anon', 'public.activity_feed(timestamptz, bigint, int, uuid, boolean)', 'execute')
          and not has_function_privilege('anon', 'public.mark_activity_seen(timestamptz)', 'execute')
          and not has_function_privilege('anon', 'public.question_activity(bigint, text)', 'execute')
          and has_function_privilege('authenticated', 'public.mark_activity_seen(timestamptz)', 'execute')
          and has_function_privilege('authenticated', 'public.question_activity(bigint, text)', 'execute'),
  'the feed, mark_activity_seen and question_activity are for authenticated only');
select ok(not has_table_privilege('authenticated', 'private.activity_questions', 'select')
          and not has_table_privilege('authenticated', 'private.activity_questions', 'insert')
          and not has_table_privilege('anon', 'private.activity_questions', 'select'),
  'notes are out of the API''s reach: read through the feed, written through the RPC');
select ok(has_table_privilege('authenticated', 'public.activity_seen', 'select')
          and not has_table_privilege('authenticated', 'public.activity_seen', 'insert')
          and not has_table_privilege('authenticated', 'public.activity_seen', 'update')
          and not has_table_privilege('authenticated', 'public.activity_seen', 'delete')
          and not has_table_privilege('anon', 'public.activity_seen', 'select')
          and (select relrowsecurity from pg_class where oid = 'public.activity_seen'::regclass),
  'activity_seen is read-only under RLS; only mark_activity_seen writes it');
select is((select count(*)::int from pg_proc where proname = 'activity_feed' and pronamespace = 'public'::regnamespace), 1,
  'activity_feed has one signature, so a call naming only the old arguments is not ambiguous');

set local role authenticated;

-- Fixtures, through the RPCs so activity is written as in the app. The two spaces and the loan
-- interleave, so a filter has rows to skip on every page.
select pg_temp.login('00000000-0000-0000-0000-000000009301');
create temp table e as
  select pg_temp.spend('00000000-0000-0000-0000-000000009310', '00000000-0000-0000-0000-000000009321', 1, 'Rent') as s1,
         pg_temp.spend('00000000-0000-0000-0000-000000009311', '00000000-0000-0000-0000-000000009325', 2, 'Cab') as s2;
select lives_ok($$select pg_temp.edit('00000000-0000-0000-0000-000000009310', '00000000-0000-0000-0000-000000009321', 3,
    (select s1 from e), 'Rent and water')$$, 'fixture: A edits Rent in S1');
select lives_ok($$select public.create_loan('{"idempotency_key": "00000000-0000-0000-0000-000000009a11",
    "direction": "lent", "counterparty_phone": "+919930000002", "principal_minor": 50000}')$$,
  'fixture: A lends B 50000 (L1)');
select lives_ok($$select pg_temp.edit('00000000-0000-0000-0000-000000009311', '00000000-0000-0000-0000-000000009325', 4,
    (select s2 from e), 'Cab and tolls')$$, 'fixture: A edits Cab in S2');
select lives_ok($$select pg_temp.spend('00000000-0000-0000-0000-000000009310', '00000000-0000-0000-0000-000000009321', 5, 'Milk'),
                         pg_temp.spend('00000000-0000-0000-0000-000000009311', '00000000-0000-0000-0000-000000009325', 6, 'Tea'),
                         pg_temp.spend('00000000-0000-0000-0000-000000009310', '00000000-0000-0000-0000-000000009321', 7, 'Eggs')$$,
  'fixture: A spends three more times, S1, S2, S1');
-- The two 'edited' rows, kept here because only members can read activity.
create temp table x as
  select (select id from public.activity where space_id = '00000000-0000-0000-0000-000000009310' and action = 'edited') as s1,
         (select id from public.activity where space_id = '00000000-0000-0000-0000-000000009311' and action = 'edited') as s2,
         (select id from public.activity where space_id = '00000000-0000-0000-0000-000000009310' and action = 'created' limit 1) as made,
         (select id from public.activity where loan_id is not null limit 1) as loan;
select pg_temp.login('00000000-0000-0000-0000-000000009302');
select lives_ok($$select public.accept_claim('loan', '00000000-0000-0000-0000-000000009a11')$$, 'fixture: B accepts L1');
select lives_ok($$select public.record_repayment('{"loan_id": "00000000-0000-0000-0000-000000009a11",
    "idempotency_key": "00000000-0000-0000-0000-000000009a13", "amount_minor": 1000}')$$,
  'fixture: B records repaying A 1000');

-- Filters: A is in both spaces and the loan.
select pg_temp.login('00000000-0000-0000-0000-000000009301');
select is(pg_temp.feed(),
  'expense:created expense:created expense:edited loan:created expense:edited expense:created expense:created expense:created repayment:recorded',
  'no filter: A sees both spaces and the loan');
select is(pg_temp.feed('00000000-0000-0000-0000-000000009310'),
  'expense:created expense:edited expense:created expense:created', 'space filter: only S1''s rows');
select ok((select bool_and(space_id = '00000000-0000-0000-0000-000000009311') and count(*) = 3
             from public.activity_feed(null, null, 100, '00000000-0000-0000-0000-000000009311')),
  'space filter: only S2''s rows');
select is(pg_temp.feed(null, true), 'loan:created repayment:recorded', 'loans filter: only loan rows');
select is(pg_temp.feed('00000000-0000-0000-0000-000000009310', true), null, 'a space and loans together match nothing');
select is((select array_agg(id) from public.activity_feed(null, null, 100, null, null)),
          (select array_agg(id) from public.activity_feed()),
  'a null loans flag means no filter');

-- Filtered paging keeps the keyset contract: every matching row once, in the unfiltered order.
select is(pg_temp.paged(), (select array_agg(id) from public.activity_feed(null, null, 100)),
  'paging, no filter: two at a time reads the whole feed once, in order');
select is(pg_temp.paged('00000000-0000-0000-0000-000000009310'),
          (select array_agg(id) from public.activity_feed(null, null, 100) where space_id = '00000000-0000-0000-0000-000000009310'),
  'paging, space filter: S1''s rows once each, in the feed''s order');
select is(pg_temp.paged('00000000-0000-0000-0000-000000009311'),
          (select array_agg(id) from public.activity_feed(null, null, 100) where space_id = '00000000-0000-0000-0000-000000009311'),
  'paging, space filter: S2''s rows once each, in the feed''s order');
select is(pg_temp.paged(null, true),
          (select array_agg(id) from public.activity_feed(null, null, 100) where loan_id is not null),
  'paging, loans filter: loan rows once each, in the feed''s order');
select is((select count(*)::int from public.activity_feed(null, null, 1, '00000000-0000-0000-0000-000000009310')), 1,
  'paging: the limit applies after the filter');

-- A filter never widens what the caller sees.
select pg_temp.login('00000000-0000-0000-0000-000000009302');
select is(pg_temp.feed('00000000-0000-0000-0000-000000009311'), null, 'space filter: B, not in S2, gets nothing for S2');
select is(pg_temp.feed(null, true), 'loan:created repayment:recorded', 'loans filter: B sees L1');
select pg_temp.login('00000000-0000-0000-0000-000000009304');
select is(pg_temp.feed('00000000-0000-0000-0000-000000009310'), null, 'space filter: P, a pending member, gets nothing for S1');
select pg_temp.login('00000000-0000-0000-0000-000000009305');
select is(pg_temp.feed('00000000-0000-0000-0000-000000009310'), null, 'space filter: O, an outsider to S1, gets nothing for S1');

-- 'Question this': who may ask.
select pg_temp.login('00000000-0000-0000-0000-000000009302');
select lives_ok(format('select public.question_activity(%s, %L)', (select s1 from x),
    '  Why did this go up?  '), 'note: B, an accepted member, questions A''s edit');
select throws_ok(format('select public.question_activity(%s, %L)', (select s2 from x), 'Why?'),
  '42501', null, 'note: B cannot question an edit in a space B is not in');
select throws_ok(format('select public.question_activity(%s, %L)', (select made from x), 'Why?'),
  '42501', null, 'note: only an edit can be questioned');
select throws_ok(format('select public.question_activity(%s, %L)', (select loan from x), 'Why?'),
  '42501', null, 'note: a loan row cannot be questioned');
select throws_ok($$select public.question_activity(-1, 'Why?')$$, '42501', null, 'note: a missing row answers as a forbidden one');
select throws_ok(format('select public.question_activity(%s, %L)', (select s1 from x), '   '),
  '22023', null, 'note: a blank note is refused');
select throws_ok(format('select public.question_activity(%s, %L)', (select s1 from x), repeat('a', 281)),
  '22023', null, 'note: more than 280 characters is refused');
select pg_temp.login('00000000-0000-0000-0000-000000009301');
select throws_ok(format('select public.question_activity(%s, %L)', (select s1 from x), 'Why?'),
  '42501', null, 'note: the editor cannot question their own edit');
select pg_temp.login('00000000-0000-0000-0000-000000009304');
select throws_ok(format('select public.question_activity(%s, %L)', (select s1 from x), 'Why?'),
  '42501', null, 'note: P, a pending member, cannot question');
select pg_temp.login('00000000-0000-0000-0000-000000009305');
select throws_ok(format('select public.question_activity(%s, %L)', (select s1 from x), 'Why?'),
  '42501', null, 'note: O, a member of another space only, cannot question');
select pg_temp.login('00000000-0000-0000-0000-000000009303');
select lives_ok(format('select public.question_activity(%s, %L)', (select s1 from x),
    'Call +91 98000 00009 or 9800000010, ref 12345 ' || repeat('a', 234)),
  'note: D, a member, asks too, at the 280 character cap');

-- Who sees the notes: members of that space, on that row.
select is(pg_temp.notes(), 'Bilal:false:Why did this go up? | Dev:true:Call •••• or ••••, ref 12345 ' || repeat('a', 234),
  'note: trimmed, phone numbers redacted, shown oldest first with who asked');
select pg_temp.login('00000000-0000-0000-0000-000000009302');
select lives_ok(format('select public.question_activity(%s, %L)', (select s1 from x), 'Was the water extra?'),
  'note: B asks again');
select pg_temp.login('00000000-0000-0000-0000-000000009301');
select ok(pg_temp.notes() like 'Bilal:false:Was the water extra? | Dev:false:Call •••• or %',
  'note: the editor sees them; asking again replaced B''s note');
select pg_temp.login('00000000-0000-0000-0000-000000009305');
select ok((select count(*) = 3 and bool_and(questions is null) from public.activity_feed()),
  'note: O sees S2''s rows and no note from S1');
reset role;
update public.space_members set left_at = now() where id = '00000000-0000-0000-0000-000000009323';
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000009303');
select ok((select count(*) = 0 from public.activity_feed())
          and (select count(*) = 0 from public.activity_feed(null, null, 100, '00000000-0000-0000-0000-000000009310')),
  'note: D, once gone, sees neither the row nor any note');
select throws_ok(format('select public.question_activity(%s, %L)', (select s1 from x), 'Why?'),
  '42501', null, 'note: D, once gone, cannot question');

-- Unread: the cursor is the caller's own and only moves forward.
select pg_temp.login('00000000-0000-0000-0000-000000009301');
select public.mark_activity_seen(now() - interval '1 hour');
select public.mark_activity_seen(now() - interval '2 hours');
select is((select seen_at from public.activity_seen), now() - interval '1 hour', 'seen: an older time does not move the cursor back');
select public.mark_activity_seen(now() + interval '1 day');
select is((select seen_at from public.activity_seen), now(), 'seen: a time in the future is held to now');
select pg_temp.login('00000000-0000-0000-0000-000000009302');
select is((select count(*)::int from public.activity_seen), 0, 'seen: B cannot read A''s cursor');
reset role;
set local role anon;
select throws_ok('select public.mark_activity_seen(now())', '42501', null, 'seen: anon cannot mark');

select * from finish();
rollback;
