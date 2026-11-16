-- Ride Tracker: the rider's own data.
--
-- The app is offline-first: SwiftData on the phone is the working copy and a sync engine pushes and
-- pulls these tables. So:
--   * ids are uuids made on the phone (the same ids SwiftData uses), never generated here;
--   * every row has updated_at (set by the server, the pull cursor) and deleted_at (a tombstone,
--     so deletes reach other devices); rows are never hard-deleted by the app;
--   * a ride's GPS track is one compressed file in Storage (bucket "tracks"), never rows per point.
-- Everything here is visible to its owner only. Friends see published copies (next migration).

-- Internal helpers live in a schema the Data API doesn't expose.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

-- Keeps updated_at server-side so a phone with a wrong clock can't hide changes from other devices.
create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Profiles: one per account, created on sign-up. The display name is what friends see.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function private.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;
revoke execute on function private.create_profile_for_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.create_profile_for_new_user();

-- ---------------------------------------------------------------------------------------------
-- Rides

create table public.rides (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  notes text not null default '',
  started_at timestamptz not null,
  ended_at timestamptz not null,
  distance_meters double precision not null default 0,
  moving_seconds double precision not null default 0,
  max_speed_mps double precision not null default 0,
  avg_moving_speed_mps double precision not null default 0,
  elevation_gain_meters double precision not null default 0,
  -- Path in the "tracks" bucket: <user_id>/<ride_id>.track (TrackCodec blob).
  track_path text,
  include_screenshots boolean not null default false,
  -- "Where to?" (never shared with friends).
  destination_name text,
  destination_latitude double precision check (destination_latitude between -90 and 90),
  destination_longitude double precision check (destination_longitude between -180 and 180),
  destination_spot_id uuid,
  destination_reached_at timestamptz,
  -- The rider wants friends to see this ride (the published copy lives in shared_rides).
  shared_with_friends boolean not null default false,
  shared_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (ended_at >= started_at)
);

-- ---------------------------------------------------------------------------------------------
-- Spots

create table public.spots (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- The ride it was marked on; kept if that ride is deleted.
  ride_id uuid references public.rides (id) on delete set null,
  name text not null default '',
  name_is_suggested boolean not null default false,
  notes text not null default '',
  category text not null default 'other'
    check (category in ('viewpoint', 'food', 'fuel', 'monument', 'stay', 'mechanic', 'nature', 'other')),
  status text not null default 'visited' check (status in ('wantToGo', 'visited')),
  rating smallint check (rating between 1 and 5),
  priority smallint check (priority between 1 and 3),
  best_season text,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  altitude double precision,
  address text,
  locality text,
  google_maps_url text not null default '',
  source_url text,
  visits timestamptz[] not null default '{}',
  auto_visited_by_ride_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------------------------
-- Media links: references to items in the rider's Photos library. The photos themselves stay in
-- Photos; only items picked for friends are copied (shared_media, next migration).

create table public.media_links (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  ride_id uuid references public.rides (id) on delete cascade,
  spot_id uuid references public.spots (id) on delete cascade,
  -- PHAsset.localIdentifier on the device that made the link; cloud_identifier maps it on others.
  local_identifier text not null default '',
  cloud_identifier text,
  kind text not null default 'photo' check (kind in ('photo', 'livePhoto', 'video', 'screenshot', 'screenRecording')),
  captured_at timestamptz not null,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  is_manual boolean not null default false,
  shared_with_friends boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------------------------
-- Songs from the Music app played during a ride.

create table public.played_songs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  ride_id uuid references public.rides (id) on delete cascade,
  title text not null default '',
  artist text not null default '',
  album text not null default '',
  store_id text not null default '',
  started_at timestamptz not null,
  listened_seconds double precision not null default 0,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------------------------
-- Indexes: every policy filters on user_id, and the sync engine pulls "changed since" per user.
-- Foreign keys get their own indexes for joins and cascades.

create index rides_user_updated_idx on public.rides (user_id, updated_at);
create index spots_user_updated_idx on public.spots (user_id, updated_at);
create index spots_ride_id_idx on public.spots (ride_id);
create index media_links_user_updated_idx on public.media_links (user_id, updated_at);
create index media_links_ride_id_idx on public.media_links (ride_id);
create index media_links_spot_id_idx on public.media_links (spot_id);
create index played_songs_user_updated_idx on public.played_songs (user_id, updated_at);
create index played_songs_ride_id_idx on public.played_songs (ride_id);

create trigger touch_profiles before update on public.profiles
  for each row execute function private.touch_updated_at();
create trigger touch_rides before insert or update on public.rides
  for each row execute function private.touch_updated_at();
create trigger touch_spots before insert or update on public.spots
  for each row execute function private.touch_updated_at();
create trigger touch_media_links before insert or update on public.media_links
  for each row execute function private.touch_updated_at();
create trigger touch_played_songs before insert or update on public.played_songs
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------------------------
-- Access: signed-in riders only (no anonymous access at all), each to their own rows.
-- Deletes are tombstones (update deleted_at), so there are no DELETE grants or policies;
-- account deletion cascades from auth.users.

alter table public.profiles enable row level security;
alter table public.rides enable row level security;
alter table public.spots enable row level security;
alter table public.media_links enable row level security;
alter table public.played_songs enable row level security;

revoke all on public.profiles, public.rides, public.spots, public.media_links, public.played_songs from anon, authenticated;
grant select, update (display_name) on public.profiles to authenticated;
grant select, insert, update on public.rides, public.spots, public.media_links, public.played_songs to authenticated;

create policy "Riders read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "Riders rename themselves"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- The same four owner-only policies on each of the rider's tables.
do $$
declare
  t text;
begin
  foreach t in array array['rides', 'spots', 'media_links', 'played_songs'] loop
    execute format(
      'create policy "Riders read their own %1$s" on public.%1$I for select to authenticated
         using ((select auth.uid()) = user_id)', t);
    execute format(
      'create policy "Riders add their own %1$s" on public.%1$I for insert to authenticated
         with check ((select auth.uid()) = user_id)', t);
    execute format(
      'create policy "Riders change their own %1$s" on public.%1$I for update to authenticated
         using ((select auth.uid()) = user_id)
         with check ((select auth.uid()) = user_id)', t);
  end loop;
end;
$$;
