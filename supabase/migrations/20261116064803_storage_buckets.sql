-- Ride Tracker: files.
--
--   tracks/<user_id>/<ride_id>.track             the full TrackCodec blob, owner only
--   shared/<owner_id>/<ride_id>/track            trimmed track of a shared ride
--   shared/<owner_id>/<ride_id>/photos/<id>.jpg  2048 px copy of a photo the rider picked
--
-- Both buckets are private: files are fetched with the rider's session, never by public URL.
-- The first folder of every path is the owner's id, which is what the policies check.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('tracks', 'tracks', false, 20 * 1024 * 1024, array['application/octet-stream']),
  ('shared', 'shared', false, 10 * 1024 * 1024, array['application/octet-stream', 'image/jpeg'])
on conflict (id) do nothing;

-- Owners read, upload, replace (upsert needs select + insert + update) and remove their own files.
create policy "Riders read their own files"
  on storage.objects for select to authenticated
  using (bucket_id in ('tracks', 'shared') and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Riders upload their own files"
  on storage.objects for insert to authenticated
  with check (bucket_id in ('tracks', 'shared') and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Riders replace their own files"
  on storage.objects for update to authenticated
  using (bucket_id in ('tracks', 'shared') and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id in ('tracks', 'shared') and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Riders remove their own files"
  on storage.objects for delete to authenticated
  using (bucket_id in ('tracks', 'shared') and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Friends read shared files of riders who share with them. Never the "tracks" bucket.
create policy "Friends read shared files"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'shared'
    and exists (
      select 1 from public.friend_shares s
      where s.owner_id::text = (storage.foldername(name))[1] and s.friend_id = (select auth.uid())
    )
  );
