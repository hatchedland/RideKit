# Ride Tracker — project rules

Native iOS app for **motorcycle / scooter** rides, built around **places**. Full product plan: [PLAN.md](PLAN.md).
Android port (planned 2026-11-18): [PLAN-ANDROID.md](PLAN-ANDROID.md).
Setup and release checklist: [README.md](README.md).

**Repo layout (2026-11-18):** `ios/` (the iOS app, its tests, widget, `Shared`, `Packages/RideKit`,
`project.yml`, `Config`), `android/` (coming in Phase 1), and at the root `supabase/` (the CLI expects it
there), `spec/` (formats + golden files both apps test against), `design/` and `scripts/`. **iOS paths
below (`RideTracker/…`, `Shared/…`, `Packages/RideKit`, `Config/…`) are relative to `ios/`.**

## Product rules (decided with the owner — don't change without asking)

- **Spots are the core.** Every spot stores a Google Maps URL built with the official Maps URLs format
  (`https://www.google.com/maps/search/?api=1&query=lat,lon`); the link itself needs no API.
- **Maps inside the app are Google Maps (decided 2026-11-12)**: Maps SDK for iOS through the shared
  `GoogleMapView` (`RideTracker/Features/Maps`), never MapKit's `Map`. **Directions stay in the app
  (decided 2026-11-17)**: a spot's Directions button opens `RoutePreviewSheet` — the Google Routes
  two-wheeler route on the map, distance and time, and one **Start ride** that rides there (the riding
  screen shows the road ahead and what's left). No turn-by-turn voice. **The app never hands
  off to the Google Maps app (2026-11-17)** — the Start sheet's "Directions in Google Maps" toggle is
  gone.
- **Honest arrival time (decided 2026-11-17)**: wherever a route to a destination is shown before a
  ride (route preview, Start sheet), say how long it really takes and whether it ends in daylight
  (`RideTimePlan`, `ArrivalEstimateView`). Google's road time is the floor; the rider's own pace from
  their last 20 rides of ≥ 20 km (`RidePace`: distance-weighted moving speed, median share of time
  stopped) is averaged in, capped at 1.6× Google. Without 2 such rides: 15% stopped (about 10 min an
  hour). Sunset at the destination, 20 min margin: "After dark. Leave by 1:20 pm to arrive in
  daylight." No verdict for rides over 14 h. Before the ride only — nothing new on the riding screen. **Place search and suggested spot / stop names use Google Places (API
  New, decided 2026-11-16)** through RideKit `GooglePlaces` + `GooglePlacesClient` (plain URLSession,
  same key, `X-Ios-Bundle-Identifier`), nearby names limited to `GooglePlaces.riderTypes`; results
  shown off a Google map carry "Results from Google Maps". Addresses and towns stay on Apple's
  free `MKReverseGeocodingRequest`. **Weather is Google Weather (decided 2026-11-17)** through RideKit
  `GoogleWeather` (hourly forecast, same key and bundle-id header; the key's API restrictions must
  include Weather API), credited "Weather from Google". The API key lives in git-ignored
  `Config/Secrets.xcconfig` (public repo); without it maps show a placeholder instead of crashing.
- **Tapping a map pin, or a spot in the Spots list, opens a drawer, never a new page (decided 2026-11-16)**: `.mapDrawer` in
  `RideTracker/Features/Maps/MapDrawer.swift`. Opens at a short peek with the map still usable;
  dragging or scrolling it goes full screen; tapping its header toggles peek ↔ full; tapping empty map
  or swiping down closes it. From a list there's no map to keep in view, so it opens full screen
  (`startsExpanded`). Drawer content never pushes another page.
- **Mark spot while riding = one tap, zero looking**: riding screen, Lock Screen Live Activity, Action
  button, Siri. Save first, name later. Never add UI that needs attention while moving.
- **Riding screen layout (decided 2026-11-17)**: the map edge to edge; on top a compact band on
  near-solid asphalt — speed with **km/h right on the number** (so it never reads as a temperature),
  the weather on its own labelled line under it (3D illustration + "21° · Rain"), Distance / Time /
  Max-or-To-go stacked right; at the bottom one row: round Pause · big **Mark spot** (84 pt) · round
  End (confirms). No tab bar while riding. Map alerts (famous places, wishlist, arrival) stack like
  notifications under the band, newest on top, max 2, 6 s each; weather alerts are a line in the
  band. Weather backdrop behind the numbers is faint and **never flashes** (no lightning: startles at
  speed, photosensitivity). **No music controls** — a read-only now-playing line (Music app only);
  riders use headset buttons, Siri or the Lock Screen.
- **Famous places ahead (decided 2026-11-17)**: while riding, Google Places sights with **≥ 500
  reviews and ≥ 4.0 rating** (`FamousPlaces`, `GooglePlaces.famousTypes`) within **2 km and not
  behind the rider** (heading from GPS, else the last 50 m ridden) are announced passively, the
  **3 nearest** at a time, each once per ride, never a saved spot. One search about every 3 km.
  Setting on by default.
- **Weather alerts (decided 2026-11-17)**: passive, while riding — storm > rain > wind (gusts ≥ 40
  km/h) > heat (feels ≥ 38°) > rain easing, plus sunset in the last 30 min with ≥ 5 km to go.
  Rain is news when it starts, not every hour; same kind at most hourly, any weather alert at most
  every 15 min (`WeatherAlerts`). Forecast every 10 min / 10 km, ~30 min ahead along the route.
  Times come from hourly data, so alerts say "Rain from 4:30 pm", never "in 20 min".
- **Wishlist**: spots are `wantToGo` or `visited`. A ride auto-visits a wishlist spot only if the rider
  **stopped ≥ 2 min** or **took a photo** within the radius — riding past doesn't count. Always undoable.
- **Spot radius is 150 m** (photo → spot matching and auto-visit). Revisit radius is 100 m. Nearby
  wishlist alert at 2 km.
- **Starting a ride (decided 2026-11-16): Start ride → one sheet → Start.** Many rides have no
  destination, so the main button is **Start ride**. **The Ride tab is a pre-ride dashboard, not a
  map (decided 2026-11-17)**: weather here (3D illustration, outlook for the next 6 h, hourly strip),
  ODO/TRIP, the 3 nearest wishlist spots as one-tap destinations, and **Start ride** pinned at the
  bottom. The map lives in Spots, and fills the screen while riding. The sheet offers an **optional** "Where
  to?" (wishlist, recent destinations, place search; no auto-focused keyboard) and the ride name; its
  big button always starts. With a destination the name defaults to "Ride to <place>", without one
  to "Ride · 12 Oct 2026". Action button / Siri / Lock Screen start instantly. The destination is
  never shared with friends. The name is also the Photos album name; renaming a ride renames its album.
- **Every photo/video taken between Start and End goes into the ride's album** in
  Photos › Albums › Ride Tracker. Built from the **capture-time window** (pauses included), never only
  from live events. Late arrivals are swept for 48 h. Screenshots excluded by default.
- **Photos are referenced, never copied** (`PHAsset` local ID + `PHCloudIdentifier`). Deleting a ride
  or spot never deletes photos; deleting an album only on explicit choice.
- **Sharing** sends the **original** Photos files (edited version if any, Live Photo still) through the
  system share sheet as file URLs. "Open Photos" can only open the Photos app (no public API to open a
  specific item) — don't claim otherwise.
- **Ride soundtrack**: songs played in the **Music app** (Apple Music / own library) for ≥ 30 s during
  a ride are logged with time and place, opened via Apple Music links. YouTube Music, Spotify and
  other apps are not readable by iOS apps — songs can only be logged from the Music app; don't
  promise otherwise (checked with the owner 2026-11-16: tracking stays Apple Music only). Uses MediaPlayer (no MusicKit entitlement, so it works
  on free Personal builds). **Android logs every music app** — Spotify, YouTube Music, Apple Music and
  others — through notification access (decided 2026-11-18), so the platforms differ here on purpose.
- **No GoPro / action-camera support.** Photos without GPS stay in the album, just unpinned.
- **Photo trail** is the default way a ride's media is shown: stops (spots, or photo clusters within
  150 m / 10 min) joined by the road between them. Unnamed stops are **suggested, never auto-saved**
  as spots ("Save as spot"). Photos without GPS go into the trail by capture time but **never get a
  map pin**. A song that starts during a stop (arrival to departure) belongs to **that stop**, others
  to the road it started on (decided 2026-11-18).
- **Bikes and scooters only.** No car mode or vehicle type.
- **App Store release target. Account required, everything in Supabase (decided 2026-11-16).** The app
  opens on sign-in; nothing (riding included, Siri/Action button too) works signed out. Every ride
  (stats, destination, notes, track file), spot, photo/video **metadata** link and played song syncs to
  the rider's Supabase project data (`supabase/migrations`, row-level security per rider). Photo and
  video files stay in Photos (only picked friend photos are copied). Offline-first: SwiftData on the
  phone records with no signal and syncs later. CloudKit is gone; Friends runs on Supabase.
- **Friends (decided 2026-10-15; in-app requests, mutual, on Supabase since 2026-11-16)**: friends-only,
  nothing public, iPhone-only. Every rider picks a unique **@handle** after the first sign-in
  (`profiles.username`). Riders find each other **only inside the app** by @handle (`search_riders`:
  handle + name, never email, ≥ 2 characters, max 10) and send a **friend request**
  (`friend_requests`); accepting (`accept_friend_request`) makes them **friends both ways** — each sees
  the other's shared rides and live rides. No invite links or codes. Remove friend ends it both ways.
  Friends see **published copies** (`shared_rides`, `shared_media`, bucket `shared`) — route, stops,
  songs, **only photos the rider picked** — never the rider's own tables, and can follow a ride
  **live** (`live_rides`, ~1 update/min, chosen on the Start sheet, ends at End or after 12 h). The
  **first and last 500 m** of every shared ride and everything in **privacy zones** are never shared,
  live included; the destination never is. **The server does the trimming (2026-11-18)**: the
  `publish-shared-ride` Edge Function reads the full track from the rider's Storage and the zones from
  `privacy_zones` / `profiles.hide_ride_ends` (kept in the account, so every phone has them), and writes
  the shared track, row and photos. Apps upload picked photos to a private outbox
  (`tracks/<uid>/outbox/<ride>/`) and call it; a trigger keeps live positions out of zones. Its logic
  (`supabase/functions/_shared`) must pass `./scripts/test-functions.sh` against `spec/fixtures`. Shared photos are the one exception to "never copied":
  2048 px JPEG copies of the chosen photos only. Nothing social on the riding screen beyond a passive
  "Live" chip; no comments or likes. Every friend's stop has **Add to my wishlist** — that's the point
  of the feature. Works in every build.
- **Group chat (decided 2026-11-17)**: Friends › Chats, for planning rides and talking afterwards.
  A rider makes a group from **their own friends only** (max 20, `create_chat_group` /
  `add_chat_members`); members who aren't friends with each other see only name and @handle, never
  rides. Unfriending doesn't remove anyone from a group; admins remove, anyone leaves. Text only for
  now (spot and ride cards next, push last — Personal builds can't get push). **Nothing on the riding
  screen**, ever. Every message can be **reported** (`chat_reports`, reviewed by the owner) and any
  rider **blocked** (`rider_blocks`: their messages are hidden and they can't add you) — App Store
  guideline 1.2. Message ids are made on the phone (no double posts); the newest 200 per group and
  unsent messages are cached in Caches/chat as JSON (`ChatTimeline`), not SwiftData. New messages
  arrive on the private Realtime broadcast channel `group:<id>`, used only as a nudge to re-read.
  Riders **agree to the chat rules** once (`ChatRulesSheet`, `profiles.chat_rules_accepted_at`)
  before posting or making a group; the server refuses both without it. The rules promise reports
  are looked at within 24 hours, so someone must actually watch `chat_reports`. Groups keep an admin
  and empty groups are deleted however members leave, account deletion included (`tidy_chat_group`).

## Tech constraints

- iOS 26+, Swift 6 strict concurrency, SwiftUI. **Apple frameworks only — the exceptions are the
  Google Maps SDK for iOS and supabase-swift** (SPM, pinned in `project.yml`). No other third-party
  dependencies. Supabase host + publishable key live in git-ignored `Config/Secrets.xcconfig`.
- **Accounts (decided 2026-11-16; sign-in methods 2026-11-18): Supabase Auth, Sign in with Apple and
  Google only — no email/password, no email links**, on iOS and Android (`AccountService`). Apple: the
  native sheet → `signInWithIdToken` (nonce; entitlement in Debug/Release; **hidden in Personal builds**,
  free teams can't sign it). Google: `signInWithOAuth` in an `ASWebAuthenticationSession` back to
  `ridetracker://auth-callback` (no Google SDK). The same verified email is the same account whichever
  way a rider signs in; Apple "Hide My Email" makes a separate one. Signed out, only the sign-in screen shows.
  **Delete account (2026-11-17, guideline 5.1.1(v))**: Settings › Delete account removes the rider's
  Storage files (tracks, shared), then `delete_my_account()` deletes the auth user, which cascades to
  every row of theirs; then this phone's copy is erased. Photos and Ride Tracker albums stay. Every
  new table must reference `auth.users` with `on delete cascade`, or deletion leaves data behind.
- **Minimum version (2026-11-18)**: `app_config.min_version` per platform. Raise it (in SQL) when a schema
  change would break an older build; that build then shows `UpdateRequiredView` (never during a ride)
  and stops syncing. Two apps share these tables, so sync payloads only ever carry a platform's own
  columns (e.g. photo ids), never the other platform's.
- Always the latest non-deprecated APIs, e.g. `CLLocationUpdate.liveUpdates` + `CLServiceSession` +
  `CLBackgroundActivitySession` (only "When In Use" permission — never ask for "Always"),
  `MKReverseGeocodingRequest` (not `CLGeocoder`), `MKMapItem.location` / `.address` (not `placemark`).
- **SwiftData models must stay CloudKit-compatible**: no `@Attribute(.unique)`, every property has a
  default or is optional, every relationship optional. Schema changes are **additive only** and go
  through a new `VersionedSchema` + `SchemaMigrationPlan` (see `RideTracker/Models/Schema.swift`).
  Released versions are **frozen as nested model copies** (V1 = v1.0.0; V2 adds `PlayedSong`; V3 adds
  `Ride.sharedWithFriends`/`sharedAt` and `MediaLink.sharedWithFriends`); the
  top-level models are always the latest. Every schema change needs a migration test from the previous
  version (see `RideTrackerTests/MigrationTests.swift`).
- A ride's track is **one compressed blob** (`TrackCodec`), never one row per GPS point.
  Format v2 (raw DEFLATE, Unix time) is specified in `spec/track-codec.md` and shared with Android;
  change it only with a new version number and a new golden file in `spec/fixtures`.
- Pure logic belongs in **`Packages/RideKit`** (no UIKit/SwiftUI/SwiftData there) with tests.
  App code (`RideTracker/`) maps models to RideKit value types (`SpotReference`, `MediaCandidate`).
- `Shared/` is compiled into both the app and the widget extension — it must not reference app-only
  types. Intents reach the app through `RideControl` handlers.
- **Brand ("Milestone", PLAN.md §12):** use the `Brand` tokens in `Shared/Brand.swift`, never ad-hoc
  system colours. **Highway yellow is a fill only**, with asphalt text on it — never yellow text on a
  light background. Signal red is for recording, End and problems only. Big numbers use the expanded
  width (`Brand.readout` / `Brand.stat` / `Brand.label`); everything else is the system font. The
  riding screen is always dark. Weather uses the `Brand.Sky` tokens and the 3D illustrations from
  `design/make-weather-3d.swift` (Assets.xcassets/Weather). The app icon is the **tread-to-pin** 3D render from
  `design/make-icon-tread.swift` (chosen 2026-11-17: a two-wheeler's tread mark curving up the road
  to a map pin; highway yellow kept — saffron tested and rejected, too close to Strava's orange; copy
  `design/AppIcon-Tread.png` into `AppIcon.appiconset/AppIcon.png`). The km-stone stays as the
  in-app milestone shape; its 3D icon (`design/make-icon-3d.swift`) is retired. The older flat
  version is `design/make-icon.swift`.
- **Our own icons, not SF Symbols, wherever the brand shows (decided 2026-11-16).** Drawn in code by
  `design/make-icons.swift` (24 pt grid, 2 pt round strokes) into `Assets.xcassets/Icons` as template
  PDFs, shown with `Image(icon:)` / `UIImage.icon(_:)` (`Shared/Icons.swift`). Spot categories use
  `SpotCategory.icon`. Generic UI glyphs (share, close, search, checkmark) stay SF Symbols.
- Debug builds accept `-seedSampleRide` to (re)create and open a sample ride for checking screens in
  the simulator (`RideTracker/App/SampleRide.swift`). `-openTab ride|rides|spots|friends|settings` opens a tab.
  `defaults write com.hatchedland.ridetracker fakeWeather rain` (also `rainSoon|storm|wind|heat|clearing|sunny|night|cloudy|sunset`)
  fakes the forecast and `fakeSong "Title|Artist"` the Music app (the simulator has none); delete
  them afterwards. Launch arguments don't survive the app being reopened, so use `defaults`.
- Build configs: **Debug / Release / Personal** all use no entitlements and local SwiftData (the cloud
  copy is Supabase), so every feature works in **Personal** (scheme "RideTracker (Personal)", flag
  `PERSONAL_TEAM`) for free-Apple-ID device testing. Keep new capabilities out of Personal unless free
  teams support them.
- `ios/RideTracker.xcodeproj` is **generated** by XcodeGen from `ios/project.yml` and not committed. Change
  targets, capabilities, Info.plist keys and entitlements in `project.yml`, then `xcodegen generate` in `ios/`.

## Layout

| Path | Purpose |
|---|---|
| `ios/` | Everything iOS; the rows below up to `TestRoutes` live in it |
| `Packages/RideKit` | Google Maps links, GPS filter, stats, auto-pause, track codec + crash buffer, album window, photo placement, photo trail (`Trail`), wishlist matching, ride naming, arrival time (`RidePace`, `RideTimePlan`), GPX/KML, song log + Apple Music links, friends (`SharePrivacy`, `SharedRide`, `LiveRide`, `LivePublishThrottle`), group chat (`ChatTimeline`, `ChatLayout`, `ChatText`), famous places ahead (`FamousPlaces`), weather (`GoogleWeather`, `WeatherAlerts`, `Sun`) |
| `RideTracker/Models` | SwiftData `Spot`, `Ride`, `MediaLink`, `PlayedSong`; versioned schema (V1, V2 frozen; V3 current) |
| `RideTracker/Services` | `RideRecorder` (the ride lifecycle), `LocationService`, `PhotoLibraryService`, `SpotService`, `MediaOrganizer`, `TrailNamer` (suggested stop names, cached on device), `MusicService`, `LiveActivityController`, `AccountService` (sign-in), `GooglePlacesClient` (Google Places, Routes and Weather requests; Debug fake weather), `SyncService` + `SyncRows` (Supabase sync), `FriendsService` + `FriendsBackend` (friends on Supabase), `ChatService` + `ChatBackend` (group chat), `AppSettings` |
| `RideTracker/Features` | SwiftUI screens: Record (incl. `ReadyDashboard`, `WeatherBackdrop`), Spots, Rides (incl. `RideTrailView`, `SoundtrackSection`), Media (incl. `MediaSharing`), Friends (feed, live ride, friends' spots, share sheet, privacy zones, `Chat/` group chat), `Common/Skeleton` (loading placeholders), Settings |
| `RideTrackerWidgets` | Live Activity + Dynamic Island |
| `Shared` | `RideActivityAttributes`, App Intents, `Brand` (palette, type, milestone shape) |
| `design` | Art drawn in code: `make-icon-tread.swift` (app icon), `make-icon-3d.swift` (retired km-stone icon), `make-stone-3d.swift` (distance stone), `make-weather-3d.swift` (3D weather → `Assets.xcassets/Weather`), `make-icons.swift` (line icons), `make-icon.swift` (older flat icon) |
| `TestRoutes` | GPX files for simulator playback |
| `supabase/` (root) | Migrations, Edge Functions (`publish-shared-ride`, shared logic in `functions/_shared`) |
| `spec/` (root) | Track file format and golden fixtures both apps (and the Edge Functions) test against |

## Commands

```sh
./scripts/test.sh                       # RideKit unit tests (works with only Command Line Tools)
./scripts/test-functions.sh             # Edge Functions' shared logic vs spec/fixtures (Node 23+)
(cd ios && xcodegen generate)           # regenerate the Xcode project after editing ios/project.yml
xcodebuild -project ios/RideTracker.xcodeproj -scheme RideTracker -destination 'platform=iOS Simulator,name=iPhone 17' test   # needs Xcode
./scripts/run-on-iphone.sh              # free Personal build (no iCloud) → USB iPhone
./scripts/typecheck-without-xcode.sh    # stopgap type-check on the macOS SDK when Xcode isn't installed
```

Before committing: RideKit tests pass (and `test-functions.sh` when `supabase/functions` or `spec/` changed), and the app builds (or, without Xcode, the type-check script
reports 0 real errors). New logic needs tests; aim for ≥ 80% coverage on new code.

## Git

- Repo: github.com/hatchedland/RideKit (public). Commit and push as **hatchedland**
  (`mail.rajanydv@gmail.com`). Never add `Co-Authored-By`.
- **This project never uses JIRA IDs.** Commits: `<gitmoji> <description>`, subject line only,
  real emoji (✨ 🐛 📝 💄 ♻️ ⚡ 🔧 ✅ 🔒 🚑). Branches: `<type>/<short-slug>` from `dev`.
- `main` = release, `dev` = development. Never open a PR unless explicitly asked; PRs target `dev`.
