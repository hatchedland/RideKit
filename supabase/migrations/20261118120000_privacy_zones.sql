-- Ride Tracker: privacy zones live in the account, and the server applies them.
--
-- Until now zones and "hide ride ends" were only on the phone, so a new phone (or the Android app)
-- started without them, and every app had to trim shared rides itself. Now:
-- 1. privacy_zones + profiles.hide_ride_ends hold the rider's choices (owner only).
-- 2. The publish-shared-ride Edge Function reads them and trims every shared ride on the server.
-- 3. Live rides: a position inside a zone never reaches friends, whatever the app sends.
--    (The hidden first 500 m of a live ride stays in the app: the server doesn't know the start.)

create table public.privacy_zones (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  radius_meters double precision not null default 500 check (radius_meters between 50 and 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index privacy_zones_user_id_idx on public.privacy_zones (user_id);
create trigger touch_privacy_zones before insert or update on public.privacy_zones
  for each row execute function private.touch_updated_at();

alter table public.privacy_zones enable row level security;
revoke all on public.privacy_zones from anon, authenticated;
grant select, insert, update, delete on public.privacy_zones to authenticated;

create policy "Riders read their own privacy zones" on public.privacy_zones
  for select to authenticated using ((select auth.uid()) = user_id);
create policy "Riders add their own privacy zones" on public.privacy_zones
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Riders change their own privacy zones" on public.privacy_zones
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Riders remove their own privacy zones" on public.privacy_zones
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Cut the first and last 500 m of every shared ride. On by default.
alter table public.profiles add column hide_ride_ends boolean not null default true;
grant update (hide_ride_ends) on public.profiles to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Distance and zone test, the same haversine as RideKit's Coordinate.distance.

create or replace function private.distance_meters(lat1 double precision, lon1 double precision,
                                                   lat2 double precision, lon2 double precision)
returns double precision
language sql
immutable
parallel safe
set search_path = ''
as $$
  select 2 * 6371008.8 * atan2(sqrt(h), sqrt(1 - h))
  from (select sin(radians(lat2 - lat1) / 2) ^ 2
             + cos(radians(lat1)) * cos(radians(lat2)) * sin(radians(lon2 - lon1) / 2) ^ 2 as h) as x;
$$;

create or replace function private.in_privacy_zone(owner uuid, lat double precision, lon double precision)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.privacy_zones z
    where z.user_id = owner
      and private.distance_meters(z.latitude, z.longitude, lat, lon) <= z.radius_meters
  );
$$;
revoke execute on function private.in_privacy_zone(uuid, double precision, double precision) from public, anon, authenticated;

-- Live rides: drop path points inside the rider's zones; a position inside one keeps the last
-- position friends already saw, and a ride that starts inside one isn't shown until it leaves.
create or replace function private.hide_live_ride_in_zones()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.path := coalesce((
    select jsonb_agg(p.value order by p.ordinality)
    from jsonb_array_elements(new.path) with ordinality as p
    where not private.in_privacy_zone(new.owner_id, (p.value ->> 'latitude')::double precision,
                                      (p.value ->> 'longitude')::double precision)
  ), '[]'::jsonb);

  if new.latitude is not null and new.longitude is not null
     and private.in_privacy_zone(new.owner_id, new.latitude, new.longitude) then
    if tg_op = 'INSERT' or old.latitude is null then
      return null;  -- nothing friends may see yet
    end if;
    new.latitude := old.latitude;
    new.longitude := old.longitude;
  end if;
  return new;
end;
$$;
revoke execute on function private.hide_live_ride_in_zones() from public, anon, authenticated;

create trigger hide_live_ride_in_zones before insert or update on public.live_rides
  for each row execute function private.hide_live_ride_in_zones();
