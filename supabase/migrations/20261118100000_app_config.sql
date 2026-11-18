-- Ride Tracker: the oldest app version allowed to sync, per platform.
--
-- iOS and Android both talk to these tables directly, so a schema change can break an old build
-- still in riders' hands. Raising min_version makes that build ask the rider to update (never during
-- a ride) instead of syncing wrong data. Readable before sign-in, so even a broken sign-in can say
-- "update". Changed only by the owner, in SQL:
--   update public.app_config set min_version = '1.3.0', store_url = '…' where platform = 'ios';

create table public.app_config (
  platform text primary key check (platform in ('ios', 'android')),
  -- Marketing version, e.g. '1.2.0'. Compared part by part (RideKit AppVersion); unreadable never blocks.
  min_version text not null default '0',
  -- Where "Update" goes (App Store / Play Store page); null hides the button.
  store_url text check (store_url is null or store_url like 'https://%'),
  updated_at timestamptz not null default now()
);

comment on table public.app_config is 'Oldest app version allowed to sync, per platform. Owner-edited only.';

create trigger touch_app_config before update on public.app_config
  for each row execute function private.touch_updated_at();

insert into public.app_config (platform, min_version) values ('ios', '0'), ('android', '0');

alter table public.app_config enable row level security;
revoke all on public.app_config from anon, authenticated;
grant select on public.app_config to anon, authenticated;

create policy "Anyone reads the app config"
  on public.app_config for select to anon, authenticated
  using (true);
