# Ride Tracker

A native iOS app for motorcycle and scooter rides, built around **places**:

- **Spots.** Mark a spot with one tap while riding, from the app, the Lock Screen, the Action
  button or Siri. Every spot saves a **Google Maps link**.
- **Wishlist.** Save places you want to go (paste a Google Maps link, search, or drop a pin).
  A ride that stops there, or takes a photo there, marks the spot **Visited**. You get an alert
  when one is within 2 km.
- **A Photos album for every ride.** Name the ride when you start it. Every photo and video taken
  between **Start** and **End** lands in *Photos › Albums › Ride Tracker › your ride name*.
- Inside the app, photos also appear at the spot where you took them (within 150 m) or along the
  route.

No backend and no account. Data stays on the device and syncs through the user's own iCloud
(SwiftData + CloudKit). See [PLAN.md](PLAN.md) for the full product plan.

## Project layout

| Path | What's there |
|---|---|
| `Packages/RideKit` | Pure Swift logic, fully unit-tested: Google Maps link building/parsing, GPS filtering, ride stats, auto-pause, track storage and crash recovery, the ride-album time window, photo↔spot matching, wishlist auto-visit, ride naming, GPX/KML export |
| `RideTracker/` | The iOS app: SwiftData models, services (location, Photos albums, spots, recorder, Live Activity) and SwiftUI screens |
| `RideTrackerWidgets/` | Live Activity and Dynamic Island, with Mark spot and Pause buttons |
| `Shared/` | Code compiled into both the app and the widget (activity attributes, App Intents) |
| `RideTrackerTests/` | App-level tests |
| `TestRoutes/` | GPX routes for simulator location playback |
| `project.yml` | XcodeGen definition. The `.xcodeproj` is generated, not committed |

## Getting started

1. Install **Xcode 26** from the Mac App Store, then:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app
   brew install xcodegen
   ```
2. Generate and open the project:
   ```sh
   xcodegen generate
   open RideTracker.xcodeproj
   ```
3. In **Signing & Capabilities**, pick your team for both targets, or set `DEVELOPMENT_TEAM` in
   `project.yml`. iCloud, Live Activities on device, TestFlight and the App Store need a paid
   Apple Developer Program membership.
4. Run on the simulator. The scheme replays `TestRoutes/DelhiToMurthal.gpx` (NH-44 at about
   60 km/h, with a 3-minute stop at Kundli). For real background tracking and Live Activities, use
   a device.

## Run on your own iPhone (free Apple ID)

No paid developer account is needed to test on your own phone. The **Personal** build is identical
except iCloud sync is off, because free accounts can't use iCloud. Data stays on the phone.

1. **Xcode › Settings › Accounts › +** and sign in with your Apple ID.
2. Connect the iPhone by cable, unlock it, and tap **Trust This Computer**.
3. On the iPhone, turn on **Settings › Privacy & Security › Developer Mode** (it restarts).
4. Run:
   ```sh
   ./scripts/run-on-iphone.sh
   ```
   Or in Xcode, pick the **RideTracker (Personal)** scheme and your iPhone, then press **⌘R**.
5. The first time, the iPhone blocks the app: go to **Settings › General › VPN & Device Management**,
   tap your Apple ID and choose **Trust**.

Free installs stop opening after **7 days**. Run the script again to refresh; your rides and spots are
kept.

## Tests

```sh
./scripts/test.sh            # RideKit unit tests (works with only the Command Line Tools)
```

With Xcode installed, **⌘U** runs the RideKit and app tests together.

`scripts/typecheck-without-xcode.sh` type-checks the app against the macOS SDK on a Mac without
Xcode. It's a stopgap: see the comments in the script for what it can and can't verify.

## Before App Store submission

- [ ] Set the team and confirm the bundle IDs (`com.hatchedland.ridetracker` and `.widgets`) and the iCloud container (`iCloud.com.hatchedland.ridetracker`)
- [ ] In the CloudKit Console, deploy the schema to **Production** after the first full test (it can't be changed destructively afterwards)
- [ ] Publish a privacy policy page and add its URL in App Store Connect
- [ ] App Privacy: location and photos are used on device only, not linked to the user, not used for tracking
- [ ] App Review notes: background location records the ride route, and full Photos access builds the ride album. Attach a short screen recording
- [ ] Replace the placeholder app icon if you'd like a designed one
