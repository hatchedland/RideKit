-- Ride Tracker: chat rules and tidy groups.
--
-- 1. Riders agree to the chat rules (no abuse, reports reviewed, offenders removed) before they can
--    post or make a group — App Store guideline 1.2 wants agreement to terms, not only report/block.
-- 2. A group always keeps an admin, and an empty group goes away, however its members leave —
--    including when a rider deletes their account (the cascade bypasses remove_chat_member).

alter table public.profiles add column chat_rules_accepted_at timestamptz;

create or replace function private.accept_chat_rules()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles set chat_rules_accepted_at = coalesce(chat_rules_accepted_at, now())
  where id = (select auth.uid());
$$;
revoke execute on function private.accept_chat_rules() from public, anon;
grant execute on function private.accept_chat_rules() to authenticated;

create or replace function public.accept_chat_rules()
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.accept_chat_rules();
$$;
revoke execute on function public.accept_chat_rules() from public, anon;
grant execute on function public.accept_chat_rules() to authenticated;

create or replace function private.has_accepted_chat_rules()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and chat_rules_accepted_at is not null
  );
$$;
revoke execute on function private.has_accepted_chat_rules() from public, anon;
grant execute on function private.has_accepted_chat_rules() to authenticated;

alter policy "Members post as themselves" on public.chat_messages
  with check (
    (select auth.uid()) = sender_id
    and (select private.is_chat_member(group_id))
    and (select private.has_accepted_chat_rules())
  );

create or replace function private.create_chat_group(group_name text, rider_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  new_group uuid;
begin
  if me is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if not private.has_accepted_chat_rules() then
    raise exception 'Agree to the chat rules first' using errcode = '42501';
  end if;
  insert into public.chat_groups (name, created_by) values (trim(group_name), me) returning id into new_group;
  insert into public.chat_members (group_id, rider_id, is_admin) values (new_group, me, true);
  perform private.add_chat_members(new_group, rider_ids);
  return new_group;
end;
$$;

-- After any member leaves: delete the group if it's empty, else make sure someone is admin.
create or replace function private.tidy_chat_group()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The whole group is being deleted: nothing to tidy.
  if not exists (select 1 from public.chat_groups where id = old.group_id) then
    return null;
  end if;
  if not exists (select 1 from public.chat_members where group_id = old.group_id) then
    delete from public.chat_groups where id = old.group_id;
  elsif not exists (select 1 from public.chat_members where group_id = old.group_id and is_admin) then
    update public.chat_members set is_admin = true
      where group_id = old.group_id
        and rider_id = (select m.rider_id from public.chat_members m where m.group_id = old.group_id
                        order by m.joined_at, m.rider_id limit 1);
  end if;
  return null;
end;
$$;
revoke execute on function private.tidy_chat_group() from public, anon, authenticated;

create trigger chat_members_tidy_group
  after delete on public.chat_members
  for each row execute function private.tidy_chat_group();
