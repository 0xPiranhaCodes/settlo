-- Invite capability links: 256 random bits, digest-only storage, 14-day expiry.
-- Limits: five live links per target and 20 issue/redeem calls per user per hour.
create type public.invite_kind as enum ('space', 'loan');

create table private.invite_links (
  id uuid primary key default gen_random_uuid(), token_hash bytea not null unique,
  kind public.invite_kind not null, subject_id uuid not null, target_phone public.e164 not null,
  issuer_id uuid not null references public.profiles (id) on delete restrict,
  idempotency_key uuid not null, fingerprint text not null,
  created_at timestamptz not null default now(), expires_at timestamptz not null default now() + interval '14 days',
  redeemed_at timestamptz, redeemed_by uuid references public.profiles (id) on delete restrict,
  redeem_idempotency_key uuid, declined_at timestamptz, decline_idempotency_key uuid, revoked_at timestamptz,
  check (expires_at <= created_at + interval '14 days'),
  check (not (redeemed_at is not null and declined_at is not null)), unique (issuer_id, idempotency_key)
);
alter table private.invite_links enable row level security;
create table private.invite_rate_limits (
  user_id uuid not null references public.profiles (id) on delete cascade,
  action text not null check (action in ('issue', 'redeem')), window_started_at timestamptz not null,
  attempts integer not null check (attempts > 0), primary key (user_id, action)
);
alter table private.invite_rate_limits enable row level security;

create function private.valid_invite_token(p_token text) returns boolean
language plpgsql immutable set search_path = '' as $$
begin
  if p_token is null or octet_length(p_token) <> 64 then return false; end if;
  return p_token ~ '^[0-9a-f]{64}$';
end $$;

create function private.consume_invite_rate_limit(p_user uuid, p_action text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare current private.invite_rate_limits;
begin
  insert into private.invite_rate_limits values (p_user, p_action, now(), 1)
  on conflict (user_id, action) do update set
    window_started_at = case
      when private.invite_rate_limits.window_started_at <= now() - interval '1 hour' then excluded.window_started_at
      else private.invite_rate_limits.window_started_at end,
    attempts = case
      when private.invite_rate_limits.window_started_at <= now() - interval '1 hour' then 1
      else private.invite_rate_limits.attempts + 1 end
  returning * into current;
  return current.attempts <= 20;
end $$;

create function public.issue_invite(p_kind public.invite_kind, p_subject_id uuid, p_idempotency_key uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare me uuid := public.verified_uid(); phone public.e164; fp text; old private.invite_links;
  token text; l public.loans;
begin
  if me is null then raise exception 'issue_invite: unverified caller' using errcode = '42501'; end if;
  if p_kind is null or p_subject_id is null or p_idempotency_key is null then
    raise exception 'issue_invite: required input missing' using errcode = '22023'; end if;
  if p_kind = 'space' then
    select m.phone into phone from public.space_members m where m.id = p_subject_id
      and m.left_at is null and m.accepted_at is null and m.rejected_at is null
      and public.is_accepted_member(m.space_id);
  else
    select * into l from public.loans x where x.id = p_subject_id for update;
    if l.id is not null and l.lender_accepted_at is not null and public.is_me(l.lender_id, l.lender_phone)
       and l.borrower_accepted_at is null and l.borrower_rejected_at is null then phone := l.borrower_phone;
    elsif l.id is not null and l.borrower_accepted_at is not null and public.is_me(l.borrower_id, l.borrower_phone)
       and l.lender_accepted_at is null and l.lender_rejected_at is null then phone := l.lender_phone; end if;
  end if;
  if phone is null then raise exception 'issue_invite: caller is not a party or target is not pending' using errcode = '42501'; end if;
  fp := encode(sha256(convert_to(jsonb_build_object('kind', p_kind, 'subject_id', p_subject_id)::text, 'UTF8')), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(me::text || ':' || p_idempotency_key::text, 1));
  if not private.consume_invite_rate_limit(me, 'issue') then
    raise exception 'invite rate limit reached' using errcode = 'P0001', hint = 'invite_rate_limited';
  end if;
  select * into old from private.invite_links i where i.issuer_id = me and i.idempotency_key = p_idempotency_key for update;
  if found then
    if old.fingerprint <> fp then raise exception 'issue_invite: idempotency conflict' using errcode = 'PT409', hint = 'idempotency_conflict'; end if;
    if old.redeemed_at is not null or old.declined_at is not null or old.revoked_at is not null or old.expires_at <= now() then
      raise exception 'issue_invite: unavailable' using errcode = '22023', hint = 'invite_unavailable'; end if;
    token := encode(extensions.gen_random_bytes(32), 'hex');
    update private.invite_links set token_hash = sha256(convert_to(token, 'UTF8')) where id = old.id;
    return token;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_kind::text || ':' || p_subject_id::text || ':' || phone::text, 0));
  if (select count(*) from private.invite_links i where i.kind = p_kind and i.subject_id = p_subject_id
      and i.target_phone = phone and i.expires_at > now() and i.redeemed_at is null
      and i.declined_at is null and i.revoked_at is null) >= 5 then
    raise exception 'issue_invite: target limit' using errcode = 'P0001', hint = 'invite_target_limit'; end if;
  token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into private.invite_links (token_hash, kind, subject_id, target_phone, issuer_id, idempotency_key, fingerprint)
  values (sha256(convert_to(token, 'UTF8')), p_kind, p_subject_id, phone, me, p_idempotency_key, fp);
  return token;
end $$;

create function public.inspect_invite(p_token text)
returns table (kind public.invite_kind, inviter_name text, subject_name text, masked_phone text)
language sql stable security definer set search_path = '' as $$
  select i.kind, coalesce(nullif(btrim(p.name), ''), 'Someone'),
    case when i.kind = 'space' then s.name else 'Loan with ' || coalesce(nullif(btrim(p.name), ''), 'someone') end,
    left(i.target_phone::text, 6) || repeat('•', greatest(length(i.target_phone::text) - 8, 3)) || right(i.target_phone::text, 2)
  from private.invite_links i join public.profiles p on p.id = i.issuer_id
  left join public.space_members m on i.kind = 'space' and m.id = i.subject_id
  left join public.spaces s on s.id = m.space_id
  left join public.space_members im on i.kind = 'space' and im.space_id = m.space_id and im.user_id = i.issuer_id
    and im.accepted_at is not null and im.left_at is null
  left join public.loans l on i.kind = 'loan' and l.id = i.subject_id
  where private.valid_invite_token(p_token) and i.token_hash = sha256(convert_to(p_token, 'UTF8'))
    and i.expires_at > now() and i.redeemed_at is null and i.declined_at is null and i.revoked_at is null
    and ((i.kind = 'space' and im.id is not null and m.accepted_at is null and m.left_at is null
          and m.rejected_at is null and s.deleted_at is null)
      or (i.kind = 'loan' and (i.issuer_id = l.lender_id or i.issuer_id = l.borrower_id) and
        ((i.target_phone = l.lender_phone and l.lender_accepted_at is null and l.lender_rejected_at is null)
        or (i.target_phone = l.borrower_phone and l.borrower_accepted_at is null and l.borrower_rejected_at is null))))
$$;

create function public.redeem_invite(p_token text, p_idempotency_key uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare me uuid := public.verified_uid(); phone text := public.auth_phone(); i private.invite_links;
begin
  if me is null or p_idempotency_key is null then raise exception 'redeem_invite: verified caller required' using errcode = '42501'; end if;
  if private.valid_invite_token(p_token) then
    select * into i from private.invite_links x where x.token_hash = sha256(convert_to(p_token, 'UTF8')) for update;
  end if;
  if i.redeemed_by = me and i.redeemed_at is not null and i.redeem_idempotency_key = p_idempotency_key then
    return 'redeemed';
  end if;
  -- Expected failures are result values, not exceptions: their quota write
  -- must commit so invalid, unknown and wrong-phone guesses cannot evade it.
  if not private.consume_invite_rate_limit(me, 'redeem') then return 'invite_rate_limited'; end if;
  if i.id is null or i.expires_at <= now() or i.redeemed_at is not null or i.declined_at is not null or i.revoked_at is not null then
    return 'invite_unavailable'; end if;
  if phone is distinct from i.target_phone::text then return 'wrong_phone'; end if;
  begin
    perform public.accept_claim(case when i.kind = 'space' then 'space_member' else 'loan' end, i.subject_id);
  exception when others then
    return 'invite_unavailable';
  end;
  update private.invite_links set redeemed_at = now(), redeemed_by = me, redeem_idempotency_key = p_idempotency_key where id = i.id;
  return 'redeemed';
end $$;

create function public.decline_invite(p_token text, p_idempotency_key uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare i private.invite_links; sid uuid;
begin
  if p_idempotency_key is null or not private.valid_invite_token(p_token) then
    raise exception 'decline_invite: unavailable' using errcode = '22023', hint = 'invite_unavailable'; end if;
  select * into i from private.invite_links x where x.token_hash = sha256(convert_to(p_token, 'UTF8')) for update;
  if i.declined_at is not null and i.decline_idempotency_key = p_idempotency_key then return; end if;
  if i.id is null or i.expires_at <= now() or i.redeemed_at is not null or i.declined_at is not null or i.revoked_at is not null then
    raise exception 'decline_invite: unavailable' using errcode = '22023', hint = 'invite_unavailable'; end if;
  if i.kind = 'space' then
    select m.space_id into sid from public.space_members m where m.id = i.subject_id
      and m.accepted_at is null and m.left_at is null and m.rejected_at is null;
    if sid is null then raise exception 'decline_invite: unavailable' using errcode = '22023', hint = 'invite_unavailable'; end if;
    insert into public.activity (space_id, actor_id, action, after) values
      (sid, null, 'rejected', jsonb_build_object('member_id', i.subject_id, 'phone', i.target_phone, 'link_only', true));
  else
    if not exists (select from public.loans l where l.id = i.subject_id and
      ((i.target_phone = l.lender_phone and l.lender_accepted_at is null and l.lender_rejected_at is null)
      or (i.target_phone = l.borrower_phone and l.borrower_accepted_at is null and l.borrower_rejected_at is null))) then
      raise exception 'decline_invite: unavailable' using errcode = '22023', hint = 'invite_unavailable'; end if;
    insert into public.activity (loan_id, actor_id, action, after) values
      (i.subject_id, null, 'rejected', jsonb_build_object('phone', i.target_phone, 'link_only', true));
  end if;
  update private.invite_links set declined_at = now(), decline_idempotency_key = p_idempotency_key where id = i.id;
end $$;

create function private.revoke_space_issuer_links() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.user_id is not null and old.accepted_at is not null and
     (new.user_id is distinct from old.user_id or new.accepted_at is null or new.left_at is not null) then
    update private.invite_links i set revoked_at = coalesce(i.revoked_at, now()) from public.space_members target
    where i.kind = 'space' and i.subject_id = target.id and target.space_id = old.space_id
      and i.issuer_id = old.user_id and i.redeemed_at is null and i.declined_at is null;
  end if; return new;
end $$;
create trigger revoke_space_issuer_invites after update on public.space_members for each row execute function private.revoke_space_issuer_links();

create function private.revoke_loan_issuer_links() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.lender_id is not null and old.lender_accepted_at is not null and
     (new.lender_id is distinct from old.lender_id or new.lender_accepted_at is null) then
    update private.invite_links set revoked_at = coalesce(revoked_at, now()) where kind = 'loan' and subject_id = old.id
      and issuer_id = old.lender_id and redeemed_at is null and declined_at is null;
  end if;
  if old.borrower_id is not null and old.borrower_accepted_at is not null and
     (new.borrower_id is distinct from old.borrower_id or new.borrower_accepted_at is null) then
    update private.invite_links set revoked_at = coalesce(revoked_at, now()) where kind = 'loan' and subject_id = old.id
      and issuer_id = old.borrower_id and redeemed_at is null and declined_at is null;
  end if; return new;
end $$;
create trigger revoke_loan_issuer_invites after update on public.loans for each row execute function private.revoke_loan_issuer_links();

revoke all on table private.invite_links, private.invite_rate_limits from public, anon, authenticated;
revoke execute on function private.valid_invite_token(text), private.consume_invite_rate_limit(uuid, text),
  private.revoke_space_issuer_links(), private.revoke_loan_issuer_links() from public, anon, authenticated;
revoke execute on function public.issue_invite(public.invite_kind, uuid, uuid), public.redeem_invite(text, uuid) from public, anon;
grant execute on function public.issue_invite(public.invite_kind, uuid, uuid), public.redeem_invite(text, uuid) to authenticated;
revoke execute on function public.inspect_invite(text), public.decline_invite(text, uuid) from public;
grant execute on function public.inspect_invite(text), public.decline_invite(text, uuid) to anon, authenticated;

-- Extend the already-shipped activity feed with link-only decline metadata.
-- The return type changes, so PostgreSQL requires dropping and recreating it.
drop function public.activity_feed(timestamptz, bigint, int);
create function public.activity_feed(
  p_before_at timestamptz default null, p_before_id bigint default null, p_limit int default 30
) returns table (
  id bigint, created_at timestamptz, action text, kind text,
  space_id uuid, space_name text, expense_id uuid, loan_id uuid, repayment_id uuid,
  by_me boolean, actor_name text, counterparty text, description text, amount_minor bigint,
  before_description text, before_amount_minor bigint, status text, my_side text,
  link_only boolean
)
language sql stable security definer set search_path = '' as $$
  with me as (
    select public.verified_uid() as uid
  ), cursor as (
    select coalesce(p_before_at, 'infinity'::timestamptz) as at,
           coalesce(p_before_id, 9223372036854775807) as id,
           least(greatest(coalesce(p_limit, 30), 1), 100) as n
  ), my_spaces as (
    select m.space_id
      from me, public.space_members m
      join public.spaces s on s.id = m.space_id
     where m.user_id = me.uid and m.left_at is null and m.accepted_at is not null and s.deleted_at is null
  ), my_loans as (
    select l.id from me, public.loans l where l.lender_id = me.uid and l.lender_accepted_at is not null
    union
    select l.id from me, public.loans l where l.borrower_id = me.uid and l.borrower_accepted_at is not null
  ), page as (
    select k.created_at, k.id
      from (
        select k.created_at, k.id
          from my_spaces ms, cursor c
          cross join lateral (
            select a.created_at, a.id from public.activity a
             where a.space_id = ms.space_id and (a.created_at, a.id) < (c.at, c.id)
             order by a.created_at desc, a.id desc
             limit c.n) k
        union all
        select k.created_at, k.id
          from my_loans ml, cursor c
          cross join lateral (
            select a.created_at, a.id from public.activity a
             where a.loan_id = ml.id and (a.created_at, a.id) < (c.at, c.id)
             order by a.created_at desc, a.id desc
             limit c.n) k
      ) k
     order by k.created_at desc, k.id desc
     limit (select n from cursor)
  )
  select a.id, a.created_at, a.action,
         case when coalesce((a.after ->> 'link_only')::boolean, false) then 'member'
              when a.repayment_id is not null then 'repayment'
              when a.loan_id is not null then 'loan'
              when a.expense_id is null then 'member'
              when e.is_settlement then 'settlement'
              else 'expense' end,
         a.space_id, s.name, a.expense_id, a.loan_id, a.repayment_id,
         coalesce(a.actor_id = me.uid, false),
         case when a.loan_id is not null then them.name
              else (select coalesce(m.name, case when m.accepted_at is not null then p.name end, m.phone::text)
                      from public.space_members m
                      left join public.profiles p on p.id = m.user_id
                     where m.space_id = a.space_id and m.user_id = a.actor_id
                     order by m.left_at desc nulls first
                     limit 1) end,
         them.name,
         case when coalesce((a.after ->> 'link_only')::boolean, false) then
           coalesce((select m.name from public.space_members m
                      where m.id = (a.after ->> 'member_id')::uuid),
                    them.name, a.after ->> 'phone')
         else coalesce(a.after ->> 'description', a.after ->> 'phone') end,
         coalesce((a.after ->> 'amount_minor')::bigint, (a.after ->> 'principal_minor')::bigint),
         case when a.action = 'edited' then a.before ->> 'description' end,
         case when a.action = 'edited' then (a.before ->> 'amount_minor')::bigint end,
         case when a.repayment_id is not null then r.status
              when e.deleted_at is not null then 'deleted'
              else e.settlement_status end,
         case when a.repayment_id is not null then case when side.me_lender then 'in' else 'out' end
              when e.is_settlement then (
                select case when public.is_me(pm.user_id, pm.phone) then 'out'
                            when public.is_me(sm.user_id, sm.phone) then 'in' end
                  from public.expense_payers ep
                  join public.space_members pm on pm.id = ep.member_id
                  join public.expense_splits es on es.expense_id = ep.expense_id
                  join public.space_members sm on sm.id = es.member_id
                 where ep.expense_id = a.expense_id
                 limit 1) end,
         coalesce((a.after ->> 'link_only')::boolean, false)
    from page
    cross join me
    join public.activity a on a.id = page.id
    left join public.spaces s on s.id = a.space_id
    left join public.expenses e on e.id = a.expense_id
    left join public.loans l on l.id = a.loan_id
    left join public.loan_repayments r on r.id = a.repayment_id
    cross join lateral (select l.lender_id = me.uid as me_lender) side
    left join lateral (
      select coalesce(case when (case when side.me_lender then l.borrower_accepted_at else l.lender_accepted_at end)
                                is not null then p.name end,
                      case when side.me_lender then l.borrower_phone else l.lender_phone end::text) as name
        from (select 1) one
        left join public.profiles p on p.id = case when side.me_lender then l.borrower_id else l.lender_id end
       where l.id is not null
    ) them on true
   order by a.created_at desc, a.id desc
$$;

revoke all on function public.activity_feed(timestamptz, bigint, int) from public, anon, authenticated;
grant execute on function public.activity_feed(timestamptz, bigint, int) to authenticated;
