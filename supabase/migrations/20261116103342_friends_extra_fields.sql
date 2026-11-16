-- Fields the app's SharedRide carries that the first friends migration left out. Additive only.
alter table public.shared_rides
  add column avg_moving_speed_mps double precision not null default 0;

-- A shared video is a still frame; friends see it marked as a video.
alter table public.shared_media
  add column is_video boolean not null default false;
