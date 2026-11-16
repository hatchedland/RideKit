-- Ride Tracker: tidy-ups from the Supabase advisors after the first three migrations.
--
-- 1. accept_friend_invite: the elevated part moves to the unexposed "private" schema; the API keeps
--    a plain (security invoker) wrapper with the same name and signature.
-- 2. One SELECT policy per table instead of two permissive ones (owner + friend), and the owners'
--    "for all" policies split into insert / update / delete so they no longer add a second SELECT.

-- 1 ---------------------------------------------------------------------------------------------

create or replace function private.accept_friend_invite(invite_code text)
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
revoke execute on function private.accept_friend_invite(text) from public, anon;
grant execute on function private.accept_friend_invite(text) to authenticated;

create or replace function public.accept_friend_invite(invite_code text)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.accept_friend_invite(invite_code);
$$;
revoke execute on function public.accept_friend_invite(text) from public, anon;
grant execute on function public.accept_friend_invite(text) to authenticated;

-- 2 ---------------------------------------------------------------------------------------------

-- profiles
drop policy "Riders read their own profile" on public.profiles;
drop policy "Friends read each other's profile" on public.profiles;
create policy "Riders read their own and their friends' profiles"
  on public.profiles for select to authenticated
  using (
    (select auth.uid()) = id
    or exists (
      select 1 from public.friend_shares s
      where (s.owner_id = profiles.id and s.friend_id = (select auth.uid()))
         or (s.owner_id = (select auth.uid()) and s.friend_id = profiles.id)
    )
  );

-- shared_rides
drop policy "Owners manage their shared rides" on public.shared_rides;
drop policy "Friends read shared rides" on public.shared_rides;
create policy "Owners and their friends read shared rides"
  on public.shared_rides for select to authenticated
  using (
    (select auth.uid()) = owner_id
    or exists (
      select 1 from public.friend_shares s
      where s.owner_id = shared_rides.owner_id and s.friend_id = (select auth.uid())
    )
  );
create policy "Owners publish their own rides"
  on public.shared_rides for insert to authenticated
  with check (
    (select auth.uid()) = owner_id
    and exists (select 1 from public.rides r where r.id = ride_id and r.user_id = (select auth.uid()))
  );
create policy "Owners update their shared rides"
  on public.shared_rides for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check (
    (select auth.uid()) = owner_id
    and exists (select 1 from public.rides r where r.id = ride_id and r.user_id = (select auth.uid()))
  );
create policy "Owners unpublish their rides"
  on public.shared_rides for delete to authenticated
  using ((select auth.uid()) = owner_id);

-- shared_media
drop policy "Owners manage their shared photos" on public.shared_media;
drop policy "Friends read shared photos" on public.shared_media;
create policy "Owners and their friends read shared photos"
  on public.shared_media for select to authenticated
  using (
    (select auth.uid()) = owner_id
    or exists (
      select 1 from public.friend_shares s
      where s.owner_id = shared_media.owner_id and s.friend_id = (select auth.uid())
    )
  );
create policy "Owners share their own photos"
  on public.shared_media for insert to authenticated
  with check (
    (select auth.uid()) = owner_id
    and exists (select 1 from public.shared_rides r where r.ride_id = shared_media.ride_id and r.owner_id = (select auth.uid()))
  );
create policy "Owners update their shared photos"
  on public.shared_media for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check (
    (select auth.uid()) = owner_id
    and exists (select 1 from public.shared_rides r where r.ride_id = shared_media.ride_id and r.owner_id = (select auth.uid()))
  );
create policy "Owners unshare their photos"
  on public.shared_media for delete to authenticated
  using ((select auth.uid()) = owner_id);

-- live_rides
drop policy "Riders manage their live ride" on public.live_rides;
drop policy "Friends follow a live ride" on public.live_rides;
create policy "Riders and their friends read live rides"
  on public.live_rides for select to authenticated
  using (
    (select auth.uid()) = owner_id
    or (
      started_at > now() - interval '12 hours'
      and exists (
        select 1 from public.friend_shares s
        where s.owner_id = live_rides.owner_id and s.friend_id = (select auth.uid())
      )
    )
  );
create policy "Riders start their live ride"
  on public.live_rides for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy "Riders update their live ride"
  on public.live_rides for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create policy "Riders end their live ride"
  on public.live_rides for delete to authenticated
  using ((select auth.uid()) = owner_id);
