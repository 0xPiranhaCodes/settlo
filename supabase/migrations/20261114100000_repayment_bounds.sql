-- Repayment bounds (#99): paid_on falls between the loan's start_on and today in India, and a
-- reference is trimmed of Unicode whitespace, at most 64 characters and free of control and
-- format characters (Cc, Cf). A BEFORE INSERT trigger rather than checks in record_repayment,
-- because parties may also insert repayments directly (RLS, #8); the RPC's insert fires it too, so
-- its 22023 hints reach RPC callers as overpayment does. Insert only: the guard trigger (#7)
-- already freezes these columns once recorded. Named to fire after
-- loan_repayments_guard (triggers fire in name order), which refuses non-parties first: BEFORE
-- triggers run ahead of RLS, so this one must not read an outsider's loan.
create function public.bound_loan_repayment() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  start_on date;
begin
  select l.start_on into start_on from public.loans l where l.id = new.loan_id;
  if new.paid_on < start_on then
    raise exception 'repayment paid on % is before the loan started', new.paid_on
      using errcode = '22023', hint = 'paid_on_before_start';
  end if;
  if new.paid_on > (now() at time zone 'Asia/Kolkata')::date then
    raise exception 'repayment paid on % is in the future', new.paid_on
      using errcode = '22023', hint = 'paid_on_future';
  end if;
  -- Trim Unicode White_Space (btrim is ASCII only), then refuse any Cc or Cf character left
  -- (Unicode 16; PostgreSQL regexes have no \p{...}). docs/api.md states the same rule for clients.
  new.reference := nullif(regexp_replace(new.reference,
    '^[\u0009-\u000D \u0085   -     　]+|'
    '[\u0009-\u000D \u0085   -     　]+$', '', 'g'), '');
  if char_length(new.reference) > 64 or new.reference ~ ('['
       '\u0000-\u001F\u007F-\u009F­؀-؅؜۝܏࢐-࢑࣢᠎'
       '​-‏‪-‮⁠-⁤⁦-⁯﻿￹-￻\U000110BD\U000110CD'
       '\U00013430-\U0001343F\U0001BCA0-\U0001BCA3\U0001D173-\U0001D17A\U000E0001\U000E0020-\U000E007F]') then
    raise exception 'a repayment reference is at most 64 characters, with no control or format characters'
      using errcode = '22023', hint = 'reference_invalid';
  end if;
  return new;
end $$;

revoke execute on function public.bound_loan_repayment() from public, anon, authenticated;

create trigger loan_repayments_limits
  before insert on public.loan_repayments
  for each row execute function public.bound_loan_repayment();
