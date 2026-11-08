-- White Lion — Public, read-only league sharing
-- Lets a league organiser publish a no-login, read-only link to a single
-- competition's fixtures, results, table and player statistics, without
-- exposing any other data in the business workspace.
begin;

alter table public.league_competitions
  add column if not exists is_publicly_shared boolean not null default false,
  add column if not exists public_share_token uuid unique;

-- Returns a read-only snapshot of one competition for anonymous visitors.
-- Runs as the function owner (bypassing RLS on the underlying tables), but
-- the WHERE clause below is the only gate: a row is returned only for a
-- competition that is currently flagged public and whose token matches
-- exactly. No other table, and no mutation, is reachable through this
-- function.
create or replace function public.get_public_league_snapshot(p_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $wl_public$
declare
  v_competition public.league_competitions%rowtype;
begin
  if p_token is null then
    return null;
  end if;

  select * into v_competition
  from public.league_competitions
  where public_share_token = p_token and is_publicly_shared = true;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'competition', jsonb_build_object(
      'name', v_competition.name,
      'competition_type', v_competition.competition_type,
      'region', v_competition.region,
      'organiser', v_competition.organiser,
      'points_win', v_competition.points_win,
      'points_draw', v_competition.points_draw,
      'points_loss', v_competition.points_loss
    ),
    'seasons', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'name', s.name, 'starts_on', s.starts_on, 'ends_on', s.ends_on, 'status', s.status
      ) order by s.starts_on desc nulls last)
      from public.league_seasons s where s.competition_id = v_competition.id
    ), '[]'::jsonb),
    'clubs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'short_name', c.short_name, 'home_venue', c.home_venue,
        'crest_url', c.crest_url, 'status', c.status
      ) order by c.name)
      from public.league_clubs c where c.competition_id = v_competition.id
    ), '[]'::jsonb),
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'full_name', p.full_name, 'club_id', p.club_id,
        'shirt_number', p.shirt_number, 'position', p.position
      ) order by p.full_name)
      from public.league_players p where p.competition_id = v_competition.id and p.status = 'active'
    ), '[]'::jsonb),
    'fixtures', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'season_id', f.season_id, 'home_club_id', f.home_club_id, 'away_club_id', f.away_club_id,
        'kickoff_at', f.kickoff_at, 'venue', f.venue, 'matchweek', f.matchweek, 'status', f.status,
        'home_score', f.home_score, 'away_score', f.away_score
      ) order by f.kickoff_at)
      from public.league_fixtures f where f.competition_id = v_competition.id
    ), '[]'::jsonb),
    'standings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'season_id', ls.season_id, 'club_id', ls.club_id, 'club_name', ls.club_name,
        'played', ls.played, 'won', ls.won, 'drawn', ls.drawn, 'lost', ls.lost,
        'goals_for', ls.goals_for, 'goals_against', ls.goals_against,
        'goal_difference', ls.goal_difference, 'points', ls.points
      ) order by ls.season_id, ls.points desc, ls.goal_difference desc, ls.goals_for desc)
      from public.league_standings ls where ls.competition_id = v_competition.id
    ), '[]'::jsonb),
    'player_statistics', coalesce((
      select jsonb_agg(jsonb_build_object(
        'player_id', lps.player_id, 'full_name', lps.full_name, 'club_id', lps.club_id, 'club_name', lps.club_name,
        'goals', lps.goals, 'assists', lps.assists, 'yellow_cards', lps.yellow_cards, 'red_cards', lps.red_cards
      ) order by lps.goals desc, lps.assists desc)
      from public.league_player_statistics lps where lps.competition_id = v_competition.id
    ), '[]'::jsonb)
  );
end;
$wl_public$;

revoke all on function public.get_public_league_snapshot(uuid) from public;
grant execute on function public.get_public_league_snapshot(uuid) to anon, authenticated;

commit;
