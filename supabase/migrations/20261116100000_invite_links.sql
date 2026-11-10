-- Capability invite links (#104). The bearer token is 256 random bits, only its SHA-256 digest
-- is indexed; the server-side random material exists solely so an idempotent issue replay can
-- reproduce the same response without keeping the token itself.
create type public.invite_kind as enum ('space', 'loan');

create table private.invite_links (
  id uuid primary key default gen_random_uuid(),
  nonce uuid not null default gen_random_uuid(),
  token_hash bytea not null unique,
  kind public.invite_kind not null,
  subject_id uuid not null,
  target_phone public.e164 not null,
  issuer_id uuid not null references public.profiles (id) on delete restrict,
  idempotency_key uuid not null,
  fingerprint text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days',
  redeemed_at timestamptz,
  redeemed_by uuid references public.profiles (id) on delete restrict,
  redeem_idempotency_key uuid,
  declined_at timestamptz,
  check (expires_at <= created_at + interval '14 days'),
  check (not (redeemed_at is not null and declined_at is not null)),
  unique (issuer_id, idempotency_key)
);
alter table private.invite_links enable row level security;

create function private.invite_token(p_id uuid, p_nonce uuid, p_issuer uuid) returns text
language sql immutable security definer set search_path = '' as $$
  select encode(sha256(convert_to(p_id::text || ':' || p_nonce::text || ':' || p_issuer::text, 'UTF8')), 'hex')
$$;

create function public.issue_invite(p_kind public.invite_kind, p_subject_id uuid, p_idempotency_key uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  phone public.e164;
  fp text;
  existing private.invite_links;
  made private.invite_links;
  token text;
  l public.loans;
begin
  if me is null then
    raise exception 'issue_invite: caller has no verified phone' using errcode = '42501';
  end if;
  if p_kind is null or p_subject_id is null or p_idempotency_key is null then
    raise exception 'issue_invite: kind, subject and idempotency key are required' using errcode = '22023';
  end if;
  fp := encode(sha256(convert_to(jsonb_build_object('kind', p_kind, 'subject_id', p_subject_id)::text, 'UTF8')), 'hex');
  select * into existing from private.invite_links i
   where i.issuer_id = me and i.idempotency_key = p_idempotency_key;
  if found then
    if existing.fingerprint <> fp then
      raise exception 'issue_invite: idempotency key was used with another payload'
        using errcode = 'PT409', hint = 'idempotency_conflict';
    end if;
    return private.invite_token(existing.id, existing.nonce, existing.issuer_id);
  end if;

  if p_kind = 'space' then
    select m.phone into phone from public.space_members m
     where m.id = p_subject_id and m.left_at is null and m.accepted_at is null and m.rejected_at is null
       and public.is_accepted_member(m.space_id);
  else
    select * into l from public.loans x where x.id = p_subject_id for update;
    if l.id is not null and l.lender_accepted_at is not null and public.is_me(l.lender_id, l.lender_phone)
       and l.borrower_accepted_at is null and l.borrower_rejected_at is null then
      phone := l.borrower_phone;
    elsif l.id is not null and l.borrower_accepted_at is not null and public.is_me(l.borrower_id, l.borrower_phone)
       and l.lender_accepted_at is null and l.lender_rejected_at is null then
      phone := l.lender_phone;
    end if;
  end if;
  if phone is null then
    raise exception 'issue_invite: caller is not a party or target is not pending' using errcode = '42501';
  end if;

  insert into private.invite_links (token_hash, kind, subject_id, target_phone, issuer_id,
                                    idempotency_key, fingerprint)
  values (extensions.gen_random_bytes(32), p_kind, p_subject_id, phone, me, p_idempotency_key, fp)
  on conflict (issuer_id, idempotency_key) do nothing
  returning * into made;
  if not found then
    select * into existing from private.invite_links x
     where x.issuer_id = me and x.idempotency_key = p_idempotency_key;
    if existing.fingerprint <> fp then
      raise exception 'issue_invite: idempotency key was used with another payload'
        using errcode = 'PT409', hint = 'idempotency_conflict';
    end if;
    return private.invite_token(existing.id, existing.nonce, existing.issuer_id);
  end if;
  token := private.invite_token(made.id, made.nonce, made.issuer_id);
  update private.invite_links set token_hash = sha256(convert_to(token, 'UTF8')) where id = made.id;
  return token;
end $$;

create function public.inspect_invite(p_token text)
returns table (kind public.invite_kind, inviter_name text, subject_name text, masked_phone text)
language sql stable security definer set search_path = '' as $$
  select i.kind,
         coalesce(nullif(btrim(p.name), ''), 'Someone'),
         case when i.kind = 'space' then s.name else 'Loan with ' || coalesce(nullif(btrim(p.name), ''), 'someone') end,
         left(i.target_phone::text, 6) || repeat('•', greatest(length(i.target_phone::text) - 8, 3)) || right(i.target_phone::text, 2)
    from private.invite_links i
    join public.profiles p on p.id = i.issuer_id
    left join public.space_members m on i.kind = 'space' and m.id = i.subject_id
    left join public.spaces s on s.id = m.space_id
    left join public.loans l on i.kind = 'loan' and l.id = i.subject_id
   where i.token_hash = sha256(convert_to(coalesce(p_token, ''), 'UTF8'))
     and i.expires_at > now() and i.redeemed_at is null and i.declined_at is null
     and (
       (i.kind = 'space' and m.accepted_at is null and m.left_at is null and m.rejected_at is null
                         and s.deleted_at is null)
       or
       (i.kind = 'loan' and (
         (i.target_phone = l.lender_phone and l.lender_accepted_at is null and l.lender_rejected_at is null)
         or
         (i.target_phone = l.borrower_phone and l.borrower_accepted_at is null and l.borrower_rejected_at is null)
       ))
     )
$$;

create function public.redeem_invite(p_token text, p_idempotency_key uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := public.verified_uid();
  phone text := public.auth_phone();
  i private.invite_links;
begin
  if me is null or p_idempotency_key is null then
    raise exception 'redeem_invite: verified caller and idempotency key are required' using errcode = '42501';
  end if;
  select * into i from private.invite_links x
   where x.token_hash = sha256(convert_to(coalesce(p_token, ''), 'UTF8')) for update;
  if i.redeemed_by = me and i.redeemed_at is not null and i.redeem_idempotency_key = p_idempotency_key then return; end if;
  if i.id is null or i.expires_at <= now() or i.redeemed_at is not null or i.declined_at is not null then
    raise exception 'redeem_invite: invite is invalid, expired or already used' using errcode = '22023', hint = 'invite_unavailable';
  end if;
  if phone is distinct from i.target_phone::text then
    raise exception 'redeem_invite: invite belongs to another phone' using errcode = '42501', hint = 'wrong_phone';
  end if;
  if not private.claim_idempotency_key('redeem_invite', p_idempotency_key,
       encode(sha256(convert_to(p_token, 'UTF8')), 'hex')) then return; end if;
  perform public.accept_claim(case when i.kind = 'space' then 'space_member' else 'loan' end, i.subject_id);
  update private.invite_links set redeemed_at = now(), redeemed_by = me,
                                  redeem_idempotency_key = p_idempotency_key where id = i.id;
end $$;

create function public.decline_invite(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  i private.invite_links;
  m public.space_members;
  l public.loans;
begin
  select * into i from private.invite_links x
   where x.token_hash = sha256(convert_to(coalesce(p_token, ''), 'UTF8')) for update;
  if i.id is null or i.expires_at <= now() or i.redeemed_at is not null or i.declined_at is not null then
    raise exception 'decline_invite: invite is unavailable' using errcode = '22023', hint = 'invite_unavailable';
  end if;
  if i.kind = 'space' then
    update public.space_members set user_id = null, left_at = now(), rejected_at = now()
     where id = i.subject_id and accepted_at is null and left_at is null returning * into m;
    if m.id is null then
      raise exception 'decline_invite: invite is unavailable' using errcode = '22023', hint = 'invite_unavailable';
    end if;
    insert into public.activity (space_id, actor_id, action, after)
    values (m.space_id, null, 'rejected', jsonb_build_object('member_id', m.id, 'phone', m.phone));
  else
    select * into l from public.loans where id = i.subject_id for update;
    if i.target_phone = l.lender_phone and l.lender_accepted_at is null and l.lender_rejected_at is null then
      update public.loans set lender_id = null, lender_rejected_at = now() where id = l.id
       and lender_accepted_at is null and lender_rejected_at is null;
    elsif i.target_phone = l.borrower_phone and l.borrower_accepted_at is null and l.borrower_rejected_at is null then
      update public.loans set borrower_id = null, borrower_rejected_at = now() where id = l.id
       and borrower_accepted_at is null and borrower_rejected_at is null;
    else
      raise exception 'decline_invite: invite is unavailable' using errcode = '22023', hint = 'invite_unavailable';
    end if;
    insert into public.activity (loan_id, actor_id, action, after)
    values (l.id, null, 'rejected', jsonb_build_object('phone', i.target_phone));
  end if;
  update private.invite_links set declined_at = now() where id = i.id;
end $$;

revoke all on table private.invite_links from public, anon, authenticated;
revoke execute on function private.invite_token(uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.issue_invite(public.invite_kind, uuid, uuid),
  public.redeem_invite(text, uuid) from public, anon;
grant execute on function public.issue_invite(public.invite_kind, uuid, uuid),
  public.redeem_invite(text, uuid) to authenticated;
revoke execute on function public.inspect_invite(text), public.decline_invite(text) from public;
grant execute on function public.inspect_invite(text), public.decline_invite(text) to anon, authenticated;
