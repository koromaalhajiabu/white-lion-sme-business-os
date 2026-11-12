-- 044_league_freeze_developer_only.sql
-- Freezing/unfreezing a league is now a platform-developer-only power.
-- Business owners/admins/managers and delegated league admins
-- (competition_admin) can still edit a league's other details, but a
-- database trigger blocks any attempt by anyone else to change
-- is_frozen / frozen_at / frozen_by, no matter which code path is used
-- (UI, console, direct API call).
begin;

create or replace function public.league_guard_freeze_columns()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if (new.is_frozen is distinct from old.is_frozen
      or new.frozen_at is distinct from old.frozen_at
      or new.frozen_by is distinct from old.frozen_by)
     and not public.is_platform_developer() then
    raise exception 'Only the platform developer can freeze or unfreeze a league.';
  end if;
  return new;
end;
$$;

drop trigger if exists league_competitions_freeze_guard on public.league_competitions;
create trigger league_competitions_freeze_guard before update on public.league_competitions
for each row execute function public.league_guard_freeze_columns();

commit;
