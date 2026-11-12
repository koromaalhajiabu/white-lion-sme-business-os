-- 042_league_edit_and_freeze.sql
-- Lets a league be edited after creation and frozen/unfrozen, and lets a
-- delegated League admin (competition_admin) manage their own competition
-- row the same way they can already manage its seasons and clubs.

alter table public.league_competitions
  add column if not exists is_frozen boolean not null default false,
  add column if not exists frozen_at timestamptz,
  add column if not exists frozen_by uuid references auth.users(id);

-- Broaden the manage policy so a delegated League admin can edit and
-- freeze/unfreeze their own league, matching the pattern already used by
-- league_seasons_manage / league_clubs_manage.
drop policy if exists league_competitions_manage on public.league_competitions;
create policy league_competitions_manage on public.league_competitions for all to authenticated
using (public.league_user_has_role(business_id, id, array['owner','admin','manager','competition_admin']))
with check (public.league_user_has_role(business_id, id, array['owner','admin','manager','competition_admin']));

-- Freeze enforcement: while a league is frozen, block inserts/updates/deletes
-- on its seasons, clubs, players, fixtures, match events and disciplinary
-- records. league_competitions itself is NOT guarded (so it can be
-- unfrozen), and league_competition_members is NOT guarded (so admin
-- assignment keeps working while frozen).
create or replace function public.league_block_if_frozen()
returns trigger
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  v_frozen boolean;
  v_cid uuid := coalesce(new.competition_id, old.competition_id);
begin
  select is_frozen into v_frozen from public.league_competitions where id = v_cid;
  if coalesce(v_frozen,false) then
    raise exception 'This league is frozen. Unfreeze it before making changes.' using errcode='42501';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists league_seasons_frozen_guard on public.league_seasons;
create trigger league_seasons_frozen_guard before insert or update or delete on public.league_seasons
for each row execute function public.league_block_if_frozen();

drop trigger if exists league_clubs_frozen_guard on public.league_clubs;
create trigger league_clubs_frozen_guard before insert or update or delete on public.league_clubs
for each row execute function public.league_block_if_frozen();

drop trigger if exists league_players_frozen_guard on public.league_players;
create trigger league_players_frozen_guard before insert or update or delete on public.league_players
for each row execute function public.league_block_if_frozen();

drop trigger if exists league_fixtures_frozen_guard on public.league_fixtures;
create trigger league_fixtures_frozen_guard before insert or update or delete on public.league_fixtures
for each row execute function public.league_block_if_frozen();

drop trigger if exists league_match_events_frozen_guard on public.league_match_events;
create trigger league_match_events_frozen_guard before insert or update or delete on public.league_match_events
for each row execute function public.league_block_if_frozen();

drop trigger if exists league_disciplinary_actions_frozen_guard on public.league_disciplinary_actions;
create trigger league_disciplinary_actions_frozen_guard before insert or update or delete on public.league_disciplinary_actions
for each row execute function public.league_block_if_frozen();
