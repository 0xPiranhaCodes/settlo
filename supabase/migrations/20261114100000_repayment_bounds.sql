-- Repayment bounds (#99): paid_on falls between the loan's start_on and today in India, and a
-- reference is trimmed, at most 64 characters and printable. A BEFORE INSERT trigger rather than
-- checks in record_repayment, because parties may also insert repayments directly (RLS, #8); the
-- RPC's insert fires it too, so its 22023 hints reach RPC callers as overpayment does. Insert only:
-- the guard trigger (#7) already freezes these columns once recorded. Named to fire after
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
  new.reference := nullif(btrim(new.reference), '');
  if char_length(new.reference) > 64 or new.reference ~ '[[:cntrl:]]' then
    raise exception 'a repayment reference is at most 64 printable characters'
      using errcode = '22023', hint = 'reference_invalid';
  end if;
  return new;
end $$;

revoke execute on function public.bound_loan_repayment() from public, anon, authenticated;

create trigger loan_repayments_limits
  before insert on public.loan_repayments
  for each row execute function public.bound_loan_repayment();
