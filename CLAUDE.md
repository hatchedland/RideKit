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
- **Ride soundtrack**: songs played in the **Music app** (Apple Music / own library) for ≥ 30 s during
  a ride are logged with time and place, opened via Apple Music links. Other apps (Spotify, …) are not
  readable by iOS apps — don't promise them. Uses MediaPlayer (no MusicKit entitlement, so it works
  on free Personal builds).
- **No GoPro / action-camera support.** Photos without GPS stay in the album, just unpinned.
- **App Store release target.** No backend, no accounts: SwiftData + CloudKit private database only.

## Tech constraints

- iOS 26+, Swift 6 strict concurrency, SwiftUI. **Apple frameworks only — no third-party dependencies.**
- Always the latest non-deprecated APIs, e.g. `CLLocationUpdate.liveUpdates` + `CLServiceSession` +
  `CLBackgroundActivitySession` (only "When In Use" permission — never ask for "Always"),
  `MKReverseGeocodingRequest` (not `CLGeocoder`), `MKMapItem.location` / `.address` (not `placemark`).
- **SwiftData models must stay CloudKit-compatible**: no `@Attribute(.unique)`, every property has a
  default or is optional, every relationship optional. Schema changes are **additive only** and go
  through a new `VersionedSchema` + `SchemaMigrationPlan` (see `RideTracker/Models/Schema.swift`).
  Released versions are **frozen as nested model copies** (V1 = v1.0.0; V2 adds `PlayedSong`); the
  top-level models are always the latest. Every schema change needs a migration test from the previous
  version (see `RideTrackerTests/MigrationTests.swift`).
- A ride's track is **one compressed blob** (`TrackCodec`), never one row per GPS point.
- Pure logic belongs in **`Packages/RideKit`** (no UIKit/SwiftUI/SwiftData there) with tests.
  App code (`RideTracker/`) maps models to RideKit value types (`SpotReference`, `MediaCandidate`).
- `Shared/` is compiled into both the app and the widget extension — it must not reference app-only
  types. Intents reach the app through `RideControl` handlers.
- Build configs: **Debug / Release** use iCloud (`RideTracker.entitlements`). **Personal** (scheme
  "RideTracker (Personal)", flag `PERSONAL_TEAM`) has no entitlements and local-only SwiftData, for
  free-Apple-ID device testing. Keep new capabilities out of Personal unless free teams support them.
- `RideTracker.xcodeproj` is **generated** by XcodeGen from `project.yml` and not committed. Change
  targets, capabilities, Info.plist keys and entitlements in `project.yml`, then `xcodegen generate`.

## Layout

| Path | Purpose |
|---|---|
| `Packages/RideKit` | Google Maps links, GPS filter, stats, auto-pause, track codec + crash buffer, album window, photo placement, wishlist matching, ride naming, GPX/KML |
| `RideTracker/Models` | SwiftData `Spot`, `Ride`, `MediaLink`, versioned schema |
| `RideTracker/Services` | `RideRecorder` (the ride lifecycle), `LocationService`, `PhotoLibraryService`, `SpotService`, `MediaOrganizer`, `LiveActivityController`, `AppSettings` |
| `RideTracker/Features` | SwiftUI screens: Record, Spots, Rides, Media, Settings |
| `RideTrackerWidgets` | Live Activity + Dynamic Island |
| `Shared` | `RideActivityAttributes`, App Intents |
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
