-- Claim decisions take an idempotency key (#116, ADR 0004), so the app can queue them offline and
-- replay them after a lost response. Additive: accept_claim(text, uuid) and reject_claim(text, uuid)
-- (#9) stay as they are for redeem_invite and older clients, and still do the work; these overloads
-- only put the key in front. Same contract as #59: a fixed empty search_path, verified callers only,
-- a payload-bound key in private.idempotency_keys, codes 22023 / 42501 / PT409.
--
-- The key is claimed first, so a replay returns without writing even though the claim is no longer
-- pending (the two-argument call would refuse it with 42501). A refused decision rolls its key back
-- with it. Keys are honoured for 30 days (#70); a replay after that runs as a new call and is
-- refused with 42501, since a decision is final.
create function public.accept_claim(p_kind text, p_id uuid, p_idempotency_key uuid) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if p_kind is null or p_id is null or p_idempotency_key is null then
    raise exception 'accept_claim: kind, id and idempotency key are required' using errcode = '22023';
  end if;
  if not private.claim_idempotency_key('accept_claim', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object('kind', p_kind, 'id', p_id)::text, 'UTF8')), 'hex')) then
    return;
  end if;
  perform public.accept_claim(p_kind, p_id);
end $$;

create function public.reject_claim(p_kind text, p_id uuid, p_idempotency_key uuid) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if p_kind is null or p_id is null or p_idempotency_key is null then
    raise exception 'reject_claim: kind, id and idempotency key are required' using errcode = '22023';
  end if;
  if not private.claim_idempotency_key('reject_claim', p_idempotency_key, encode(sha256(convert_to(
       jsonb_build_object('kind', p_kind, 'id', p_id)::text, 'UTF8')), 'hex')) then
    return;
  end if;
  perform public.reject_claim(p_kind, p_id);
end $$;

revoke execute on function public.accept_claim(text, uuid, uuid), public.reject_claim(text, uuid, uuid)
  from public, anon;
grant execute on function public.accept_claim(text, uuid, uuid), public.reject_claim(text, uuid, uuid)
  to authenticated;
