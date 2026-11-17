-- Ride Tracker: group chat between friends (decided 2026-11-17).
--
-- A rider makes a group from their own friends (max 20 riders) to plan rides and talk afterwards.
-- Members who aren't friends with each other see only each other's name and @handle, never rides.
-- Ending a friendship doesn't remove anyone from a group; admins remove members by hand.
-- Moderation (App Store guideline 1.2): any message can be reported, any rider blocked; blocked
-- riders' messages are hidden from the blocker and they can't add the blocker to a group.
--
-- New messages are broadcast on the private Realtime channel "group:<id>" (members only); the app
-- treats a broadcast as a nudge and reads new rows through the policies below.

-- ---------------------------------------------------------------------------------------------
-- Tables

create table public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 40),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.chat_members (
  group_id uuid not null references public.chat_groups (id) on delete cascade,
  rider_id uuid not null references auth.users (id) on delete cascade,
  is_admin boolean not null default false,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  primary key (group_id, rider_id)
);
-- "Which groups am I in?" is the hot path of every policy below.
create index chat_members_rider_group_idx on public.chat_members (rider_id, group_id);

create table public.chat_messages (
  -- Made on the phone, so a retried send can't post twice.
  id uuid primary key,
  group_id uuid not null references public.chat_groups (id) on delete cascade,
  sender_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null default 'text' check (kind in ('text')),
  body text not null check (char_length(body) <= 2000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (deleted_at is not null or char_length(trim(body)) >= 1)
);
create index chat_messages_group_created_idx on public.chat_messages (group_id, created_at desc, id desc);
create index chat_messages_sender_idx on public.chat_messages (sender_id);

create table public.rider_blocks (
  blocker_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index rider_blocks_blocked_idx on public.rider_blocks (blocked_id);

-- Read by the project owner in the dashboard; riders can only file them.
create table public.chat_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.chat_messages (id) on delete cascade,
  reporter_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  reason text not null default '' check (char_length(reason) <= 500),
  created_at timestamptz not null default now(),
  unique (message_id, reporter_id)
);
create index chat_reports_reporter_idx on public.chat_reports (reporter_id);

-- ---------------------------------------------------------------------------------------------
-- Helpers (security definer, so policies on chat_members can ask about chat_members)

create or replace function private.is_chat_member(target_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.chat_members m
    where m.group_id = target_group and m.rider_id = (select auth.uid())
  );
$$;
revoke execute on function private.is_chat_member(uuid) from public, anon;
grant execute on function private.is_chat_member(uuid) to authenticated;

create or replace function private.is_chat_admin(target_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.chat_members m
    where m.group_id = target_group and m.rider_id = (select auth.uid()) and m.is_admin
  );
$$;
revoke execute on function private.is_chat_admin(uuid) from public, anon;
grant execute on function private.is_chat_admin(uuid) to authenticated;

-- Friends both ways, as accept_friend_request makes them.
create or replace function private.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.friend_shares where owner_id = a and friend_id = b)
     and exists (select 1 from public.friend_shares where owner_id = b and friend_id = a);
$$;
revoke execute on function private.are_friends(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Row-level security

alter table public.chat_groups enable row level security;
alter table public.chat_members enable row level security;
alter table public.chat_messages enable row level security;
alter table public.rider_blocks enable row level security;
alter table public.chat_reports enable row level security;

revoke all on public.chat_groups, public.chat_members, public.chat_messages,
              public.rider_blocks, public.chat_reports from anon, authenticated;

-- Groups: members read; admins rename. Creating goes through create_chat_group.
grant select on public.chat_groups to authenticated;
grant update (name) on public.chat_groups to authenticated;
create policy "Members see their groups"
  on public.chat_groups for select to authenticated
  using ((select private.is_chat_member(id)));
create policy "Admins rename their groups"
  on public.chat_groups for update to authenticated
  using ((select private.is_chat_admin(id)))
  with check ((select private.is_chat_admin(id)));

-- Members: members see each other; each rider moves only their own read marker. Adding and
-- removing go through the functions below.
grant select on public.chat_members to authenticated;
grant update (last_read_at) on public.chat_members to authenticated;
create policy "Members see who's in their groups"
  on public.chat_members for select to authenticated
  using ((select private.is_chat_member(group_id)));
create policy "Riders move their own read marker"
  on public.chat_members for update to authenticated
  using ((select auth.uid()) = rider_id)
  with check ((select auth.uid()) = rider_id);

-- Messages: members read everything except what riders they blocked wrote; members post as
-- themselves; senders delete (tombstone) their own.
grant select on public.chat_messages to authenticated;
grant insert (id, group_id, kind, body) on public.chat_messages to authenticated;
grant update (deleted_at) on public.chat_messages to authenticated;
create policy "Members read their groups' messages"
  on public.chat_messages for select to authenticated
  using (
    (select private.is_chat_member(group_id))
    and not exists (
      select 1 from public.rider_blocks b
      where b.blocker_id = (select auth.uid()) and b.blocked_id = chat_messages.sender_id
    )
  );
create policy "Members post as themselves"
  on public.chat_messages for insert to authenticated
  with check ((select auth.uid()) = sender_id and (select private.is_chat_member(group_id)));
create policy "Senders delete their own messages"
  on public.chat_messages for update to authenticated
  using ((select auth.uid()) = sender_id)
  with check ((select auth.uid()) = sender_id);

-- A deleted message keeps its row (so phones drop it) but loses its text.
create or replace function private.clear_deleted_chat_message()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deleted_at is not null then
    new.body := '';
  end if;
  return new;
end;
$$;
create trigger chat_messages_clear_deleted
  before update on public.chat_messages
  for each row execute function private.clear_deleted_chat_message();

-- Blocks: riders manage their own list.
grant select, insert, delete on public.rider_blocks to authenticated;
create policy "Riders see their own blocks"
  on public.rider_blocks for select to authenticated
  using ((select auth.uid()) = blocker_id);
create policy "Riders block for themselves"
  on public.rider_blocks for insert to authenticated
  with check ((select auth.uid()) = blocker_id);
create policy "Riders unblock for themselves"
  on public.rider_blocks for delete to authenticated
  using ((select auth.uid()) = blocker_id);

-- Reports: file one about a message you can see; nobody reads them through the API.
grant insert (message_id, reason) on public.chat_reports to authenticated;
create policy "Members report messages they can see"
  on public.chat_reports for insert to authenticated
  with check (
    (select auth.uid()) = reporter_id
    and exists (select 1 from public.chat_messages m where m.id = chat_reports.message_id)
  );

-- ---------------------------------------------------------------------------------------------
-- Functions the app calls

-- Adds riders to a group: only the caller's friends (both ways), never someone who blocked the
-- caller, max 20 members. Skips riders already in it. Caller must be an admin.
create or replace function private.add_chat_members(target_group uuid, rider_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  rider uuid;
begin
  if not exists (select 1 from public.chat_members where group_id = target_group and rider_id = me and is_admin) then
    raise exception 'Only a group admin can add riders' using errcode = '42501';
  end if;
  foreach rider in array coalesce(rider_ids, '{}') loop
    if rider = me then continue; end if;
    if not private.are_friends(me, rider) then
      raise exception 'You can only add your friends' using errcode = '42501';
    end if;
    if exists (select 1 from public.rider_blocks where blocker_id = rider and blocked_id = me) then
      continue; -- Quietly: the caller isn't told who blocked them.
    end if;
    insert into public.chat_members (group_id, rider_id) values (target_group, rider)
      on conflict do nothing;
  end loop;
  if (select count(*) from public.chat_members where group_id = target_group) > 20 then
    raise exception 'A group can have at most 20 riders' using errcode = '23514';
  end if;
end;
$$;
revoke execute on function private.add_chat_members(uuid, uuid[]) from public, anon;
grant execute on function private.add_chat_members(uuid, uuid[]) to authenticated;

create or replace function public.add_chat_members(target_group uuid, rider_ids uuid[])
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.add_chat_members(target_group, rider_ids);
$$;
revoke execute on function public.add_chat_members(uuid, uuid[]) from public, anon;
grant execute on function public.add_chat_members(uuid, uuid[]) to authenticated;

-- Makes a group with the caller as admin, then adds the chosen friends.
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
  insert into public.chat_groups (name, created_by) values (trim(group_name), me) returning id into new_group;
  insert into public.chat_members (group_id, rider_id, is_admin) values (new_group, me, true);
  perform private.add_chat_members(new_group, rider_ids);
  return new_group;
end;
$$;
revoke execute on function private.create_chat_group(text, uuid[]) from public, anon;
grant execute on function private.create_chat_group(text, uuid[]) to authenticated;

create or replace function public.create_chat_group(group_name text, rider_ids uuid[])
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.create_chat_group(group_name, rider_ids);
$$;
revoke execute on function public.create_chat_group(text, uuid[]) from public, anon;
grant execute on function public.create_chat_group(text, uuid[]) to authenticated;

-- Removes a rider: yourself (leaving) or, as an admin, anyone. When the last admin goes, the
-- longest-standing member becomes admin; when the last member goes, the group is deleted.
create or replace function private.remove_chat_member(target_group uuid, rider uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if rider is distinct from me
     and not exists (select 1 from public.chat_members where group_id = target_group and rider_id = me and is_admin) then
    raise exception 'Only a group admin can remove riders' using errcode = '42501';
  end if;
  delete from public.chat_members where group_id = target_group and rider_id = rider;
  if not exists (select 1 from public.chat_members where group_id = target_group) then
    delete from public.chat_groups where id = target_group;
  elsif not exists (select 1 from public.chat_members where group_id = target_group and is_admin) then
    update public.chat_members set is_admin = true
      where group_id = target_group
        and rider_id = (select rider_id from public.chat_members where group_id = target_group
                        order by joined_at, rider_id limit 1);
  end if;
end;
$$;
revoke execute on function private.remove_chat_member(uuid, uuid) from public, anon;
grant execute on function private.remove_chat_member(uuid, uuid) to authenticated;

create or replace function public.remove_chat_member(target_group uuid, rider uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.remove_chat_member(target_group, rider);
$$;
revoke execute on function public.remove_chat_member(uuid, uuid) from public, anon;
grant execute on function public.remove_chat_member(uuid, uuid) to authenticated;

-- The Chats list in one call: each of my groups with its members (name and @handle only), the
-- newest message I can see, and how many I haven't read.
create or replace function private.chat_overview()
returns table (
  group_id uuid,
  name text,
  is_admin boolean,
  members jsonb,
  last_message_body text,
  last_message_sender uuid,
  last_message_at timestamptz,
  unread integer
)
language sql
stable
security definer
set search_path = ''
as $$
  with me as (select auth.uid() as id),
  mine as (
    select m.group_id, m.is_admin, m.last_read_at
    from public.chat_members m, me
    where m.rider_id = me.id
  ),
  visible as (
    select msg.*
    from public.chat_messages msg
    join mine on mine.group_id = msg.group_id
    where msg.deleted_at is null
      and not exists (
        select 1 from public.rider_blocks b, me
        where b.blocker_id = me.id and b.blocked_id = msg.sender_id
      )
  )
  select
    g.id,
    g.name,
    mine.is_admin,
    (select coalesce(jsonb_agg(jsonb_build_object(
              'id', cm.rider_id,
              'name', coalesce(nullif(p.display_name, ''), 'Rider'),
              'username', coalesce(p.username, ''),
              'is_admin', cm.is_admin
            ) order by cm.joined_at), '[]'::jsonb)
       from public.chat_members cm
       left join public.profiles p on p.id = cm.rider_id
      where cm.group_id = g.id),
    last.body,
    last.sender_id,
    last.created_at,
    (select count(*)::integer from visible v, me
      where v.group_id = g.id and v.created_at > mine.last_read_at and v.sender_id <> me.id)
  from mine
  join public.chat_groups g on g.id = mine.group_id
  left join lateral (
    select v.body, v.sender_id, v.created_at from visible v
    where v.group_id = g.id order by v.created_at desc, v.id desc limit 1
  ) last on true
  order by coalesce(last.created_at, g.created_at) desc;
$$;
revoke execute on function private.chat_overview() from public, anon;
grant execute on function private.chat_overview() to authenticated;

create or replace function public.chat_overview()
returns table (
  group_id uuid,
  name text,
  is_admin boolean,
  members jsonb,
  last_message_body text,
  last_message_sender uuid,
  last_message_at timestamptz,
  unread integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.chat_overview();
$$;
revoke execute on function public.chat_overview() from public, anon;
grant execute on function public.chat_overview() to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Realtime: each new, changed or deleted message is broadcast on "group:<id>" to members only.

create or replace function private.broadcast_chat_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.broadcast_changes(
    'group:' || coalesce(new.group_id, old.group_id)::text,
    tg_op, tg_op, tg_table_name, tg_table_schema, new, old
  );
  return null;
end;
$$;
revoke execute on function private.broadcast_chat_message() from public, anon, authenticated;

create trigger chat_messages_broadcast
  after insert or update on public.chat_messages
  for each row execute function private.broadcast_chat_message();

-- Listening needs membership of the group the topic names; anything else is refused.
create or replace function private.can_listen_to_chat(topic text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if topic !~ '^group:[0-9a-fA-F-]{36}$' then
    return false;
  end if;
  return private.is_chat_member(substring(topic from 7)::uuid);
end;
$$;
revoke execute on function private.can_listen_to_chat(text) from public, anon;
grant execute on function private.can_listen_to_chat(text) to authenticated;

create policy "Members listen to their group chats"
  on realtime.messages for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select private.can_listen_to_chat(realtime.topic()))
  );
