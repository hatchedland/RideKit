# Ride Tracker — Android Plan

Started 2026-11-18. The iOS plan and every product rule in [CLAUDE.md](CLAUDE.md) / [PLAN.md](PLAN.md)
apply to Android unless this file says otherwise. Same product, same brand, same Supabase project:
a rider can switch phones and keep everything.

## 1. Decisions

| # | Decision | Why |
|---|---|---|
| A1 | **The backend stays Supabase, no own API server.** Both apps talk to Postgres (RLS + RPCs), Storage and Realtime directly. | A server would add cost, latency and ops for zero new capability. |
| A2 | **One repo, three folders** (`apps/ios`, `apps/android`, `backend/supabase`) plus `spec/`. | One person, one PR per change: schema + both apps land together. |
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
- **Sign-in**: Supabase magic link via verified App Links (`https://…/auth-callback`).
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
| Apple Music now-playing | **Open question Q1** |

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
- [ ] Shared tracks friends already published are still v1: republish them as v2 (part of the
      server-side publishing below, or a one-off republish on iOS).
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
- [ ] Server-side shared-ride publishing (`publish_shared_ride`): trimming happens in the backend.
- [ ] Android Google API key (package + SHA-1 restricted; Maps SDK, Places, Routes, Weather).
- [ ] Repo move to `apps/ios`, `apps/android`, `backend/supabase` (one PR, scripts + CLAUDE.md updated).

### Phase 1 — Android MVP
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
- **New personal developer accounts need 12 testers for 14 days of closed testing** before production:
  start this as soon as Phase 1 is usable.

## 5. Open questions (owner)

1. **Music**: Android *can* read Spotify / YouTube Music now-playing via notification-listener access
   (Play reviews that permission strictly). Log all apps on Android, or keep Apple-Music-only parity?
2. **Sign in with Google** (Credential Manager) on Android alongside the email link?
3. Apple Sign In / Google Sign In parity on iOS if (2) is yes?
