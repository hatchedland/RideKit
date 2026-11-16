-- Ride Tracker: friends.
--
-- Same rules as before the move from CloudKit: friends-only, nothing public, one-way sharing
-- (an invite lets the friend see *your* shared rides; they invite you back to share theirs).
-- Friends never read the owner's tables. They read published copies that the app builds after
-- trimming the first and last 500 m and everything inside privacy zones, and without the
-- destination. Photos are shared only when the rider picks them, as 2048 px JPEG copies.

-- ---------------------------------------------------------------------------------------------
-- Invites and who sees whose rides

create table public.friend_invites (
  -- Unguessable (122 random bits); travels in the invite link.
  code text primary key default replace(gen_random_uuid()::text, '-', ''),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by uuid references auth.users (id) on delete set null,
  used_at timestamptz
);

-- owner_id shares their rides with friend_id.
create table public.friend_shares (
  owner_id uuid not null references auth.users (id) on delete cascade,
  friend_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  check (owner_id <> friend_id)
);

create index friend_invites_owner_idx on public.friend_invites (owner_id);
create index friend_invites_used_by_idx on public.friend_invites (used_by);
-- "Whose rides can I see?" is the hot path in every friend policy below.
create index friend_shares_friend_owner_idx on public.friend_shares (friend_id, owner_id);

-- Accepting an invite has to write a row the accepting rider doesn't own (the inviter's share),
-- so it runs with elevated rights, after checking the caller and the invite itself.
create or replace function public.accept_friend_invite(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  invite public.friend_invites%rowtype;
begin
  if me is null then
    raise exception 'Sign in to accept an invite' using errcode = '42501';
  end if;

  select * into invite from public.friend_invites where code = invite_code for update;
  if not found or invite.expires_at < now() or (invite.used_by is not null and invite.used_by <> me) then
    raise exception 'This invite is no longer valid' using errcode = 'P0002';
  end if;
  if invite.owner_id = me then
    raise exception 'That''s your own invite' using errcode = '22023';
  end if;

  insert into public.friend_shares (owner_id, friend_id) values (invite.owner_id, me)
    on conflict do nothing;
  update public.friend_invites set used_by = me, used_at = coalesce(used_at, now()) where code = invite_code;
  return invite.owner_id;
end;
$$;
revoke execute on function public.accept_friend_invite(text) from public, anon;
grant execute on function public.accept_friend_invite(text) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Published copies that friends read

create table public.shared_rides (
  ride_id uuid primary key references public.rides (id) on delete cascade,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null default '',
  started_at timestamptz not null,
  ended_at timestamptz not null,
  distance_meters double precision not null default 0,
  moving_seconds double precision not null default 0,
  max_speed_mps double precision not null default 0,
  elevation_gain_meters double precision not null default 0,
  -- Trimmed track in the "shared" bucket: <owner_id>/<ride_id>/track
  track_path text,
  -- RideKit SharedRide stops and songs, already redacted by the app.
  stops jsonb not null default '[]' check (jsonb_typeof(stops) = 'array'),
  songs jsonb not null default '[]' check (jsonb_typeof(songs) = 'array'),
  published_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.shared_media (
  id uuid primary key,
  ride_id uuid not null references public.shared_rides (ride_id) on delete cascade,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- 2048 px JPEG in the "shared" bucket: <owner_id>/<ride_id>/photos/<id>.jpg
  photo_path text not null,
  captured_at timestamptz not null,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  stop_id text,
  created_at timestamptz not null default now()
);

-- One live ride per rider at a time; friends follow it through Realtime.
create table public.live_rides (
  owner_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  ride_id uuid not null,
  ride_name text not null default '',
  started_at timestamptz not null,
  updated_at timestamptz not null default now(),
  distance_meters double precision not null default 0,
  is_paused boolean not null default false,
  -- Last position and the road so far, both already outside the hidden start and privacy zones.
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  path jsonb not null default '[]' check (jsonb_typeof(path) = 'array')
);

create index shared_rides_owner_published_idx on public.shared_rides (owner_id, published_at desc);
create index shared_media_ride_id_idx on public.shared_media (ride_id);
create index shared_media_owner_idx on public.shared_media (owner_id);

create trigger touch_shared_rides before insert or update on public.shared_rides
  for each row execute function private.touch_updated_at();
create trigger touch_live_rides before insert or update on public.live_rides
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------------------------
-- Access

alter table public.friend_invites enable row level security;
alter table public.friend_shares enable row level security;
alter table public.shared_rides enable row level security;
alter table public.shared_media enable row level security;
alter table public.live_rides enable row level security;

revoke all on public.friend_invites, public.friend_shares, public.shared_rides, public.shared_media, public.live_rides
  from anon, authenticated;
grant select, insert, delete on public.friend_invites to authenticated;
grant select, delete on public.friend_shares to authenticated;
grant select, insert, update, delete on public.shared_rides, public.shared_media, public.live_rides to authenticated;

-- Invites: only the inviter sees and manages them; accepting goes through accept_friend_invite.
create policy "Riders see their own invites"
  on public.friend_invites for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy "Riders create their own invites"
  on public.friend_invites for insert to authenticated
  with check ((select auth.uid()) = owner_id and used_by is null and used_at is null);
create policy "Riders withdraw their own invites"
  on public.friend_invites for delete to authenticated
  using ((select auth.uid()) = owner_id);

-- Shares: both sides can see the link and end it (stop sharing / stop following).
create policy "Both riders see a share"
  on public.friend_shares for select to authenticated
  using ((select auth.uid()) in (owner_id, friend_id));
create policy "Either rider ends a share"
  on public.friend_shares for delete to authenticated
  using ((select auth.uid()) in (owner_id, friend_id));

-- Friends see each other's display names, nothing else from the profile.
create policy "Friends read each other's profile"
  on public.profiles for select to authenticated
  using (
    exists (
      select 1 from public.friend_shares s
      where (s.owner_id = profiles.id and s.friend_id = (select auth.uid()))
         or (s.owner_id = (select auth.uid()) and s.friend_id = profiles.id)
    )
  );

-- Published rides and photos: the owner manages them; friends they share with can read them.
create policy "Owners manage their shared rides"
  on public.shared_rides for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check (
    (select auth.uid()) = owner_id
    and exists (select 1 from public.rides r where r.id = ride_id and r.user_id = (select auth.uid()))
  );
create policy "Friends read shared rides"
  on public.shared_rides for select to authenticated
  using (exists (
    select 1 from public.friend_shares s
    where s.owner_id = shared_rides.owner_id and s.friend_id = (select auth.uid())
  ));

create policy "Owners manage their shared photos"
  on public.shared_media for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check (
    (select auth.uid()) = owner_id
    and exists (select 1 from public.shared_rides r where r.ride_id = shared_media.ride_id and r.owner_id = (select auth.uid()))
  );
create policy "Friends read shared photos"
  on public.shared_media for select to authenticated
  using (exists (
    select 1 from public.friend_shares s
    where s.owner_id = shared_media.owner_id and s.friend_id = (select auth.uid())
  ));

-- Live: the rider publishes about once a minute; friends see it for at most 12 hours.
create policy "Riders manage their live ride"
  on public.live_rides for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy "Friends follow a live ride"
  on public.live_rides for select to authenticated
  using (
    started_at > now() - interval '12 hours'
    and exists (
      select 1 from public.friend_shares s
      where s.owner_id = live_rides.owner_id and s.friend_id = (select auth.uid())
    )
  );

-- Realtime pushes live position changes to friends (it applies the select policies above).
alter publication supabase_realtime add table public.live_rides;
