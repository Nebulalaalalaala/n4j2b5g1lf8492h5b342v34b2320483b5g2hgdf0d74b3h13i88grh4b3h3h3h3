-- Optional server rollback ONLY. Does not delete reports, evidence, audit rows,
-- accounts or XP. Restores the exact deployed claim/send functions captured by
-- GOOBER_HUB_MODERATION.sql. Restart clients after restoring the local backup.
begin;
do $$ begin
  if to_regprocedure('public.hub_base_claim(text,text,text,text,text[])') is null
    or to_regprocedure('public.hub_base_send(text,text,text,text)') is null
    or to_regprocedure('public.hub_base_send_as_test(text,text,text)') is null then
    raise exception 'Moderation base-function backup missing; no changes made';
  end if;
end $$;
drop function public.hub_claim(text,text,text,text,text[]);
drop function public.hub_send(text,text,text,text);
drop function public.hub_send_as_test(text,text,text);
alter function public.hub_base_claim(text,text,text,text,text[]) rename to hub_claim;
alter function public.hub_base_send(text,text,text,text) rename to hub_send;
alter function public.hub_base_send_as_test(text,text,text) rename to hub_send_as_test;
grant execute on function public.hub_claim(text,text,text,text,text[]) to anon;
grant execute on function public.hub_send(text,text,text,text) to anon;
grant execute on function public.hub_send_as_test(text,text,text) to anon;
create or replace function public.hub_ok(p_user text,p_key text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select public.hub_credential_ok(p_user,p_key);
$$;
revoke all on function public.hub_ok(text,text) from public,anon,authenticated;
drop function public.hub_admin_reports(text,text,text,boolean,bigint);
drop function public.hub_admin_moderate(text,text,text,bigint,text,integer,text);
drop function public.hub_self_restrictions(text,text);
notify pgrst,'reload schema';
commit;
