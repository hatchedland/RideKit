# Ride Tracker — project rules

Native iOS app for **motorcycle / scooter** rides, built around **places**. Full product plan: [PLAN.md](PLAN.md).
Setup and release checklist: [README.md](README.md).

## Product rules (decided with the owner — don't change without asking)

- **Spots are the core.** Every spot stores a Google Maps URL built with the official Maps URLs format
  (`https://www.google.com/maps/search/?api=1&query=lat,lon`). No Google API keys, no Places API.
- **Mark spot while riding = one tap, zero looking**: riding screen, Lock Screen Live Activity, Action
  button, Siri. Save first, name later. Never add UI that needs attention while moving.
- **Wishlist**: spots are `wantToGo` or `visited`. A ride auto-visits a wishlist spot only if the rider
  **stopped ≥ 2 min** or **took a photo** within the radius — riding past doesn't count. Always undoable.
- **Spot radius is 150 m** (photo → spot matching and auto-visit). Revisit radius is 100 m. Nearby
  wishlist alert at 2 km.
- **The rider names the ride at Start.** Empty name → "Ride · 12 Oct 2026". The name is also the
  Photos album name; renaming a ride renames its album.
- **Every photo/video taken between Start and End goes into the ride's album** in
  Photos › Albums › Ride Tracker. Built from the **capture-time window** (pauses included), never only
  from live events. Late arrivals are swept for 48 h. Screenshots excluded by default.
- **Photos are referenced, never copied** (`PHAsset` local ID + `PHCloudIdentifier`). Deleting a ride
  or spot never deletes photos; deleting an album only on explicit choice.
- **Sharing** sends the **original** Photos files (edited version if any, Live Photo still) through the
  system share sheet as file URLs. "Open Photos" can only open the Photos app (no public API to open a
  specific item) — don't claim otherwise.
- **Ride soundtrack**: songs played in the **Music app** (Apple Music / own library) for ≥ 30 s during
  a ride are logged with time and place, opened via Apple Music links. Other apps (Spotify, …) are not
  readable by iOS apps — don't promise them. Uses MediaPlayer (no MusicKit entitlement, so it works
  on free Personal builds).
- **No GoPro / action-camera support.** Photos without GPS stay in the album, just unpinned.
- **Photo trail** is the default way a ride's media is shown: stops (spots, or photo clusters within
  150 m / 10 min) joined by the road between them. Unnamed stops are **suggested, never auto-saved**
  as spots ("Save as spot"). Photos without GPS go into the trail by capture time but **never get a
  map pin**.
- **Bikes and scooters only.** No car mode or vehicle type.
- **App Store release target.** No backend, no accounts: SwiftData + CloudKit (private database for
  the rider's data, **CloudKit sharing for Friends**). No servers of our own, ever.
- **Friends (decided 2026-10-15)**: each rider shares one CloudKit zone ("Friends") with people they
  invite — friends-only, nothing public, iPhone-only. Sharing is one-way (invite back to see theirs).
  Friends see shared rides (route, stops, songs, **only photos the rider picked**) and can follow a
  ride **live** (~1 update/min, chosen on the Start sheet, ends at End or after 12 h). The **first and
  last 500 m** of every shared ride and everything in **privacy zones** are never shared, live included.
  Shared photos are the one exception to "never copied": 2048 px JPEG copies of the chosen photos only.
  Nothing social on the riding screen beyond a passive "Live" chip; no comments or likes. Every
  friend's stop has **Add to my wishlist** — that's the point of the feature. Not in the Personal build.

## Tech constraints

- iOS 26+, Swift 6 strict concurrency, SwiftUI. **Apple frameworks only — no third-party dependencies.**
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
  riding screen is always dark. The icon is generated by `design/make-icon.swift`.
- Debug builds accept `-seedSampleRide` to (re)create and open a sample ride for checking screens in
  the simulator (`RideTracker/App/SampleRide.swift`).
- Build configs: **Debug / Release** use iCloud (`RideTracker.entitlements`). **Personal** (scheme
  "RideTracker (Personal)", flag `PERSONAL_TEAM`) has no entitlements and local-only SwiftData, for
  free-Apple-ID device testing. Keep new capabilities out of Personal unless free teams support them.
- `RideTracker.xcodeproj` is **generated** by XcodeGen from `project.yml` and not committed. Change
  targets, capabilities, Info.plist keys and entitlements in `project.yml`, then `xcodegen generate`.

## Layout

| Path | Purpose |
|---|---|
| `Packages/RideKit` | Google Maps links, GPS filter, stats, auto-pause, track codec + crash buffer, album window, photo placement, photo trail (`Trail`), wishlist matching, ride naming, GPX/KML, song log + Apple Music links, friends (`SharePrivacy`, `SharedRide`, `LiveRide`, `LivePublishThrottle`) |
| `RideTracker/Models` | SwiftData `Spot`, `Ride`, `MediaLink`, `PlayedSong`; versioned schema (V1, V2 frozen; V3 current) |
| `RideTracker/Services` | `RideRecorder` (the ride lifecycle), `LocationService`, `PhotoLibraryService`, `SpotService`, `MediaOrganizer`, `TrailNamer` (suggested stop names, cached on device), `MusicService`, `LiveActivityController`, `FriendsService` + `FriendsCloud` (CloudKit sharing), `AppSettings` |
| `RideTracker/Features` | SwiftUI screens: Record, Spots, Rides (incl. `RideTrailView`, `SoundtrackSection`), Media (incl. `MediaSharing`), Friends (feed, live ride, friends' spots, share sheet, privacy zones), Settings |
| `RideTrackerWidgets` | Live Activity + Dynamic Island |
| `Shared` | `RideActivityAttributes`, App Intents, `Brand` (palette, type, milestone shape) |
| `design` | `make-icon.swift` (renders the app icon) |
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
