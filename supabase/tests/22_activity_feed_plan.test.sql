-- Activity feed cost (#91, PR #101 review): the reviewer's adversarial fixture. 120,000 activity rows:
-- 20,000 visible to C across C's 500 spaces, then 100,000 newer rows in 500 spaces C is not in. The
-- old view read activity newest first and filtered every row by RLS: 1.2M buffers and 9 s for the
-- first page. The feed now starts from C's memberships, so its cost follows C's spaces, not the
-- table: the bound below is over 10x the measured ~17k buffers and a sixth of the old 1.2M.
begin;
create extension if not exists pgtap with schema extensions;

select plan(4);

-- 120,000 activity rows: 20,000 visible to C across C's 500 spaces (older), then 100,000 newer rows in
-- 500 other spaces. Run inside a transaction that rolls back.
insert into auth.users (id, phone, phone_confirmed_at) values
  ('00000000-0000-0000-0000-00000000c001', '919120000001', now()),
  ('00000000-0000-0000-0000-00000000c002', '919120000002', now());
insert into public.profiles (id, phone, name) values
  ('00000000-0000-0000-0000-00000000c001', '+919120000001', 'Caller'),
  ('00000000-0000-0000-0000-00000000c002', '+919120000002', 'Other');
insert into public.spaces (id, name, kind, created_by)
select ('00000000-0000-0000-0001-' || lpad(to_hex(g), 12, '0'))::uuid, 'Space ' || g, 'flat',
       case when g <= 500 then '00000000-0000-0000-0000-00000000c001'::uuid else '00000000-0000-0000-0000-00000000c002'::uuid end
  from generate_series(1, 1000) g;
insert into public.space_members (space_id, phone, user_id, role, accepted_at)
select ('00000000-0000-0000-0001-' || lpad(to_hex(g), 12, '0'))::uuid,
       case when g <= 500 then '+919120000001' else '+919120000002' end,
       case when g <= 500 then '00000000-0000-0000-0000-00000000c001'::uuid else '00000000-0000-0000-0000-00000000c002'::uuid end,
       'owner', now()
  from generate_series(1, 1000) g;
insert into public.activity (space_id, action, created_at)
select ('00000000-0000-0000-0001-' || lpad(to_hex(1 + g % 500), 12, '0'))::uuid, 'created',
       timestamptz '2026-01-01' + g * interval '1 second'
  from generate_series(1, 20000) g;
insert into public.activity (space_id, action, created_at)
select ('00000000-0000-0000-0001-' || lpad(to_hex(501 + g % 500), 12, '0'))::uuid, 'created',
       timestamptz '2026-06-01' + g * interval '1 second'
  from generate_series(1, 100000) g;
analyze public.activity; analyze public.space_members; analyze public.spaces; analyze public.loans;

create function pg_temp.plan() returns jsonb language plpgsql as $$
declare
  j jsonb;
begin
  execute 'explain (analyze, buffers, format json) select * from public.activity_feed()' into j;
  return j -> 0;
end $$;
grant execute on all functions in schema pg_temp to public;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000c001", "role": "authenticated"}', true);

select is((select count(*)::int from public.activity_feed()), 30, 'C gets a full first page');
select ok((select bool_and(f.space_id::text <= '00000000-0000-0000-0001-0000000001f4') from public.activity_feed() f),
  'every row is from one of C''s 500 spaces, none from the 100,000 newer foreign rows');
select is((select max(created_at) from public.activity_feed()), timestamptz '2026-01-01' + 20000 * interval '1 second',
  'the page starts at C''s newest row');
select cmp_ok(
  (select ((p -> 'Plan' ->> 'Shared Hit Blocks')::int + (p -> 'Plan' ->> 'Shared Read Blocks')::int) from pg_temp.plan() p),
  '<', 200000, 'the first page reads a bounded number of buffers, not the whole table');

select * from finish();
rollback;
