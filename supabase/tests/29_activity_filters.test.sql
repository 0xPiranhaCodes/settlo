-- Activity filters, unread and 'Question this' (#109): activity_feed's filters, mark_activity_seen
-- and question_activity.
-- Callers: A owns S1 and S2; B is an accepted member of S1; D is a member of S1 who later leaves;
-- P has an account but is still a pending member of S1; O is a member of S2 only; anon has no
-- session. A spends in both spaces, edits one expense in each, and lends B L1.
begin;
create extension if not exists pgtap with schema extensions;

select plan(174);

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

-- Redaction. The server is the authority and may be stricter than the app, never laxer. Each case
-- is an input, what the app's own redactPhones returns for it (app), and what the server must
-- return (want). Two checks per case: the server returns want, and it redacts at least everything
-- the app does, that is, redacting the app's output leaves nothing the server would have kept:
-- server(app) = server(input). Invisible characters, marks outside Devanagari, spaces other than
-- U+0020 and characters outside the BMP are written as escapes so the file shows what it tests.
create temp table redaction_cases (n int generated always as identity, input text, app text, want text, what text);
-- Where the app and the server agree.
insert into redaction_cases (input, app, want, what) values
  (E'Call +९१ ९८०००–००००९ / 9\u200C8000 00009',
   E'Call •••• / ••••',
   E'Call •••• / ••••', E'the reviewer''s probe: Devanagari with +91 and an en dash, and a zero-width non-joiner'),
  (E'फ़ोन ९८०००००००९ पर',
   E'फ़ोन •••• पर',
   E'फ़ोन •••• पर', E'Devanagari digits'),
  (E'৯৮০০০০০০০৯',
   E'••••',
   E'••••', E'Bengali digits'),
  (E'９８０００００００９',
   E'••••',
   E'••••', E'fullwidth digits'),
  (E'٩٨٠٠٠٠٠٠٠٩',
   E'••••',
   E'••••', E'Arabic-Indic digits'),
  (E'x \U0001D7D7\U0001D7D6\U0001D7CE\U0001D7CE\U0001D7CE\U0001D7CE\U0001D7CE\U0001D7CE\U0001D7CE\U0001D7D7',
   E'x ••••',
   E'x ••••', E'digits outside the BMP (mathematical bold)'),
  (E'98०००০০০০9',
   E'••••',
   E'••••', E'scripts mixed inside one number'),
  (E'98000\u200D00009',
   E'••••',
   E'••••', E'a zero-width joiner inside'),
  (E'9\u200B8\u200B0\u200B0\u200B0\u200B0\u200B0\u200B0\u200B0\u200B9',
   E'••••',
   E'••••', E'a zero-width space between every digit'),
  (E'\u200E98000\u00AD00009',
   E'\u200E••••',
   E'\u200E••••', E'a left-to-right mark before and a soft hyphen inside'),
  (E'+9\u20601 9800000009',
   E'••••',
   E'••••', E'a word joiner inside the +91'),
  (E'98000—00009',
   E'••••',
   E'••••', E'an em dash'),
  (E'98000–00009',
   E'••••',
   E'••••', E'an en dash'),
  (E'９８０００－００００９',
   E'••••',
   E'••••', E'a fullwidth hyphen between fullwidth digits'),
  (E'+91\u00A098000\u00A000009',
   E'••••',
   E'••••', E'no-break spaces'),
  (E'98000\u300000009',
   E'••••',
   E'••••', E'an ideographic space'),
  (E'98000\u2009 00009',
   E'••••',
   E'••••', E'a thin space and a space'),
  (E'98000.00009',
   E'••••',
   E'••••', E'dots'),
  (E'9.8.0.0.0.0.0.0.0.9',
   E'••••',
   E'••••', E'a dot between every digit'),
  (E'(+91) 98000.00009',
   E'••••',
   E'••••', E'parentheses and a dot'),
  (E'Ask Riya (98000) 00009 today',
   E'Ask Riya •••• today',
   E'Ask Riya •••• today', E'parentheses around the first half'),
  (E'+919800000009',
   E'••••',
   E'••••', E'prefix +91, joined'),
  (E'+91 98000 00009',
   E'••••',
   E'••••', E'prefix +91, spaced'),
  (E'UTR 919800000009',
   E'UTR ••••',
   E'UTR ••••', E'prefix 91, joined, in a sentence'),
  (E'91-98000-00009',
   E'••••',
   E'••••', E'prefix 91, hyphens'),
  (E'09800000009',
   E'••••',
   E'••••', E'prefix 0, joined'),
  (E'0 98000 00009',
   E'••••',
   E'••••', E'prefix 0, spaced'),
  (E'(0)9800000009',
   E'••••',
   E'••••', E'prefix 0 in parentheses'),
  (E'9800000009 9800000010',
   E'•••• ••••',
   E'•••• ••••', E'two numbers a space apart'),
  (E'कमरा १२\u00A0— 98000 00009 🎉',
   E'कमरा १२\u00A0— •••• 🎉',
   E'कमरा १२\u00A0— •••• 🎉', E'the rest is returned as written: its own digits, no-break space, dash and emoji'),
  (E'19800000009',
   E'19800000009',
   E'19800000009', E'11 digits with no trunk prefix is not a phone'),
  (E'980000000',
   E'980000000',
   E'980000000', E'9 digits is not a phone'),
  (E'Ref 4321 8812 0099 1234',
   E'Ref 4321 8812 0099 1234',
   E'Ref 4321 8812 0099 1234', E'a card-like run is not a phone'),
  (E'₹10,00,000 on 2026-11-05, ref 12345',
   E'₹10,00,000 on 2026-11-05, ref 12345',
   E'₹10,00,000 on 2026-11-05, ref 12345', E'amounts and dates are not phones'),
  (E'98000 - 00009',
   E'98000 - 00009',
   E'98000 - 00009', E'three separators break a number'),
  (E'9198000000091',
   E'9198000000091',
   E'9198000000091', E'13 digits is not a phone'),
  (E'',
   E'',
   E'', E'an empty note');
-- Where the server is stricter: lookalike digits (folded by NFKC) and nonspacing or enclosing
-- marks (dropped), neither of which the app folds; and what must still be left alone.
insert into redaction_cases (input, app, want, what) values
  (E'Call 9\u034F8\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F9',
   E'Call 9\u034F8\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F9',
   E'Call ••••', E'the reviewer''s repro: a combining grapheme joiner (U+034F) between every digit'),
  (E'9\uFE0F8\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F9 ok',
   E'9\uFE0F8\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F9 ok',
   E'•••• ok', E'the reviewer''s repro: a variation selector (U+FE0F) between every digit'),
  (E'Call 9\u034F8\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F9 / 9\uFE0F8\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F9',
   E'Call 9\u034F8\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F9 / 9\uFE0F8\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F9',
   E'Call •••• / ••••', E'the reviewer''s repro, whole'),
  (E'Call ⑨⑧⓪⓪⓪⓪⓪⓪⓪⑨',
   E'Call ⑨⑧⓪⓪⓪⓪⓪⓪⓪⑨',
   E'Call ••••', E'circled digits'),
  (E'⁹⁸⁰⁰⁰⁰⁰⁰⁰⁹ now',
   E'⁹⁸⁰⁰⁰⁰⁰⁰⁰⁹ now',
   E'•••• now', E'superscript digits'),
  (E'₉₈₀₀₀₀₀₀₀₉',
   E'₉₈₀₀₀₀₀₀₀₉',
   E'••••', E'subscript digits'),
  (E'⁺⁹¹ ⑨⑧⓪⓪⓪ ⓪⓪⓪⓪⑨',
   E'⁺⁹¹ ⑨⑧⓪⓪⓪ ⓪⓪⓪⓪⑨',
   E'••••', E'superscript +91 and circled digits, spaced'),
  (E'⑼⑻⑴⑴⑴⑴⑴⑴⑴⑼',
   E'⑼⑻⑴⑴⑴⑴⑴⑴⑴⑼',
   E'••••', E'parenthesised digits'),
  (E'⒐⒏⒈⒈⒈⒈⒈⒈⒈⒐',
   E'⒐⒏⒈⒈⒈⒈⒈⒈⒈⒐',
   E'••••', E'digits with a full stop'),
  (E'9\uFE0F\u20E38\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E39\uFE0F\u20E3 ok',
   E'9\uFE0F\u20E38\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E30\uFE0F\u20E39\uFE0F\u20E3 ok',
   E'•••• ok', E'keycap digits'),
  (E'9\U000E01008\U000E01000\U000E01000\U000E01000\U000E01000\U000E01000\U000E01000\U000E01000\U000E01009',
   E'9\U000E01008\U000E01000\U000E01000\U000E01000\U000E01000\U000E01000\U000E01000\U000E01000\U000E01009',
   E'••••', E'a supplementary variation selector (U+E0100) between digits'),
  (E'9\u03368\u03360\u03360\u03360\u03360\u03360\u03360\u03360\u03369\u0336',
   E'9\u03368\u03360\u03360\u03360\u03360\u03360\u03360\u03360\u03369\u0336',
   E'••••', E'a combining strike-through on every digit'),
  (E'9\u20DD8\u20DD0\u20DD0\u20DD0\u20DD0\u20DD0\u20DD0\u20DD0\u20DD9\u20DD',
   E'9\u20DD8\u20DD0\u20DD0\u20DD0\u20DD0\u20DD0\u20DD0\u20DD0\u20DD9\u20DD',
   E'••••', E'an enclosing circle on every digit'),
  (E'98⓪⓪⁰⁰००09',
   E'98⓪⓪⁰⁰००09',
   E'••••', E'plain, circled, superscript and Devanagari digits in one number'),
  (E'x ⑳12345678',
   E'x ⑳12345678',
   E'x ••••', E'one character that is two digits (U+2473 is 20) starts a number'),
  (E'Seat ⑳, row ⑫',
   E'Seat ⑳, row ⑫',
   E'Seat ⑳, row ⑫', E'circled numbers that are not a phone stay'),
  (E'x² + y² = 10',
   E'x² + y² = 10',
   E'x² + y² = 10', E'superscripts in a sum stay'),
  (E'किराया ₹१२,००० क्यों? café',
   E'किराया ₹१२,००० क्यों? café',
   E'किराया ₹१२,००० क्यों? café', E'text with its own combining marks stays as written');
select is(private.redact_phones(c.input), c.want, 'redact: ' || c.what) from redaction_cases c order by c.n;
select is(private.redact_phones(c.app), private.redact_phones(c.input),
          'redact, at least what the app does: ' || c.what) from redaction_cases c order by c.n;
select is(private.redact_phones(c.input, true), c.want, 'redact, as a reference: ' || c.what) from (values
  (E'432188120099',
   E'432188120099', E'a whole 12-digit UTR is kept'),
  (E' 919800000009 ',
   E' 919800000009 ', E'a UTR is kept with spaces around it'),
  (E'९१२३४५६७८९०१',
   E'९१२३४५६७८९०१', E'a UTR in Devanagari digits is kept'),
  (E'\u00A0432188120099\u00A0',
   E'\u00A0432188120099\u00A0', E'a UTR with no-break spaces around it is kept'),
  (E'9198\u200B00000009',
   E'••••', E'an invisible character inside means it is not a UTR'),
  (E'UTR 919800000009',
   E'UTR ••••', E'anything else beside the digits means it is not a UTR'),
  (E'432188120099x',
   E'432188120099x', E'12 digits that do not read as a phone are kept either way')
) c(input, want, what);
select is(private.redact_phones(null), null, 'redact: null stays null');
select ok(not has_function_privilege('authenticated', 'private.redact_phones(text, boolean)', 'execute')
          and not has_function_privilege('anon', 'private.redact_phones(text, boolean)', 'execute'),
  'redact: the helper is not callable through the API');

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

-- Straight through the RPC, as a client that redacts nothing would call it: the reviewer's probe.
select pg_temp.login('00000000-0000-0000-0000-000000009302');
select lives_ok(format('select public.question_activity(%s, %L)', (select s1 from x),
    E'Call +९१ ९८०००–००००९ / 9\u200C8000 00009, or ৯৮০০০০০০০৯, ９８０００\u200D００００９, 98000—00009'),
  'note: B sends numbers in other scripts, with a zero-width joiner and an em dash');
select is((select q ->> 'note' from public.activity_feed() f, jsonb_array_elements(f.questions) q
            where f.id = (select s1 from x) and (q ->> 'by_me')::boolean),
  'Call •••• / ••••, or ••••, ••••, ••••', 'note: none of them is stored or returned');
-- The second review's repro, and the lookalikes: marks between digits, circled and superscript digits.
select lives_ok(format('select public.question_activity(%s, %L)', (select s1 from x),
    E'Call 9\u034F8\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F0\u034F9 / 9\uFE0F8\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F0\uFE0F9'
    || E', ⑨⑧⓪⓪⓪⓪⓪⓪⓪⑨ or ⁹⁸⁰⁰⁰⁰⁰⁰⁰⁹'),
  'note: B sends numbers split by U+034F and U+FE0F, and in circled and superscript digits');
select is((select q ->> 'note' from public.activity_feed() f, jsonb_array_elements(f.questions) q
            where f.id = (select s1 from x) and (q ->> 'by_me')::boolean),
  'Call •••• / ••••, •••• or ••••', 'note: none of them is stored or returned');
select lives_ok(format('select public.question_activity(%s, %L)', (select s1 from x), 'Why did this go up?'),
  'note: B asks the first question again');
select pg_temp.login('00000000-0000-0000-0000-000000009303');

-- Who sees the notes: members of that space, on that row.
select is(pg_temp.notes(), 'Bilal:false:Why did this go up? | Dev:true:Call •••• or ••••, ref 12345 ' || repeat('a', 234),
  'note: trimmed, phone numbers redacted, shown oldest first with who asked');
select pg_temp.login('00000000-0000-0000-0000-000000009302');
select lives_ok(format('select public.question_activity(%s, %L)', (select s1 from x), 'Was the water extra?'),
  'note: B asks again');
select pg_temp.login('00000000-0000-0000-0000-000000009301');
select ok(pg_temp.notes() like 'Bilal:false:Was the water extra? | Dev:false:Call •••• or %',
  'note: the editor sees them; asking again replaced B''s note');
-- Each note says when it was asked, which is what rings the editor's bell (and nobody else's: the
-- app counts a question only on the caller's own edit). The same note again is not a new question.
select ok((select bool_and((q ->> 'created_at')::timestamptz = now()) and count(*) = 2
             from public.activity_feed() f, jsonb_array_elements(f.questions) q),
  'note: each note carries when it was asked');
reset role;
update private.activity_questions set created_at = now() - interval '1 day';
set local role authenticated;
select pg_temp.login('00000000-0000-0000-0000-000000009302');
select public.question_activity((select s1 from x), 'Was the water extra?');
select pg_temp.login('00000000-0000-0000-0000-000000009303');
select public.question_activity((select s1 from x), 'And the gas?');
select pg_temp.login('00000000-0000-0000-0000-000000009301');
select is((select string_agg(concat_ws(':', q ->> 'name', (q ->> 'created_at')::timestamptz = now()), ' ')
             from public.activity_feed() f, jsonb_array_elements(f.questions) q),
  'Bilal:f Dev:t', 'note: a replay keeps its time; a changed note is asked now, and sorts last');
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

reset role;
select has_trigger('public', 'activity_seen', 'live_caller', 'barrier: activity_seen takes the delete_account write barrier');
select has_trigger('private', 'activity_questions', 'live_caller', 'barrier: activity_questions takes it too');

select * from finish();
rollback;
