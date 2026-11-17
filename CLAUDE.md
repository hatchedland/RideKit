# Ride Tracker — project rules

Native iOS app for **motorcycle / scooter** rides, built around **places**. Full product plan: [PLAN.md](PLAN.md).
Setup and release checklist: [README.md](README.md).

## Product rules (decided with the owner — don't change without asking)

- **Spots are the core.** Every spot stores a Google Maps URL built with the official Maps URLs format
  (`https://www.google.com/maps/search/?api=1&query=lat,lon`); the link itself needs no API.
- **Maps inside the app are Google Maps (decided 2026-11-12)**: Maps SDK for iOS through the shared
  `GoogleMapView` (`RideTracker/Features/Maps`), never MapKit's `Map`. Directions hand off to the Google
  Maps app via Maps URLs. **Place search and suggested spot / stop names use Google Places (API
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
  on free Personal builds).
- **No GoPro / action-camera support.** Photos without GPS stay in the album, just unpinned.
- **Photo trail** is the default way a ride's media is shown: stops (spots, or photo clusters within
  150 m / 10 min) joined by the road between them. Unnamed stops are **suggested, never auto-saved**
  as spots ("Save as spot"). Photos without GPS go into the trail by capture time but **never get a
  map pin**.
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
  live included; the destination never is. Shared photos are the one exception to "never copied":
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

## Tech constraints

- iOS 26+, Swift 6 strict concurrency, SwiftUI. **Apple frameworks only — the exceptions are the
  Google Maps SDK for iOS and supabase-swift** (SPM, pinned in `project.yml`). No other third-party
  dependencies. Supabase host + publishable key live in git-ignored `Config/Secrets.xcconfig`.
- **Accounts (decided 2026-11-16): Supabase Auth, passwordless email link** (`AccountService`,
  `ridetracker://auth-callback`). Free projects can't customise the default email template, so the
  6-digit code waits for an own SMTP sender (before App Store). Signed out, only the sign-in screen shows.
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
- Pure logic belongs in **`Packages/RideKit`** (no UIKit/SwiftUI/SwiftData there) with tests.
  App code (`RideTracker/`) maps models to RideKit value types (`SpotReference`, `MediaCandidate`).
- `Shared/` is compiled into both the app and the widget extension — it must not reference app-only
  types. Intents reach the app through `RideControl` handlers.
- **Brand ("Milestone", PLAN.md §12):** use the `Brand` tokens in `Shared/Brand.swift`, never ad-hoc
  system colours. **Highway yellow is a fill only**, with asphalt text on it — never yellow text on a
  light background. Signal red is for recording, End and problems only. Big numbers use the expanded
  width (`Brand.readout` / `Brand.stat` / `Brand.label`); everything else is the system font. The
  riding screen is always dark. Weather uses the `Brand.Sky` tokens and the 3D illustrations from
  `design/make-weather-3d.swift` (Assets.xcassets/Weather). The app icon is the 3D render from `design/make-icon-3d.swift`
  (chosen 2026-11-16; copy `design/AppIcon-3D.png` into `AppIcon.appiconset/AppIcon.png`). The older flat
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
- `RideTracker.xcodeproj` is **generated** by XcodeGen from `project.yml` and not committed. Change
  targets, capabilities, Info.plist keys and entitlements in `project.yml`, then `xcodegen generate`.

## Layout

| Path | Purpose |
|---|---|
| `Packages/RideKit` | Google Maps links, GPS filter, stats, auto-pause, track codec + crash buffer, album window, photo placement, photo trail (`Trail`), wishlist matching, ride naming, GPX/KML, song log + Apple Music links, friends (`SharePrivacy`, `SharedRide`, `LiveRide`, `LivePublishThrottle`), group chat (`ChatTimeline`, `ChatLayout`, `ChatText`), famous places ahead (`FamousPlaces`), weather (`GoogleWeather`, `WeatherAlerts`, `Sun`) |
| `RideTracker/Models` | SwiftData `Spot`, `Ride`, `MediaLink`, `PlayedSong`; versioned schema (V1, V2 frozen; V3 current) |
| `RideTracker/Services` | `RideRecorder` (the ride lifecycle), `LocationService`, `PhotoLibraryService`, `SpotService`, `MediaOrganizer`, `TrailNamer` (suggested stop names, cached on device), `MusicService`, `LiveActivityController`, `AccountService` (sign-in), `GooglePlacesClient` (Google Places, Routes and Weather requests; Debug fake weather), `SyncService` + `SyncRows` (Supabase sync), `FriendsService` + `FriendsBackend` (friends on Supabase), `ChatService` + `ChatBackend` (group chat), `AppSettings` |
| `RideTracker/Features` | SwiftUI screens: Record (incl. `ReadyDashboard`, `WeatherBackdrop`), Spots, Rides (incl. `RideTrailView`, `SoundtrackSection`), Media (incl. `MediaSharing`), Friends (feed, live ride, friends' spots, share sheet, privacy zones, `Chat/` group chat), `Common/Skeleton` (loading placeholders), Settings |
| `RideTrackerWidgets` | Live Activity + Dynamic Island |
| `Shared` | `RideActivityAttributes`, App Intents, `Brand` (palette, type, milestone shape) |
| `design` | Art drawn in code: `make-icon-3d.swift` (app icon), `make-stone-3d.swift` (distance stone), `make-weather-3d.swift` (3D weather → `Assets.xcassets/Weather`), `make-icons.swift` (line icons), `make-icon.swift` (older flat icon) |
| `TestRoutes` | GPX files for simulator playback |

## Commands

```sh
./scripts/test.sh                       # RideKit unit tests (works with only Command Line Tools)
xcodegen generate                       # regenerate the Xcode project after editing project.yml
xcodebuild -scheme RideTracker -destination 'platform=iOS Simulator,name=iPhone 17' test   # needs Xcode
./scripts/run-on-iphone.sh              # free Personal build (no iCloud) → USB iPhone
./scripts/typecheck-without-xcode.sh    # stopgap type-check on the macOS SDK when Xcode isn't installed
```

Before committing: RideKit tests pass, and the app builds (or, without Xcode, the type-check script
reports 0 real errors). New logic needs tests; aim for ≥ 80% coverage on new code.

## Git

- Repo: github.com/hatchedland/RideKit (public). Commit and push as **hatchedland**
  (`mail.rajanydv@gmail.com`). Never add `Co-Authored-By`.
- **This project never uses JIRA IDs.** Commits: `<gitmoji> <description>`, subject line only,
  real emoji (✨ 🐛 📝 💄 ♻️ ⚡ 🔧 ✅ 🔒 🚑). Branches: `<type>/<short-slug>` from `dev`.
- `main` = release, `dev` = development. Never open a PR unless explicitly asked; PRs target `dev`.
