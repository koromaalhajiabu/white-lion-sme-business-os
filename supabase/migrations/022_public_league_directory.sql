-- White Lion — Public directory of published leagues
-- Only competitions explicitly marked public appear in this directory.
begin;

create or replace function public.get_public_league_directory()
returns jsonb
language sql
stable
security definer
set search_path = public
as $wl_directory$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', c.name,
        'competition_type', c.competition_type,
        'region', c.region,
        'organiser', c.organiser,
        'public_share_token', c.public_share_token
      )
      order by c.created_at desc nulls last, c.name
    ),
    '[]'::jsonb
  )
  from public.league_competitions c
  where c.is_publicly_shared = true
    and c.public_share_token is not null;
$wl_directory$;

revoke all on function public.get_public_league_directory() from public;
grant execute on function public.get_public_league_directory() to anon, authenticated;

commit;
