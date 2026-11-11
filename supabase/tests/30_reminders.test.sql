begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Synthetic identities generated in the transaction; no contact data in fixtures.
insert into auth.users(id, phone, phone_confirmed_at)
select ('10000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
       (910000000000::bigint+n)::text, now() from generate_series(1,4) n;
insert into public.profiles(id, phone, name)
select id, ('+' || phone)::public.e164, 'Test party' from auth.users
where id::text like '10000000-%';
insert into public.loans(id,lender_id,borrower_id,lender_phone,borrower_phone,
  lender_accepted_at,borrower_accepted_at,principal_minor,installment_minor,due_day,start_on,created_by)
select '20000000-0000-0000-0000-000000000001', a.id,b.id,a.phone,b.phone,
  now(),now(),10000,1000,5,'2026-01-01',a.id
from public.profiles a,public.profiles b
where a.id='10000000-0000-0000-0000-000000000001' and b.id='10000000-0000-0000-0000-000000000002';
create function pg_temp.login(n int) returns text language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub',
    '10000000-0000-0000-0000-' || lpad(n::text,12,'0'),'role','authenticated')::text,true)
$$;
grant execute on function pg_temp.login(int) to authenticated;
select ok(not has_function_privilege('anon','public.remind_loan(uuid)','execute'),'anon cannot remind');
select ok(not has_function_privilege('authenticated','private.send_due_reminders(date)','execute'),'cron is server only');
select ok((select bool_and(relrowsecurity) from pg_class where oid in
 ('public.loan_reminders'::regclass,'public.reminder_preferences'::regclass,'private.due_reminders'::regclass)), 'new tables have RLS');
set local role authenticated;
select pg_temp.login(3);
select throws_ok($$select public.remind_loan('20000000-0000-0000-0000-000000000001')$$,'42501','Not allowed','outsider refused');
select pg_temp.login(1);
select is(public.remind_loan('20000000-0000-0000-0000-000000000001'), now()+interval '24 hours','first send returns deadline');
select is(public.remind_loan('20000000-0000-0000-0000-000000000001'), now()+interval '24 hours','retry returns same deadline');
select is((select count(*)::int from public.activity_feed() where action='reminded'),0,'sender feed has no nudge');
select is((select count(*)::int from public.activity where action='reminded'),0,'sender direct read has no nudge');
select pg_temp.login(2);
select is((select count(*)::int from public.activity_feed() where action='reminded'),1,'only recipient feed receives nudge');
select is((select count(*)::int from public.activity where action='reminded'),1,'recipient direct read sees one');
select is(public.remind_loan('20000000-0000-0000-0000-000000000001'), now()+interval '24 hours','other direction shares loan cooldown');
select lives_ok('select public.set_reminders(false)','recipient can opt out');
select is((select enabled from public.reminder_preferences),false,'preference persisted');
select throws_ok('update public.loan_reminders set sent_at = now()','42501',null,'cannot alter cooldown');
select pg_temp.login(3);
select is((select count(*)::int from public.reminder_preferences),0,'cannot read another preference');
select is((select count(*)::int from public.loan_reminders),0,'outsider cannot read cooldown');
select is((select count(*)::int from public.activity_feed() where action='reminded'),0,'outsider feed hidden');
reset role;
update public.loan_reminders set sent_at=now()-interval '24 hours';
set local role authenticated;
select pg_temp.login(1);
select throws_ok($$select public.remind_loan('20000000-0000-0000-0000-000000000001')$$,'22023','Reminder unavailable','opt out enforced server side');
select pg_temp.login(2);
select public.set_reminders(true);
select pg_temp.login(1);
select lives_ok($$select public.remind_loan('20000000-0000-0000-0000-000000000001')$$,'exactly 24h allowed');
reset role;
select is((select count(*)::int from public.activity where action='reminded'),2,'exactly two sends');
-- Unaccepted and unverified users cannot send, even when linked to the loan.
update public.loans set borrower_accepted_at=null where id='20000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.login(2);
select throws_ok($$select public.remind_loan('20000000-0000-0000-0000-000000000001')$$,'42501','Not allowed','pending party refused');
reset role;
update auth.users set phone_confirmed_at=null where id='10000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.login(1);
select throws_ok($$select public.remind_loan('20000000-0000-0000-0000-000000000001')$$,'42501','Not allowed','unverified party refused');
reset role;
update public.loans set borrower_accepted_at=now() where id='20000000-0000-0000-0000-000000000001';
select private.send_due_reminders('2026-02-05');
select is((select count(*)::int from public.activity where action='due'),0,'not overdue on due day');
update public.reminder_preferences set enabled=false where user_id='10000000-0000-0000-0000-000000000002';
select private.send_due_reminders('2026-02-06');
select is((select count(*)::int from public.activity where action='due'),0,'due nudge respects opt out');
update public.reminder_preferences set enabled=true where user_id='10000000-0000-0000-0000-000000000002';
select private.send_due_reminders('2026-02-06');
select private.send_due_reminders('2026-02-06');
select is((select count(*)::int from public.activity where action='due'),1,'day-after cron is idempotent');
select is((select recipient_id from public.activity where action='due'),
 '10000000-0000-0000-0000-000000000002'::uuid,'due reminder goes only to borrower');
select * from finish();
rollback;
