-- Review probes for invite capabilities (#104): link-only decline, hash-only tokens,
-- lifecycle revocation, quotas and uniform validation.
begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

insert into auth.users (id, phone, phone_confirmed_at) values
 ('00000000-0000-0000-0000-000000010501', '919200000001', now()),
 ('00000000-0000-0000-0000-000000010502', '919200000002', now()),
 ('00000000-0000-0000-0000-000000010503', '919200000003', now()),
 ('00000000-0000-0000-0000-000000010504', '919200000004', now());
insert into public.profiles (id, phone, name) values
 ('00000000-0000-0000-0000-000000010501', '+919200000001', 'Asha'),
 ('00000000-0000-0000-0000-000000010502', '+919200000002', 'Bilal'),
 ('00000000-0000-0000-0000-000000010503', '+919200000003', 'Chitra'),
 ('00000000-0000-0000-0000-000000010504', '+919200000004', 'Dev');

insert into public.spaces (id, name, created_by) values
 ('00000000-0000-0000-0000-000000010510', 'Decline probe', '00000000-0000-0000-0000-000000010501'),
 ('00000000-0000-0000-0000-000000010520', 'Leave probe', '00000000-0000-0000-0000-000000010501'),
 ('00000000-0000-0000-0000-000000010530', 'Limit probe', '00000000-0000-0000-0000-000000010501');
insert into public.space_members (id, space_id, phone, user_id, role, accepted_at) values
 ('00000000-0000-0000-0000-000000010511', '00000000-0000-0000-0000-000000010510', '+919200000001', '00000000-0000-0000-0000-000000010501', 'owner', now()),
 ('00000000-0000-0000-0000-000000010512', '00000000-0000-0000-0000-000000010510', '+919200000002', null, 'member', null),
 ('00000000-0000-0000-0000-000000010521', '00000000-0000-0000-0000-000000010520', '+919200000001', '00000000-0000-0000-0000-000000010501', 'member', now()),
 ('00000000-0000-0000-0000-000000010522', '00000000-0000-0000-0000-000000010520', '+919200000003', '00000000-0000-0000-0000-000000010503', 'owner', now()),
 ('00000000-0000-0000-0000-000000010523', '00000000-0000-0000-0000-000000010520', '+919200000002', null, 'member', null),
 ('00000000-0000-0000-0000-000000010531', '00000000-0000-0000-0000-000000010530', '+919200000001', '00000000-0000-0000-0000-000000010501', 'owner', now()),
 ('00000000-0000-0000-0000-000000010532', '00000000-0000-0000-0000-000000010530', '+919200000005', null, 'member', null);
insert into public.loans (id, lender_phone, borrower_phone, lender_id, borrower_id, principal_minor,
                          schedule_type, created_by, lender_accepted_at)
values ('00000000-0000-0000-0000-000000010540', '+919200000001', '+919200000002',
        '00000000-0000-0000-0000-000000010501', null,
        10000, 'flexible', '00000000-0000-0000-0000-000000010501', now());

create function pg_temp.login(u text) returns text language sql as $$
 select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true)
$$;
create function pg_temp.issue_space(member_id uuid, key uuid) returns text language sql as $$
 select public.issue_invite('space', member_id, key)
$$;
create function pg_temp.issue_loan(key uuid) returns text language sql as $$
 select public.issue_invite('loan', '00000000-0000-0000-0000-000000010540', key)
$$;
create function pg_temp.call_decline(token text, key uuid) returns void language plpgsql as $$
begin
  if to_regprocedure('public.decline_invite(text,uuid)') is not null then
    execute 'select public.decline_invite($1, $2)' using token, key;
  else
    execute 'select public.decline_invite($1)' using token;
  end if;
end $$;
create function pg_temp.hint_for(statement text) returns text language plpgsql as $$
declare hint text;
begin
  begin
    execute statement;
    raise exception 'probe_succeeded';
  exception when others then
    if sqlerrm = 'probe_succeeded' then return null; end if;
    get stacked diagnostics hint = PG_EXCEPTION_HINT;
    return hint;
  end;
end $$;
create function pg_temp.set_quota(who uuid, action text, attempts int) returns void language plpgsql as $$
begin
  if to_regclass('private.invite_rate_limits') is not null then
    execute 'insert into private.invite_rate_limits (user_id, action, window_started_at, attempts)
             values ($1, $2, now(), $3)
             on conflict (user_id, action) do update
             set window_started_at = excluded.window_started_at, attempts = excluded.attempts'
      using who, action, attempts;
  end if;
end $$;
create function pg_temp.clear_quota(action_name text) returns void language plpgsql as $$
begin
  if to_regclass('private.invite_rate_limits') is not null then
    execute 'delete from private.invite_rate_limits where action = $1' using action_name;
  end if;
end $$;
create function pg_temp.quota_attempts() returns int language plpgsql as $$
declare answer int := 0;
begin
  if to_regclass('private.invite_rate_limits') is not null then
    execute 'select coalesce(sum(attempts), 0)::int from private.invite_rate_limits' into answer;
  end if;
  return answer;
end $$;
create function pg_temp.was_revoked(token text) returns boolean language plpgsql as $$
declare answer boolean;
begin
  if exists (select from information_schema.columns
              where table_schema = 'private' and table_name = 'invite_links' and column_name = 'revoked_at') then
    execute 'select revoked_at is not null from private.invite_links
              where token_hash = sha256(convert_to($1, ''UTF8''))' into answer using token;
  end if;
  return coalesce(answer, false);
end $$;
grant execute on all functions in schema pg_temp to public;

select hasnt_column('private', 'invite_links', 'nonce', 'no stored nonce can rebuild a bearer token');
select hasnt_function('private', 'invite_token', array['uuid', 'uuid', 'uuid'],
 'no database function rebuilds a bearer token from stored columns');
select has_function('private', 'valid_invite_token', array['text'],
 'one server validator rejects malformed tokens before lookup');
select ok(not has_table_privilege('authenticated', 'private.invite_rate_limits', 'select'),
 'authenticated callers cannot read or alter invite quotas');
select ok(not has_function_privilege('authenticated', 'private.consume_invite_rate_limit(uuid,text)', 'execute'),
 'authenticated callers cannot bypass the quota helper');
select is((select count(*)::int from pg_proc where proname like '%invite%'
  and pronamespace = 'private'::regnamespace
  and not coalesce(proconfig @> array['search_path=""'], false)), 0,
 'all private invite helpers fix search_path empty');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010501');
create temporary table issued(label text primary key, token text not null);
grant select, insert, update, delete on issued to public;
insert into issued values ('decline', pg_temp.issue_space(
 '00000000-0000-0000-0000-000000010512', '00000000-0000-4000-8000-000000010551'));
insert into issued values ('leave', pg_temp.issue_space(
 '00000000-0000-0000-0000-000000010523', '00000000-0000-4000-8000-000000010552'));
insert into issued values ('loan', pg_temp.issue_loan('00000000-0000-4000-8000-000000010553'));
insert into issued values ('rotated-old', pg_temp.issue_space(
 '00000000-0000-0000-0000-000000010532', '00000000-0000-4000-8000-000000010554'));

reset role; set local role anon;
select lives_ok(format('select pg_temp.call_decline(%L, %L)',
 (select token from issued where label = 'decline'), '00000000-0000-4000-8000-000000010561'),
 'an anonymous holder may invalidate only this link');
reset role;
select ok((select accepted_at is null and rejected_at is null and left_at is null
            from public.space_members where id = '00000000-0000-0000-0000-000000010512'),
 'anonymous decline leaves the real invitee claim pending');
select ok(exists(select from public.activity where space_id = '00000000-0000-0000-0000-000000010510'
                  and action = 'rejected' and after ->> 'link_only' = 'true'),
 'anonymous decline tells the inviter that the link reached the wrong person');
set local role anon;
select lives_ok(format('select pg_temp.call_decline(%L, %L)',
 (select token from issued where label = 'decline'), '00000000-0000-4000-8000-000000010561'),
 'same-key decline replay is harmless');
select is(pg_temp.hint_for(format('select pg_temp.call_decline(%L, %L)',
 (select token from issued where label = 'decline'), '00000000-0000-4000-8000-000000010562')),
 'invite_unavailable', 'a different-key decline replay is uniformly unavailable');
reset role; set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010502');
select lives_ok($$select public.accept_claim('space_member', '00000000-0000-0000-0000-000000010512')$$,
 'the verified target can still accept after an anonymous decline');
select ok((select accepted_at is not null from public.space_members
            where id = '00000000-0000-0000-0000-000000010512'),
 'the target claim becomes accepted');

reset role; set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010501');
insert into issued values ('rotated-new', pg_temp.issue_space(
 '00000000-0000-0000-0000-000000010532', '00000000-0000-4000-8000-000000010554'));
select isnt((select token from issued where label = 'rotated-old'),
             (select token from issued where label = 'rotated-new'),
 'same-key issue replay rotates to a fresh random token');
reset role; set local role anon;
select is((select count(*)::int from public.inspect_invite(
 (select token from issued where label = 'rotated-old'))), 0, 'rotation invalidates the old link');
select is((select count(*)::int from public.inspect_invite(
 (select token from issued where label = 'rotated-new'))), 1, 'rotation leaves the new link live');
reset role;
select ok((select i.token_hash = sha256(convert_to(x.token, 'UTF8'))
            from private.invite_links i cross join issued x
           where x.label = 'rotated-new' and i.kind = 'space'
             and i.subject_id = '00000000-0000-0000-0000-000000010532'),
 'the row stores only the active token digest');
select ok(not exists(select from private.invite_links i cross join issued x
                      where row_to_json(i)::text like '%' || x.token || '%'),
 'no invite row contains a plaintext bearer token');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010501');
select pg_temp.issue_space('00000000-0000-0000-0000-000000010532', '00000000-0000-4000-8000-000000010571');
select pg_temp.issue_space('00000000-0000-0000-0000-000000010532', '00000000-0000-4000-8000-000000010572');
select pg_temp.issue_space('00000000-0000-0000-0000-000000010532', '00000000-0000-4000-8000-000000010573');
select pg_temp.issue_space('00000000-0000-0000-0000-000000010532', '00000000-0000-4000-8000-000000010574');
select is(pg_temp.hint_for($$select pg_temp.issue_space('00000000-0000-0000-0000-000000010532',
 '00000000-0000-4000-8000-000000010575')$$), 'invite_target_limit',
 'a sixth live link for one target is refused');
reset role;
select is((select count(*)::int from private.invite_links where kind = 'space'
            and subject_id = '00000000-0000-0000-0000-000000010532'
            and expires_at > now() and redeemed_at is null and declined_at is null), 5,
 'at most five links remain live for a target');

select pg_temp.set_quota('00000000-0000-0000-0000-000000010501', 'issue', 20);
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010501');
select is(pg_temp.hint_for($$select pg_temp.issue_space('00000000-0000-0000-0000-000000010523',
 '00000000-0000-4000-8000-000000010576')$$), 'invite_rate_limited',
 'issue is throttled per verified user');
reset role; select pg_temp.clear_quota('issue');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010503');
select is(pg_temp.hint_for(format('select public.redeem_invite(%L, %L)',
 (select token from issued where label = 'loan'), '00000000-0000-4000-8000-000000010577')),
 'wrong_phone', 'wrong verified phone keeps its distinct plain-copy hint');
reset role;
select pg_temp.set_quota('00000000-0000-0000-0000-000000010502', 'redeem', 20);
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010502');
select is(pg_temp.hint_for(format('select public.redeem_invite(%L, %L)',
 (select token from issued where label = 'loan'), '00000000-0000-4000-8000-000000010578')),
 'invite_rate_limited', 'redeem is throttled per verified user');
reset role; select pg_temp.clear_quota('redeem');

set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010501');
select lives_ok($$select public.leave_space('00000000-0000-0000-0000-000000010520',
 '00000000-0000-4000-8000-000000010579')$$, 'issuer leaves a space with another owner');
reset role;
select ok(pg_temp.was_revoked((select token from issued where label = 'leave')),
 'leaving explicitly revokes the issuer space link');
set local role anon;
select is((select count(*)::int from public.inspect_invite((select token from issued where label = 'leave'))),
 0, 'a departed issuer space link reveals nothing');
reset role;
update public.loans set lender_id = null, lender_accepted_at = null
 where id = '00000000-0000-0000-0000-000000010540';
select ok(pg_temp.was_revoked((select token from issued where label = 'loan')),
 'losing the loan explicitly revokes the issuer link');
set local role anon;
select is((select count(*)::int from public.inspect_invite((select token from issued where label = 'loan'))),
 0, 'a former loan party link reveals nothing');

select is((select count(*)::int from public.inspect_invite('xyz')), 0,
 'a malformed token is rejected before lookup');
reset role; set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010502');
select is(pg_temp.hint_for($$select public.redeem_invite('xyz',
 '00000000-0000-4000-8000-000000010580')$$), 'invite_unavailable',
 'malformed redeem keeps the uniform unavailable hint');
set local role anon;
select is(pg_temp.hint_for(format('select pg_temp.call_decline(%L, %L)', repeat('a', 4096),
 '00000000-0000-4000-8000-000000010581')), 'invite_unavailable',
 'oversized decline is rejected before lookup');
reset role;
select is(pg_temp.quota_attempts(), 0,
 'invalid tokens do not consume or bypass a user quota row');

select * from finish();
rollback;
