-- Ride Tracker: delete your account from inside the app (App Store guideline 5.1.1(v)).
--
-- The app first removes the rider's files from Storage through the Storage API (tracks/<id>/…,
-- shared/<id>/…; files can't be deleted from SQL), then calls delete_my_account(). Deleting the
-- auth user removes every row that belongs to them: each table references auth.users with
-- "on delete cascade" (rides, spots, media links, songs, profile, friends, shared and live rides,
-- requests, and group chat memberships, messages, blocks and reports).
-- Photos and videos in the rider's Photos library are never touched; they were never uploaded.

create or replace function private.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  delete from auth.users where id = me;
end;
$$;
revoke execute on function private.delete_my_account() from public, anon;
grant execute on function private.delete_my_account() to authenticated;

create or replace function public.delete_my_account()
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.delete_my_account();
$$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
