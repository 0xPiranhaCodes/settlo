-- Invite capabilities (#104): minimal anonymous copy, verified-phone redemption, expiry and reuse.
begin;
create extension if not exists pgtap with schema extensions;
select plan(32);

insert into auth.users (id, phone, phone_confirmed_at) values
 ('00000000-0000-0000-0000-000000010401', '919100000001', now()),
 ('00000000-0000-0000-0000-000000010402', '919100000002', now()),
 ('00000000-0000-0000-0000-000000010403', '919100000003', now()),
 ('00000000-0000-0000-0000-000000010404', '919100000004', null);
insert into public.profiles (id, phone, name) values
 ('00000000-0000-0000-0000-000000010401', '+919100000001', 'Asha'),
 ('00000000-0000-0000-0000-000000010402', '+919100000002', 'Bilal'),
 ('00000000-0000-0000-0000-000000010403', '+919100000003', 'Omar');
insert into public.spaces (id, name, created_by) values
 ('00000000-0000-0000-0000-000000010410', 'Flat 402', '00000000-0000-0000-0000-000000010401');
insert into public.space_members (id, space_id, phone, user_id, role, accepted_at) values
 ('00000000-0000-0000-0000-000000010411', '00000000-0000-0000-0000-000000010410', '+919100000001', '00000000-0000-0000-0000-000000010401', 'owner', now()),
 ('00000000-0000-0000-0000-000000010412', '00000000-0000-0000-0000-000000010410', '+919100000002', null, 'member', null);
insert into public.loans (id, lender_phone, borrower_phone, lender_id, borrower_id, principal_minor,
                          schedule_type, created_by, lender_accepted_at)
values ('00000000-0000-0000-0000-000000010420', '+919100000001', '+919100000002',
        '00000000-0000-0000-0000-000000010401', null,
        10000, 'flexible', '00000000-0000-0000-0000-000000010401', now());

create function pg_temp.login(u text) returns text language sql as $$
 select set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true)
$$;
create function pg_temp.issue_space(k uuid) returns text language sql as $$
 select public.issue_invite('space', '00000000-0000-0000-0000-000000010412', k)
$$;
create function pg_temp.issue_loan(k uuid) returns text language sql as $$
 select public.issue_invite('loan', '00000000-0000-0000-0000-000000010420', k)
$$;
grant execute on all functions in schema pg_temp to public;

select ok(not has_table_privilege('authenticated', 'private.invite_links', 'select'), 'invite rows are private');
select ok(not has_function_privilege('anon', 'public.issue_invite(public.invite_kind,uuid,uuid)', 'execute'), 'anon cannot issue');
select ok(has_function_privilege('anon', 'public.inspect_invite(text)', 'execute'), 'anon may inspect the minimal copy');
select ok(has_function_privilege('anon', 'public.decline_invite(text,uuid)', 'execute'), 'anon may decline by capability');
select is((select count(*)::int from pg_proc where proname like '%invite%' and pronamespace = 'public'::regnamespace
  and not coalesce(proconfig @> array['search_path=""'], false)), 0, 'all invite RPCs fix search_path empty');

set local role anon;
select throws_ok($$select public.issue_invite('space', '00000000-0000-0000-0000-000000010412',
 '00000000-0000-4000-8000-000000010431')$$, '42501', null, 'anon cannot issue');
reset role; set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010403');
select throws_ok($$select pg_temp.issue_space('00000000-0000-4000-8000-000000010431')$$,
 '42501', null, 'a space outsider cannot issue');
select throws_ok($$select pg_temp.issue_loan('00000000-0000-4000-8000-000000010432')$$,
 '42501', null, 'a loan outsider cannot issue');

select pg_temp.login('00000000-0000-0000-0000-000000010401');
create temporary table issued(token text);
grant select, insert, delete on issued to public;
insert into issued select pg_temp.issue_space('00000000-0000-4000-8000-000000010433');
select is(length(token), 64, 'the server issues a 256-bit hex token') from issued;
select isnt(pg_temp.issue_space('00000000-0000-4000-8000-000000010433'), (select token from issued),
 'same-key same-payload issue replay rotates the bearer token');
update issued set token = pg_temp.issue_space('00000000-0000-4000-8000-000000010433');
select throws_ok($$select pg_temp.issue_loan('00000000-0000-4000-8000-000000010433')$$,
 'PT409', null, 'same issue key with another payload conflicts');
reset role;
select is((select count(*)::int from private.invite_links), 1, 'issue replay writes one row');
select ok(not exists(select from private.invite_links i, issued x where i.token_hash = convert_to(x.token, 'UTF8')),
 'the table does not store the plaintext token');
select ok((select token_hash = sha256(convert_to(token, 'UTF8')) from private.invite_links, issued),
 'the table stores the SHA-256 token digest');
select is((select expires_at::date - created_at::date from private.invite_links), 14, 'an invite expires in 14 days');

set local role anon;
select is((select inviter_name from public.inspect_invite((select token from issued))), 'Asha', 'anonymous copy names the inviter');
select is((select subject_name from public.inspect_invite((select token from issued))), 'Flat 402', 'anonymous copy names the space');
select is((select masked_phone from public.inspect_invite((select token from issued))), '+91910•••••02', 'anonymous copy masks the target phone');
select is((select count(*)::int from public.inspect_invite('not-a-token')), 0, 'an invalid token reveals nothing');
select throws_ok(format('select public.redeem_invite(%L, %L)', (select token from issued),
 '00000000-0000-4000-8000-000000010441'), '42501', null, 'anon cannot redeem');

reset role; set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010403');
select throws_ok(format('select public.redeem_invite(%L, %L)', (select token from issued),
 '00000000-0000-4000-8000-000000010442'), '42501', null, 'the wrong verified phone cannot redeem');
select pg_temp.login('00000000-0000-0000-0000-000000010402');
select lives_ok(format('select public.redeem_invite(%L, %L)', (select token from issued),
 '00000000-0000-4000-8000-000000010443'), 'the target phone redeems');
select ok((select accepted_at is not null from public.space_members where id = '00000000-0000-0000-0000-000000010412'),
 'redemption accepts the targeted claim');
select lives_ok(format('select public.redeem_invite(%L, %L)', (select token from issued),
 '00000000-0000-4000-8000-000000010443'), 'same-key redemption replay is harmless');
select throws_ok(format('select public.redeem_invite(%L, %L)', (select token from issued),
 '00000000-0000-4000-8000-000000010444'), '22023', null, 'a used token cannot be redeemed again');
select is((select count(*)::int from public.inspect_invite((select token from issued))), 0, 'a used token no longer reveals copy');

reset role; set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010401');
truncate issued; insert into issued select pg_temp.issue_loan('00000000-0000-4000-8000-000000010434');
reset role; set local role anon;
select is((select kind::text from public.inspect_invite((select token from issued))), 'loan',
 'a loan capability reveals only loan Join copy');
select lives_ok(format('select public.decline_invite(%L, %L)', (select token from issued),
 '00000000-0000-4000-8000-000000010445'),
 'an anonymous bearer may say this is not them');
reset role;
select ok((select borrower_rejected_at is null and borrower_id is null from public.loans
 where id = '00000000-0000-0000-0000-000000010420'), 'link decline leaves the targeted loan claim pending');
select is((select count(*)::int from public.inspect_invite((select token from issued))), 0,
 'a declined token no longer reveals copy');

reset role;
update public.space_members set accepted_at = null where id = '00000000-0000-0000-0000-000000010412';
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000010401');
truncate issued; insert into issued select pg_temp.issue_space('00000000-0000-4000-8000-000000010435');
reset role; update private.invite_links set expires_at = now() - interval '1 second' where redeemed_at is null;
set local role anon;
select is((select count(*)::int from public.inspect_invite((select token from issued))), 0, 'expired tokens reveal nothing');
select throws_ok(format('select public.decline_invite(%L, %L)', (select token from issued),
 '00000000-0000-4000-8000-000000010446'), '22023', null, 'expired tokens cannot decline');

select * from finish();
rollback;
