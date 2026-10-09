-- Goober Hub moderation for 2.4.2. Run AFTER GOOBER_HUB.sql (and creations, if installed).
-- Re-runnable. Does not reset Journey's admin passphrase, XP, profiles or keys.
-- Hub bans are NOT GooberDash game bans. Chat mutes only restrict sending.
begin;
do $$ begin
  if to_regprocedure('public.hub_ok(text,text)') is null
     or to_regclass('public.hub_reports') is null then
    raise exception 'Run GOOBER_HUB.sql first';
  end if;
end $$;

-- An empty table is fail-closed. If not already configured, set id=1's hash in
-- SQL Editor using a strong private passphrase. Never ship that phrase in code.
create table if not exists public.journey_admin (id int primary key default 1, pass_hash text not null);
alter table public.journey_admin enable row level security;
revoke all on public.journey_admin from public,anon,authenticated;
create table if not exists public.hub_restrictions (
  user_id text primary key,
  banned_until timestamptz, muted_until timestamptz,
  updated_by text not null, updated_at timestamptz not null default now());
create table if not exists public.hub_moderation_actions (
  id bigserial primary key, nonce text unique not null,
  admin_id text not null, report_id bigint not null, target text not null,
  action text not null check(action in ('dismiss','ban','mute','unban','unmute')),
  days int not null, result jsonb not null, created_at timestamptz not null default now());
alter table public.hub_restrictions enable row level security;
alter table public.hub_moderation_actions enable row level security;
revoke all on public.hub_restrictions,public.hub_moderation_actions from public,anon,authenticated;
alter table public.hub_reports add column if not exists validated boolean not null default false;
alter table public.hub_reports add column if not exists reviewed_by text;
alter table public.hub_reports add column if not exists reviewed_at timestamptz;
create index if not exists hub_reports_review_queue on public.hub_reports(reviewed,id desc);
-- Old clients accepted a free-form target. Only validate historical reports
-- against the actual sender/recipient and exact message, never their target alone.
update public.hub_reports r set validated=true
where not r.validated and exists(select 1 from public.hub_messages m
  where m.id=r.message_id and m.sender=r.target and m.recipient=r.reporter and m.body=r.body);

create or replace function public.hub_credential_ok(p_user text,p_key text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select exists(select 1 from public.hub_keys where user_id=p_user
    and key_hash=encode(sha256(convert_to(coalesce(p_key,''),'UTF8')),'hex'));
$$;
revoke all on function public.hub_credential_ok(text,text) from public,anon,authenticated;

-- Existing authenticated Hub RPCs already use hub_ok, so bans cannot be
-- bypassed simply by using an older UI. Keep credential checking separate for
-- the user's read-only restriction status and the admin passphrase check.
create or replace function public.hub_ok(p_user text,p_key text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select public.hub_credential_ok(p_user,p_key) and not exists(
    select 1 from public.hub_restrictions where user_id=p_user and banned_until>now());
$$;
revoke all on function public.hub_ok(text,text) from public,anon,authenticated;

create or replace function public.hub_moderation_admin_ok(p_user text,p_key text,p_pass text)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
  select p_user='96c5a97d-63c9-4dd7-bf47-d5ad48bb6cf2'
    and public.hub_credential_ok(p_user,p_key)
    and coalesce(p_pass,'') not in ('','CHANGE-ME')
    and exists(select 1 from public.journey_admin where id=1
      and pass_hash=encode(sha256(convert_to(coalesce(p_pass,''),'UTF8')),'hex'));
$$;
revoke all on function public.hub_moderation_admin_ok(text,text,text) from public,anon,authenticated;

-- Preserve the deployed base implementation instead of overwriting unrelated
-- server-side fixes. Private backups are NEVER executable by client roles.
do $$ begin
  if to_regprocedure('public.hub_base_claim(text,text,text,text,text[])') is null then
    alter function public.hub_claim(text,text,text,text,text[]) rename to hub_base_claim;
  end if;
  if to_regprocedure('public.hub_base_send(text,text,text,text)') is null then
    alter function public.hub_send(text,text,text,text) rename to hub_base_send;
  end if;
  if to_regprocedure('public.hub_base_send_as_test(text,text,text)') is null then
    alter function public.hub_send_as_test(text,text,text) rename to hub_base_send_as_test;
  end if;
end $$;
revoke all on function public.hub_base_claim(text,text,text,text,text[]) from public,anon,authenticated;
revoke all on function public.hub_base_send(text,text,text,text) from public,anon,authenticated;
revoke all on function public.hub_base_send_as_test(text,text,text) from public,anon,authenticated;

create or replace function public.hub_claim(p_user text,p_key text,p_name text,p_created text,p_friends text[])
returns text language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if exists(select 1 from public.hub_restrictions where user_id=p_user and banned_until>now()) then
    raise exception 'hub banned';
  end if;
  return public.hub_base_claim(p_user,p_key,p_name,p_created,p_friends);
end $$;
create or replace function public.hub_send(p_user text,p_key text,p_to text,p_body text)
returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.hub_credential_ok(p_user,p_key) then raise exception 'not allowed'; end if;
  if exists(select 1 from public.hub_restrictions where user_id=p_user and banned_until>now()) then raise exception 'hub banned'; end if;
  if exists(select 1 from public.hub_restrictions where user_id=p_user and muted_until>now()) then raise exception 'hub muted'; end if;
  return public.hub_base_send(p_user,p_key,p_to,p_body);
end $$;
create or replace function public.hub_send_as_test(p_user text,p_key text,p_body text)
returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.hub_ok(p_user,p_key) or exists(select 1 from public.hub_restrictions where user_id=p_user and muted_until>now()) then raise exception 'not allowed'; end if;
  return public.hub_base_send_as_test(p_user,p_key,p_body);
end $$;

create or replace function public.hub_self_restrictions(p_user text,p_key text)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not public.hub_credential_ok(p_user,p_key) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_build_object('banned_until',banned_until,'muted_until',muted_until)
    from public.hub_restrictions where user_id=p_user),'{}'::jsonb);
end $$;

-- A report must be an incoming message, and target MUST be its actual sender.
-- Preserve evidence even when the message later expires. Deduplicate retries.
create or replace function public.hub_report(p_user text,p_key text,p_target text,p_message bigint,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare evidence text;
begin
  if not public.hub_ok(p_user,p_key) then raise exception 'not allowed'; end if;
  select body into evidence from public.hub_messages where id=p_message and recipient=p_user and sender=p_target;
  if not found then raise exception 'message not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hub_report:'||p_user,0));
  if exists(select 1 from public.hub_reports where reporter=p_user and message_id=p_message) then return; end if;
  if (select count(*) from public.hub_reports where reporter=p_user and created_at>now()-interval '1 day')>=20 then raise exception 'report limit reached'; end if;
  insert into public.hub_reports(reporter,target,message_id,body,reason,validated)
    values(p_user,p_target,p_message,evidence,left(coalesce(nullif(btrim(p_reason),''),'message'),120),true);
end $$;

create or replace function public.hub_admin_reports(p_user text,p_key text,p_pass text,p_reviewed boolean,p_before bigint)
returns setof jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not coalesce(public.hub_moderation_admin_ok(p_user,p_key,p_pass),false) then raise exception 'not allowed'; end if;
  return query select jsonb_build_object('id',r.id,'reporter',r.reporter,'target',r.target,
    'reporter_name',coalesce(nullif(a.name,''),r.reporter),'target_name',coalesce(nullif(b.name,''),r.target),
    'message_id',r.message_id,'body',r.body,'reason',r.reason,'created_at',r.created_at,
    'validated',r.validated,'reviewed',r.reviewed,'reviewed_at',r.reviewed_at,
    'banned_until',case when s.banned_until>now() then s.banned_until end,
    'muted_until',case when s.muted_until>now() then s.muted_until end)
  from public.hub_reports r left join public.hub_players a on a.user_id=r.reporter
    left join public.hub_players b on b.user_id=r.target left join public.hub_restrictions s on s.user_id=r.target
  where r.reviewed=coalesce(p_reviewed,false) and (coalesce(p_before,0)=0 or r.id<p_before)
  order by r.id desc limit 21;
end $$;

create or replace function public.hub_admin_moderate(p_user text,p_key text,p_pass text,p_report bigint,p_action text,p_days int,p_nonce text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.hub_reports; previous public.hub_moderation_actions; expiry timestamptz; answer jsonb;
begin
  if not coalesce(public.hub_moderation_admin_ok(p_user,p_key,p_pass),false) then raise exception 'not allowed'; end if;
  if p_action is null or p_action not in ('dismiss','ban','mute','unban','unmute')
    or coalesce(p_nonce,'') !~ '^[0-9a-f]{32}$' then raise exception 'invalid action'; end if;
  if (p_action in ('ban','mute') and (p_days is null or p_days not between 1 and 3))
    or (p_action not in ('ban','mute') and p_days is distinct from 0) then raise exception 'invalid duration'; end if;
  perform pg_advisory_xact_lock(hashtextextended('hub_moderation:'||p_nonce,0));
  select * into previous from public.hub_moderation_actions where nonce=p_nonce;
  if found then
    if previous.admin_id<>p_user or previous.report_id<>p_report or previous.action<>p_action or previous.days<>p_days then raise exception 'invalid retry'; end if;
    return previous.result;
  end if;
  select * into r from public.hub_reports where id=p_report for update;
  if not found then raise exception 'report not found'; end if;
  if r.reviewed and p_action in ('dismiss','ban','mute') then raise exception 'already reviewed'; end if;
  if p_action<>'dismiss' and (not r.validated or r.target in ('96c5a97d-63c9-4dd7-bf47-d5ad48bb6cf2','00000000-0000-4000-8000-00000000e171')) then
    raise exception 'unverified or protected target';
  end if;
  expiry := now()+make_interval(days=>p_days);
  if p_action='ban' then
    insert into public.hub_restrictions(user_id,banned_until,updated_by) values(r.target,expiry,p_user)
    on conflict(user_id) do update set banned_until=greatest(public.hub_restrictions.banned_until,expiry),updated_by=p_user,updated_at=now();
  elsif p_action='mute' then
    insert into public.hub_restrictions(user_id,muted_until,updated_by) values(r.target,expiry,p_user)
    on conflict(user_id) do update set muted_until=greatest(public.hub_restrictions.muted_until,expiry),updated_by=p_user,updated_at=now();
  elsif p_action='unban' then
    update public.hub_restrictions set banned_until=null,updated_by=p_user,updated_at=now() where user_id=r.target;
  elsif p_action='unmute' then
    update public.hub_restrictions set muted_until=null,updated_by=p_user,updated_at=now() where user_id=r.target;
  end if;
  update public.hub_reports set reviewed=true,reviewed_by=p_user,reviewed_at=now() where id=r.id;
  answer := jsonb_build_object('report',r.id,'action',p_action,'days',p_days,'target',r.target);
  insert into public.hub_moderation_actions(nonce,admin_id,report_id,target,action,days,result)
    values(p_nonce,p_user,r.id,r.target,p_action,p_days,answer);
  return answer;
end $$;

do $$ declare signature text; begin
  foreach signature in array array[
    'hub_claim(text,text,text,text,text[])','hub_send(text,text,text,text)','hub_send_as_test(text,text,text)',
    'hub_self_restrictions(text,text)','hub_report(text,text,text,bigint,text)',
    'hub_admin_reports(text,text,text,boolean,bigint)','hub_admin_moderate(text,text,text,bigint,text,integer,text)'
  ] loop
    execute 'revoke all on function public.'||signature||' from public,anon,authenticated';
    execute 'grant execute on function public.'||signature||' to anon';
  end loop;
end $$;
notify pgrst,'reload schema';
commit;
