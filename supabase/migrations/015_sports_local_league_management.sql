-- White Lion Sports & Local League Management
-- Multi-competition, business-tenant isolated schema.
begin;

create table if not exists public.league_competitions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  competition_type text not null default 'League'
    check (competition_type in ('League','Cup','Tournament','School League','Community League','Other')),
  region text,
  organiser text,
  points_win integer not null default 3 check (points_win between 0 and 10),
  points_draw integer not null default 1 check (points_draw between 0 and 10),
  points_loss integer not null default 0 check (points_loss between 0 and 10),
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id,business_id),
  unique (business_id,name)
);

create table if not exists public.league_seasons (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  competition_id uuid not null,
  name text not null,
  starts_on date,
  ends_on date,
  status text not null default 'planned' check (status in ('planned','active','completed','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id,business_id,competition_id),
  unique (competition_id,name),
  foreign key (competition_id,business_id) references public.league_competitions(id,business_id) on delete cascade,
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);

create table if not exists public.league_clubs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  competition_id uuid not null,
  name text not null,
  short_name text,
  home_venue text,
  manager_name text,
  contact_phone text,
  crest_url text,
  status text not null default 'active' check (status in ('active','inactive','withdrawn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id,business_id,competition_id),
  unique (competition_id,name),
  foreign key (competition_id,business_id) references public.league_competitions(id,business_id) on delete cascade
);

create table if not exists public.league_players (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  competition_id uuid not null,
  club_id uuid not null,
  full_name text not null,
  shirt_number integer check (shirt_number between 1 and 99),
  position text,
  date_of_birth date,
  nationality text,
  photo_url text,
  status text not null default 'active' check (status in ('active','inactive','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id,business_id,competition_id,club_id),
  foreign key (club_id,business_id,competition_id) references public.league_clubs(id,business_id,competition_id) on delete cascade
);

create table if not exists public.league_fixtures (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  competition_id uuid not null,
  season_id uuid not null,
  home_club_id uuid not null,
  away_club_id uuid not null,
  kickoff_at timestamptz,
  venue text,
  matchweek text,
  status text not null default 'scheduled' check (status in ('scheduled','postponed','cancelled','completed')),
  home_score integer check (home_score is null or home_score >= 0),
  away_score integer check (away_score is null or away_score >= 0),
  referee_name text,
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  finalised_by uuid references auth.users(id),
  finalised_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id,business_id,competition_id),
  foreign key (season_id,business_id,competition_id) references public.league_seasons(id,business_id,competition_id) on delete cascade,
  foreign key (home_club_id,business_id,competition_id) references public.league_clubs(id,business_id,competition_id),
  foreign key (away_club_id,business_id,competition_id) references public.league_clubs(id,business_id,competition_id),
  check (home_club_id <> away_club_id),
  check ((status <> 'completed') or (home_score is not null and away_score is not null))
);

create table if not exists public.league_match_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  competition_id uuid not null,
  fixture_id uuid not null,
  club_id uuid not null,
  player_id uuid,
  event_type text not null check (event_type in ('goal','own_goal','assist','yellow_card','red_card','substitution_on','substitution_off','penalty_scored','penalty_missed')),
  minute integer check (minute is null or minute between 0 and 150),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (fixture_id,business_id,competition_id) references public.league_fixtures(id,business_id,competition_id) on delete cascade,
  foreign key (club_id,business_id,competition_id) references public.league_clubs(id,business_id,competition_id),
  foreign key (player_id,business_id,competition_id,club_id) references public.league_players(id,business_id,competition_id,club_id)
);

create table if not exists public.league_disciplinary_actions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  competition_id uuid not null,
  club_id uuid not null,
  player_id uuid not null,
  fixture_id uuid,
  action_type text not null check (action_type in ('warning','yellow_card','red_card','suspension','fine','other')),
  matches_suspended integer not null default 0 check (matches_suspended >= 0),
  details text not null,
  starts_on date,
  ends_on date,
  status text not null default 'active' check (status in ('active','served','appealed','cancelled')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (club_id,business_id,competition_id) references public.league_clubs(id,business_id,competition_id),
  foreign key (player_id,business_id,competition_id,club_id) references public.league_players(id,business_id,competition_id,club_id),
  foreign key (fixture_id,business_id,competition_id) references public.league_fixtures(id,business_id,competition_id) on delete restrict
);

create table if not exists public.league_competition_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  competition_id uuid not null,
  user_id uuid not null,
  role text not null check (role in ('competition_admin','club_manager','referee','disciplinary_officer','viewer')),
  club_id uuid,
  is_active boolean not null default true,
  assigned_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (competition_id,user_id,role),
  foreign key (competition_id,business_id) references public.league_competitions(id,business_id) on delete cascade,
  foreign key (business_id,user_id) references public.business_members(business_id,user_id) on delete cascade,
  foreign key (club_id,business_id,competition_id) references public.league_clubs(id,business_id,competition_id) on delete cascade
);

create index if not exists league_seasons_competition_idx on public.league_seasons(business_id,competition_id,status);
create index if not exists league_clubs_competition_idx on public.league_clubs(business_id,competition_id,status);
create index if not exists league_players_club_idx on public.league_players(business_id,competition_id,club_id,status);
create index if not exists league_fixtures_schedule_idx on public.league_fixtures(business_id,competition_id,season_id,kickoff_at);
create index if not exists league_events_fixture_idx on public.league_match_events(business_id,competition_id,fixture_id,event_type);
create index if not exists league_discipline_player_idx on public.league_disciplinary_actions(business_id,competition_id,player_id,status);

create or replace function public.league_user_has_role(p_business_id uuid,p_competition_id uuid,p_roles text[])
returns boolean
language sql
stable
security definer
set search_path=public,auth
as $$
  select auth.uid() is not null and (
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
  );
$$;

revoke all on function public.league_user_has_role(uuid,uuid,text[]) from public;
grant execute on function public.league_user_has_role(uuid,uuid,text[]) to authenticated;

create or replace function public.league_user_can_manage_club(p_business_id uuid,p_competition_id uuid,p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public,auth
as $wl_league$
  select auth.uid() is not null and (
    exists (select 1 from public.business_members bm
      where bm.business_id=p_business_id and bm.user_id=auth.uid()
        and bm.is_active and bm.role::text=any(array['owner','admin','manager']))
    or exists (select 1 from public.league_competition_members cm
      where cm.business_id=p_business_id and cm.competition_id=p_competition_id
        and cm.user_id=auth.uid() and cm.is_active and (
          cm.role='competition_admin' or
          (cm.role in ('club_manager','disciplinary_officer') and (cm.club_id is null or cm.club_id=p_club_id))
        ))
  );
$wl_league$;

create or replace function public.league_user_can_manage_fixture(p_business_id uuid,p_competition_id uuid,p_fixture_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public,auth
as $wl_league$
  select auth.uid() is not null and (
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
  );
$wl_league$;

revoke all on function public.league_user_can_manage_club(uuid,uuid,uuid) from public;
revoke all on function public.league_user_can_manage_fixture(uuid,uuid,uuid) from public;
grant execute on function public.league_user_can_manage_club(uuid,uuid,uuid) to authenticated;
grant execute on function public.league_user_can_manage_fixture(uuid,uuid,uuid) to authenticated;

alter table public.league_competitions enable row level security;
alter table public.league_seasons enable row level security;
alter table public.league_clubs enable row level security;
alter table public.league_players enable row level security;
alter table public.league_fixtures enable row level security;
alter table public.league_match_events enable row level security;
alter table public.league_disciplinary_actions enable row level security;
alter table public.league_competition_members enable row level security;

drop policy if exists league_competitions_read on public.league_competitions;
create policy league_competitions_read on public.league_competitions for select to authenticated
using (public.is_business_member(business_id));
drop policy if exists league_competitions_manage on public.league_competitions;
create policy league_competitions_manage on public.league_competitions for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

drop policy if exists league_seasons_read on public.league_seasons;
create policy league_seasons_read on public.league_seasons for select to authenticated using (public.is_business_member(business_id));
drop policy if exists league_seasons_manage on public.league_seasons;
create policy league_seasons_manage on public.league_seasons for all to authenticated
using (public.league_user_has_role(business_id,competition_id,array['owner','admin','manager','competition_admin']))
with check (public.league_user_has_role(business_id,competition_id,array['owner','admin','manager','competition_admin']));

drop policy if exists league_clubs_read on public.league_clubs;
create policy league_clubs_read on public.league_clubs for select to authenticated using (public.is_business_member(business_id));
drop policy if exists league_clubs_manage on public.league_clubs;
create policy league_clubs_manage on public.league_clubs for all to authenticated
using (public.league_user_has_role(business_id,competition_id,array['owner','admin','manager','competition_admin']))
with check (public.league_user_has_role(business_id,competition_id,array['owner','admin','manager','competition_admin']));

drop policy if exists league_players_read on public.league_players;
create policy league_players_read on public.league_players for select to authenticated using (public.is_business_member(business_id));
drop policy if exists league_players_manage on public.league_players;
create policy league_players_manage on public.league_players for all to authenticated
using (public.league_user_can_manage_club(business_id,competition_id,club_id))
with check (public.league_user_can_manage_club(business_id,competition_id,club_id));

drop policy if exists league_fixtures_read on public.league_fixtures;
create policy league_fixtures_read on public.league_fixtures for select to authenticated using (public.is_business_member(business_id));
drop policy if exists league_fixtures_manage on public.league_fixtures;
create policy league_fixtures_manage on public.league_fixtures for all to authenticated
using (public.league_user_can_manage_fixture(business_id,competition_id,id))
with check (public.league_user_can_manage_fixture(business_id,competition_id,id));

drop policy if exists league_events_read on public.league_match_events;
create policy league_events_read on public.league_match_events for select to authenticated using (public.is_business_member(business_id));
drop policy if exists league_events_manage on public.league_match_events;
create policy league_events_manage on public.league_match_events for all to authenticated
using (public.league_user_can_manage_fixture(business_id,competition_id,fixture_id))
with check (public.league_user_can_manage_fixture(business_id,competition_id,fixture_id));

drop policy if exists league_discipline_read on public.league_disciplinary_actions;
create policy league_discipline_read on public.league_disciplinary_actions for select to authenticated using (public.is_business_member(business_id));
drop policy if exists league_discipline_manage on public.league_disciplinary_actions;
create policy league_discipline_manage on public.league_disciplinary_actions for all to authenticated
using (public.league_user_can_manage_club(business_id,competition_id,club_id))
with check (public.league_user_can_manage_club(business_id,competition_id,club_id));

drop policy if exists league_members_read on public.league_competition_members;
create policy league_members_read on public.league_competition_members for select to authenticated using (public.is_business_member(business_id));
drop policy if exists league_members_manage on public.league_competition_members;
create policy league_members_manage on public.league_competition_members for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

create or replace view public.league_standings with (security_invoker=true) as
with played as (
  select f.business_id,f.competition_id,f.season_id,f.home_club_id as club_id,
    1 as played, case when f.home_score>f.away_score then 1 else 0 end as won,
    case when f.home_score=f.away_score then 1 else 0 end as drawn,
    case when f.home_score<f.away_score then 1 else 0 end as lost,
    f.home_score as goals_for,f.away_score as goals_against
  from public.league_fixtures f where f.status='completed'
  union all
  select f.business_id,f.competition_id,f.season_id,f.away_club_id,
    1,case when f.away_score>f.home_score then 1 else 0 end,
    case when f.away_score=f.home_score then 1 else 0 end,
    case when f.away_score<f.home_score then 1 else 0 end,
    f.away_score,f.home_score
  from public.league_fixtures f where f.status='completed'
),
totals as (
  select business_id,competition_id,season_id,club_id,count(*)::integer as played,
    sum(won)::integer as won,sum(drawn)::integer as drawn,sum(lost)::integer as lost,
    sum(goals_for)::integer as goals_for,sum(goals_against)::integer as goals_against
  from played group by business_id,competition_id,season_id,club_id
)
select c.business_id,c.competition_id,s.id as season_id,c.id as club_id,c.name as club_name,
  coalesce(t.played,0) as played,coalesce(t.won,0) as won,coalesce(t.drawn,0) as drawn,
  coalesce(t.lost,0) as lost,coalesce(t.goals_for,0) as goals_for,
  coalesce(t.goals_against,0) as goals_against,
  coalesce(t.goals_for,0)-coalesce(t.goals_against,0) as goal_difference,
  coalesce(t.won,0)*co.points_win+coalesce(t.drawn,0)*co.points_draw+coalesce(t.lost,0)*co.points_loss as points
from public.league_seasons s
join public.league_competitions co on co.id=s.competition_id and co.business_id=s.business_id
join public.league_clubs c on c.competition_id=s.competition_id and c.business_id=s.business_id
left join totals t on t.club_id=c.id and t.business_id=c.business_id and t.competition_id=c.competition_id and t.season_id=s.id
where c.status='active';

create or replace view public.league_player_statistics with (security_invoker=true) as
select p.business_id,p.competition_id,p.club_id,p.id as player_id,p.full_name,c.name as club_name,
  count(*) filter (where e.event_type in ('goal','penalty_scored'))::integer as goals,
  count(*) filter (where e.event_type='assist')::integer as assists,
  count(*) filter (where e.event_type='yellow_card')::integer as yellow_cards,
  count(*) filter (where e.event_type='red_card')::integer as red_cards
from public.league_players p
join public.league_clubs c on c.id=p.club_id and c.business_id=p.business_id and c.competition_id=p.competition_id
left join public.league_match_events e on e.player_id=p.id and e.business_id=p.business_id and e.competition_id=p.competition_id
group by p.business_id,p.competition_id,p.club_id,p.id,p.full_name,c.name;

grant select on public.league_standings,public.league_player_statistics to authenticated;
grant select,insert,update,delete on public.league_competitions,public.league_seasons,public.league_clubs,public.league_players,public.league_fixtures,public.league_match_events,public.league_disciplinary_actions,public.league_competition_members to authenticated;

insert into public.business_industry_modules(business_id,module_key,is_enabled,configuration)
select id,'sports_league',false,'{"label":"Sports & Local League Management","version":1}'::jsonb
from public.businesses
on conflict (business_id,module_key) do nothing;

commit;
