-- White Lion — public directory of published competitions
begin;

create or replace function public.list_public_leagues()
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
      order by c.name
    ),
    '[]'::jsonb
  )
  from public.league_competitions c
  where c.is_publicly_shared = true
    and c.public_share_token is not null;
$wl_directory$;

revoke all on function public.list_public_leagues() from public;
grant execute on function public.list_public_leagues() to anon, authenticated;

commit;
