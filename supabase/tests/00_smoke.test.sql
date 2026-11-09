-- Harness smoke test: pgTAP loads and the local stack has the auth schema.
begin;
create extension if not exists pgtap with schema extensions;

select plan(2);

select has_schema('auth', 'auth schema exists');
select has_table('auth', 'users', 'auth.users exists');

select * from finish();
rollback;
