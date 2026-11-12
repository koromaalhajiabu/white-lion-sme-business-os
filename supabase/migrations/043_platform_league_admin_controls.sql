-- 043_platform_league_admin_controls.sql
-- Gives the platform developer total control over leagues and league admins
-- across every business: add/edit/remove any league admin assignment, and
-- freeze/unfreeze any league directly, without needing business membership.
begin;

-- The platform developer must bypass league-level RLS the same way they
-- already bypass business-level RLS (is_business_member / has_business_role).
create or replace function public.league_user_has_role(p_business_id uuid,p_competition_id uuid,p_roles text[])
returns boolean
language sql
stable
security definer
set search_path=public,auth
as $$
  select public.is_platform_developer() or (auth.uid() is not null and (
    exists (
      select 1 from public.business_members bm
      where bm.business_id=p_business_id and bm.user_id=auth.uid()
        and bm.is_active and bm.role::text = any(p_roles)
    )
    or exists (
      select 1 from public.league_competition_members cm
      where cm.business_id=p_business_id and cm.competition_id=p_competition_id
        and cm.user_id=auth.uid() and cm.is_active and cm.role=any(p_roles)
    )
  ));
$$;

create or replace function public.league_user_can_manage_club(p_business_id uuid,p_competition_id uuid,p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public,auth
as $wl_league$
  select public.is_platform_developer() or (auth.uid() is not null and (
    exists (select 1 from public.business_members bm
      where bm.business_id=p_business_id and bm.user_id=auth.uid()
        and bm.is_active and bm.role::text=any(array['owner','admin','manager']))
    or exists (select 1 from public.league_competition_members cm
      where cm.business_id=p_business_id and cm.competition_id=p_competition_id
        and cm.user_id=auth.uid() and cm.is_active and (
          cm.role='competition_admin' or
          (cm.role='club_manager' and (cm.club_id is null or cm.club_id=p_club_id))
        ))
  ));
$wl_league$;

create or replace function public.league_user_can_manage_fixture(p_business_id uuid,p_competition_id uuid,p_fixture_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public,auth
as $wl_league$
  select public.is_platform_developer() or (auth.uid() is not null and (
    exists (select 1 from public.business_members bm
      where bm.business_id=p_business_id and bm.user_id=auth.uid()
        and bm.is_active and bm.role::text=any(array['owner','admin','manager']))
    or exists (select 1 from public.league_competition_members cm
      where cm.business_id=p_business_id and cm.competition_id=p_competition_id
        and cm.user_id=auth.uid() and cm.is_active and cm.role='competition_admin')
    or exists (select 1 from public.league_competition_members cm
      join public.league_fixtures f on f.id=p_fixture_id and f.business_id=cm.business_id and f.competition_id=cm.competition_id
      where cm.business_id=p_business_id and cm.competition_id=p_competition_id
        and cm.user_id=auth.uid() and cm.is_active and cm.role='referee'
        and (cm.club_id is null or cm.club_id in (f.home_club_id,f.away_club_id)))
  ));
$wl_league$;

create or replace function public.league_user_can_manage_discipline(p_business_id uuid,p_competition_id uuid,p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public,auth
as $wl_discipline$
  select public.is_platform_developer() or (auth.uid() is not null and (
    exists (select 1 from public.business_members bm
      where bm.business_id=p_business_id and bm.user_id=auth.uid()
        and bm.is_active and bm.role::text=any(array['owner','admin','manager']))
    or exists (select 1 from public.league_competition_members cm
      where cm.business_id=p_business_id and cm.competition_id=p_competition_id
        and cm.user_id=auth.uid() and cm.is_active and (
          cm.role='competition_admin' or
          (cm.role='disciplinary_officer' and (cm.club_id is null or cm.club_id=p_club_id))
        ))
  ));
$wl_discipline$;

-- All leagues platform-wide, for the developer console.
create or replace function public.get_platform_leagues()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_result jsonb;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'business_id',c.business_id,
    'business_name',b.name,
    'name',c.name,
    'competition_type',c.competition_type,
    'region',c.region,
    'organiser',c.organiser,
    'status',c.status,
    'is_frozen',c.is_frozen,
    'frozen_at',c.frozen_at,
    'is_publicly_shared',c.is_publicly_shared,
    'admin_count',(select count(*) from public.league_competition_members m where m.competition_id=c.id and m.role='competition_admin' and m.is_active),
    'created_at',c.created_at
  ) order by c.created_at desc),'[]'::jsonb)
  into v_result
  from public.league_competitions c
  join public.businesses b on b.id=c.business_id;
  return v_result;
end;
$$;
revoke all on function public.get_platform_leagues() from public;
grant execute on function public.get_platform_leagues() to authenticated;

-- All league admin / role assignments platform-wide.
create or replace function public.get_platform_league_admins()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_result jsonb;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',m.id,
    'business_id',m.business_id,
    'business_name',b.name,
    'competition_id',m.competition_id,
    'league_name',c.name,
    'user_id',m.user_id,
    'email',u.email,
    'role',m.role,
    'club_id',m.club_id,
    'club_name',cl.name,
    'is_active',m.is_active,
    'created_at',m.created_at
  ) order by m.created_at desc),'[]'::jsonb)
  into v_result
  from public.league_competition_members m
  join public.league_competitions c on c.id=m.competition_id
  join public.businesses b on b.id=m.business_id
  left join auth.users u on u.id=m.user_id
  left join public.league_clubs cl on cl.id=m.club_id;
  return v_result;
end;
$$;
revoke all on function public.get_platform_league_admins() from public;
grant execute on function public.get_platform_league_admins() to authenticated;

-- Add or edit a league admin assignment for any league, by email. Ensures
-- the account has at least baseline business membership first (required by
-- league_competition_members' foreign key).
create or replace function public.set_platform_league_admin(
  p_competition_id uuid,
  p_email text,
  p_role text,
  p_club_id uuid default null,
  p_is_active boolean default true
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_business_id uuid;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  if p_role not in ('competition_admin','club_manager','referee','disciplinary_officer','viewer') then
    raise exception 'Invalid league role';
  end if;
  select business_id into v_business_id from public.league_competitions where id=p_competition_id;
  if v_business_id is null then raise exception 'League not found'; end if;
  select id into v_user_id from auth.users where lower(email)=lower(trim(p_email));
  if v_user_id is null then raise exception 'No registered account found for that email'; end if;

  insert into public.business_members(business_id,user_id,role,is_active,invited_by)
  values(v_business_id,v_user_id,'viewer',true,auth.uid())
  on conflict (business_id,user_id) do nothing;

  insert into public.league_competition_members(business_id,competition_id,user_id,role,club_id,is_active,assigned_by)
  values(v_business_id,p_competition_id,v_user_id,p_role,p_club_id,p_is_active,auth.uid())
  on conflict (competition_id,user_id,role) do update
  set club_id=excluded.club_id, is_active=excluded.is_active;

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(v_business_id,auth.uid(),'platform_league_admin_assigned','league_competition_members',v_user_id::text,
    jsonb_build_object('email',lower(trim(p_email)),'competition_id',p_competition_id,'role',p_role,'club_id',p_club_id,'is_active',p_is_active));
end;
$$;
revoke all on function public.set_platform_league_admin(uuid,text,text,uuid,boolean) from public;
grant execute on function public.set_platform_league_admin(uuid,text,text,uuid,boolean) to authenticated;

-- Remove a league admin / role assignment outright.
create or replace function public.remove_platform_league_admin(p_member_id uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_business_id uuid; v_user_id uuid;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  select business_id,user_id into v_business_id,v_user_id from public.league_competition_members where id=p_member_id;
  if v_business_id is null then raise exception 'League admin assignment not found'; end if;
  delete from public.league_competition_members where id=p_member_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(v_business_id,auth.uid(),'platform_league_admin_removed','league_competition_members',v_user_id::text,jsonb_build_object('member_id',p_member_id));
end;
$$;
revoke all on function public.remove_platform_league_admin(uuid) from public;
grant execute on function public.remove_platform_league_admin(uuid) to authenticated;

-- Freeze or unfreeze any league platform-wide, regardless of business membership.
create or replace function public.set_platform_league_freeze(p_competition_id uuid, p_is_frozen boolean)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_business_id uuid;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  update public.league_competitions
  set is_frozen=p_is_frozen,
      frozen_at=case when p_is_frozen then now() else null end,
      frozen_by=case when p_is_frozen then auth.uid() else null end,
      updated_at=now()
  where id=p_competition_id
  returning business_id into v_business_id;
  if v_business_id is null then raise exception 'League not found'; end if;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(v_business_id,auth.uid(),case when p_is_frozen then 'platform_league_frozen' else 'platform_league_unfrozen' end,'league_competitions',p_competition_id::text,jsonb_build_object('is_frozen',p_is_frozen));
end;
$$;
revoke all on function public.set_platform_league_freeze(uuid,boolean) from public;
grant execute on function public.set_platform_league_freeze(uuid,boolean) to authenticated;

commit;
