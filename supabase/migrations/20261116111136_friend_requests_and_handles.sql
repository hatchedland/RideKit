-- Ride Tracker: in-app friends. Riders find each other by @handle and send friend requests;
-- accepting makes them friends both ways (each sees the other's shared and live rides).
-- Replaces invite links (friend_invites stays for history; the app no longer uses it).

-- ---------------------------------------------------------------------------------------------
-- @handles: unique, lowercase, 3–20 of a–z 0–9 _ .

alter table public.profiles add column username text
  check (username ~ '^[a-z0-9_.]{3,20}$');
create unique index profiles_username_key on public.profiles (username);
grant update (display_name, username) on public.profiles to authenticated;

-- Search exposes only handle and name (never email), at most 10 riders, never yourself, and needs
-- at least two characters.
create or replace function private.search_riders(query text)
returns table (id uuid, username text, display_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name
  from public.profiles p
  where (select auth.uid()) is not null
    and char_length(trim(query)) >= 2
    and p.username like lower(trim(leading '@' from trim(query))) || '%'
    and p.id <> (select auth.uid())
  order by p.username
  limit 10;
$$;
revoke execute on function private.search_riders(text) from public, anon;
grant execute on function private.search_riders(text) to authenticated;

create or replace function public.search_riders(query text)
returns table (id uuid, username text, display_name text)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.search_riders(query);
$$;
revoke execute on function public.search_riders(text) from public, anon;
grant execute on function public.search_riders(text) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Friend requests: a pending row; accepting turns it into friend_shares both ways.

create table public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  to_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (from_id, to_id),
  check (from_id <> to_id)
);
create index friend_requests_to_idx on public.friend_requests (to_id);

alter table public.friend_requests enable row level security;
revoke all on public.friend_requests from anon, authenticated;
grant select, insert, delete on public.friend_requests to authenticated;

create policy "Both riders see a request"
  on public.friend_requests for select to authenticated
  using ((select auth.uid()) in (from_id, to_id));
create policy "Riders send their own requests"
  on public.friend_requests for insert to authenticated
  with check ((select auth.uid()) = from_id);
create policy "Either rider cancels or declines a request"
  on public.friend_requests for delete to authenticated
  using ((select auth.uid()) in (from_id, to_id));

-- Names on requests: riders also read the profile of anyone with a request to or from them.
alter policy "Riders read their own and their friends' profiles" on public.profiles
  using (
    (select auth.uid()) = id
    or exists (
      select 1 from public.friend_shares s
      where (s.owner_id = profiles.id and s.friend_id = (select auth.uid()))
         or (s.owner_id = (select auth.uid()) and s.friend_id = profiles.id)
    )
    or exists (
      select 1 from public.friend_requests r
      where (r.from_id = profiles.id and r.to_id = (select auth.uid()))
         or (r.from_id = (select auth.uid()) and r.to_id = profiles.id)
    )
  );

-- Accepting writes the other rider's share, so it runs with elevated rights after checking that
-- the caller is the rider the request was sent to.
create or replace function private.accept_friend_request(request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  request public.friend_requests%rowtype;
begin
  select * into request from public.friend_requests where id = request_id for update;
  if not found or request.to_id is distinct from me then
    raise exception 'This request is no longer there' using errcode = 'P0002';
  end if;
  insert into public.friend_shares (owner_id, friend_id)
    values (request.from_id, me), (me, request.from_id)
    on conflict do nothing;
  -- Accepting one also settles a request the other way, if both asked.
  delete from public.friend_requests
    where (from_id = request.from_id and to_id = me) or (from_id = me and to_id = request.from_id);
  return request.from_id;
end;
$$;
revoke execute on function private.accept_friend_request(uuid) from public, anon;
grant execute on function private.accept_friend_request(uuid) to authenticated;

create or replace function public.accept_friend_request(request_id uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.accept_friend_request(request_id);
$$;
revoke execute on function public.accept_friend_request(uuid) from public, anon;
grant execute on function public.accept_friend_request(uuid) to authenticated;
