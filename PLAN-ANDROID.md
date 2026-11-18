# Ride Tracker — Android Plan

Started 2026-11-18. The iOS plan and every product rule in [CLAUDE.md](CLAUDE.md) / [PLAN.md](PLAN.md)
apply to Android unless this file says otherwise. Same product, same brand, same Supabase project:
a rider can switch phones and keep everything.

## 1. Decisions

| # | Decision | Why |
|---|---|---|
| A1 | **The backend stays Supabase, no own API server.** Both apps talk to Postgres (RLS + RPCs), Storage and Realtime directly. | A server would add cost, latency and ops for zero new capability. |
| A2 | **One repo**: `ios/`, `android/`, and at the root `supabase/` (where its CLI expects it), `spec/`, `design/`, `scripts/`. | One person, one PR per change: schema + both apps land together. |
| A3 | **RideKit is ported to a pure Kotlin module (`ridekit`)**, file for file, not shared via KMP or Swift-on-Android. | ~3.1k lines; a port is cheaper than changing the iOS architecture and keeps "Apple frameworks only" on iOS. |
| A4 | **Both RideKits run the same golden fixtures** from `spec/fixtures` (JSON in → expected out). | Keeps thresholds (150 m, 2 min, 500 reviews…) and algorithms identical on both platforms. |
| A5 | **Anything privacy-critical runs on the server.** Shared-ride trimming (first/last 500 m, privacy zones) moves into the backend. | Two client implementations = two chances to leak a home address. |
| A6 | **Google APIs stay direct from the phone, one key per platform.** The Android key is restricted to package + SHA-1 (`X-Android-Package`, `X-Android-Cert`). | A key holds one kind of app restriction; a proxy would add latency while riding. Revisit only if quota is abused. |
| A7 | **Same brand, Android-native chrome.** Milestone tokens, riding screen and weather art are identical; navigation, back, sheets and permissions follow Material 3 / Android. | Riders expect their platform's back and sheet behaviour (Jakob's law). |

## 2. Android stack

Kotlin, Jetpack Compose + Material 3 (themed with Milestone, dynamic colour off), Room (offline-first),
WorkManager (sync), DataStore, Maps SDK for Android (`maps-compose`), Fused Location, supabase-kt.
**No other third-party dependencies** (the Android twin of "Apple frameworks only").
`minSdk 29`, `targetSdk` latest. Edge-to-edge, predictive back.

- **Recording**: foreground service, `foregroundServiceType="location"`, **while-in-use permission only**
  (never `ACCESS_BACKGROUND_LOCATION`). Port `TrackBuffer` crash recovery.
- **Sign-in (decided 2026-11-18)**: Apple and Google only, like iOS. Google: Credential Manager
  (`androidx.credentials` + Google ID) → `signInWithIdToken`. Apple: Supabase OAuth in a Custom Tab
  (needs Apple's Services ID + secret key in Supabase; the key expires every 6 months).
- **Music (decided 2026-11-18)**: log **every music app** (Spotify, YouTube Music, Apple Music…) via a
  `NotificationListenerService` + `MediaSessionManager`, asked for in context (Settings › Ride
  soundtrack), with a clear "only song titles while you ride" explanation. Play reviews this
  permission: the store listing and Data safety form must say why.
- **Push** (chat, later): an Edge Function that sends to FCM and APNs.

## 3. Platform mapping (UX)

| iOS | Android |
|---|---|
| Map drawer (peek ↔ full) | `BottomSheetScaffold`; system back: full → peek → closed |
| Start sheet | `ModalBottomSheet`, no auto-focused keyboard, big Start |
| Live Activity / Dynamic Island | Ongoing ride notification with **Mark spot** action; Android 16+ **Live Updates** (progress style) |
| Action button / Siri | Quick Settings tile (Start / Mark spot), home-screen widget, notification action |
| Tab bar | Material navigation bar, same 5 tabs, hidden while riding |
| Ride album in Photos | **In-app ride gallery only.** Android can't add a photo to an album without copying it, which breaks "photos are referenced, never copied" |
| "Open Photos" opens the app only | Opens the exact item (`ACTION_VIEW` on the content URI) |
| SF expanded width numbers | Roboto Flex (width axis) bundled for `readout` / `stat` / `label` |
| Template PDF icons | `make-icons.swift` also emits SVG → VectorDrawable; weather 3D art as WebP |
| Apple Music now-playing (Music app only) | Any music app via notification access |

**Android-only flows**
1. **Permissions in context**: location + notifications when the rider taps Start ("so the ride keeps
   recording"); photos (full access, because "Choose photos" breaks the capture-time album) on first need.
2. **Battery-killer recovery, not an up-front warning**: after a ride, if the track has a gap ≥ 60 s
   while the service ran, show "Your phone paused recording for 4 min. Let Ride Tracker run in the
   background →" with maker-specific steps (Xiaomi, Oppo, Vivo, Samsung…).
3. Riding screen: always dark, Mark spot 84 dp, identical layout to iOS.

## 4. Phases

### Phase 0 — groundwork on iOS + backend (before any Android code)
- [x] **TrackCodec v2**: plain header + raw DEFLATE, Unix time ([spec/track-codec.md](spec/track-codec.md),
      golden file `spec/fixtures/track-v2.bin`). iOS reads v1, writes v2, upgrades v1 before upload.
- [ ] Shared tracks friends already published are still v1: republish each shared ride once through
      the function (it writes v2) after it's deployed.
- [x] `spec/fixtures` for Trail, WishlistMatcher (+ StopDetector, RevisitDetector), RideTimePlan (+ RidePace,
      Sun), WeatherAlerts, FamousPlaces, SharePrivacy, RideNaming; Swift tests check them on every run
      ([how they work](spec/fixtures/README.md)).
- [x] ~~`media_links.platform` + `device_id`~~ — dropped: upserts send every column, so a phone editing
      another platform's link would overwrite its photo id. Instead each platform gets **its own id
      columns** (iOS: `local_identifier` / `cloud_identifier`; Android: `android_media_id`, added in the
      Android sync PR) and only ever sends its own. iOS needs no change (unknown columns are ignored).
- [x] `app_config` (`min_version`, `store_url` per platform; migration 20261118100000, applied
      2026-11-18; readable signed out, owner-edited in SQL). iOS: RideKit `AppVersion`, update screen
      (never during a ride), and **sync stops** while the build is too old.
- [x] Server-side shared-ride publishing: Edge Function `publish-shared-ride` (trims with the account's
      zones; photos via a private outbox), `privacy_zones` + `profiles.hide_ride_ends` (migration
      20261118120000, zones now follow the rider to any phone), live-ride zone trigger. Logic in
      `supabase/functions/_shared`, tested against `spec/fixtures` (`./scripts/test-functions.sh`); deployed 2026-11-18
      (`supabase functions deploy publish-shared-ride --use-api`).
- [ ] **Lock-down, once every phone runs the build that publishes through the function** (raise
      `app_config.min_version` first): revoke `insert, update` on `shared_rides` / `shared_media` from
      `authenticated`, and let riders only *delete* in the `shared` bucket. Then the app can't skip the
      server's trimming.
- [ ] Android Google API key (package + SHA-1 restricted; Maps SDK, Places, Routes, Weather).
- [x] Repo move: iOS into `ios/` (2026-11-18); `supabase/`, `spec/`, `design/`, `scripts/` stay at the root, so
      every command is unchanged. `android/` arrives with Phase 1.

### Phase 1 — Android MVP
- [x] `android/` Gradle project (Gradle 9.9.1 wrapper with checksum, Kotlin 2.4.21, JUnit 6) and
      **`ridekit`**: the Kotlin port of everything `spec/fixtures` covers (geometry, track codec, privacy,
      stops/wishlist, pace/arrival/sunset, weather alerts, famous places, trail, naming, app version),
      times as Unix seconds. `./scripts/test-android.sh` runs it against every golden file.
- [ ] App module (Compose, Material 3 + Milestone tokens, Room, WorkManager, supabase-kt, Maps).
Sign-in + @handle, Start ride → record (FGS) → Mark spot (button, notification, QS tile) → End,
spots + map + drawer, rides list/detail, offline-first sync.

### Phase 2 — Places and photos
Photo trail + in-app ride gallery, weather (dashboard, riding band, alerts), route preview + honest
arrival time, famous places ahead, wishlist auto-visit.

### Phase 3 — Social
Friends, shared rides, live rides, group chat; push for both platforms.

### Phase 4 — Play Store
- Data safety form; foreground-service location declaration + video.
- **Web page for account-deletion requests** (Play requires one besides the in-app button).
- **Revoke Sign in with Apple tokens when an account is deleted** (App Store guideline 5.1.1(v), also
  before the iOS release): an Edge Function calls Apple's `/auth/revoke` with the app's client secret.
- **New personal developer accounts need 12 testers for 14 days of closed testing** before production:
  start this as soon as Phase 1 is usable.

## 5. Decided (2026-11-18)

1. **Music**: Android logs every music app (notification access); iOS stays Music-app only.
2. **Sign-in**: Apple and Google on both platforms; email sign-in removed.
3. **Trail**: a song that starts during a stop belongs to that stop.
