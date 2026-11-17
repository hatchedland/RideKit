# Ride Tracker

A native iOS app for motorcycle and scooter rides, built around **places**:

- **Spots.** Mark a spot with one tap while riding, from the app, the Lock Screen, the Action
  button or Siri. Every spot saves a **Google Maps link**.
- **Wishlist.** Save places you want to go (paste a Google Maps link, search Google Places, or drop
  a pin). A ride that stops there, or takes a photo there, marks the spot **Visited**. You get an
  alert when one is within 2 km.
- **A pre-ride dashboard.** The Ride tab answers "can I ride now?" (the weather here, with a 3D
  illustration, the outlook for the next 6 hours and an hourly strip), shows your ODO/TRIP and the
  nearest wishlist spots as one-tap destinations, and keeps **Start ride** under your thumb.
- **A riding screen built like an instrument cluster.** The map edge to edge; speed, distance,
  time and the weather on a dark band at the top; Pause · **Mark spot** · End in one row at the
  bottom. Passive alerts only: a wishlist spot nearby, **famous places ahead** (well-reviewed sights
  within 2 km, the 3 nearest at a time) and **weather** (storm, rain, wind, heat, rain easing,
  sunset with distance still to go). A read-only line shows the song playing in the Music app.
- **A Photos album for every ride.** Name the ride when you start it. Every photo and video taken
  between **Start** and **End** lands in *Photos › Albums › Ride Tracker › your ride name*.
- **Photo trail.** Each ride's photos and videos are shown as a trail of **stops** joined by the
  road between them: the spot where you took them (within 150 m), or a group of photos with a
  suggested landmark name and a **Save as spot** button. Each stop shows its km from the start; each
  stretch of road shows its distance, time and the songs that played on it. A Grid view is one tap away.
- **Share** any ride or spot photo or video to WhatsApp, Instagram, AirDrop and other apps as the
  original file, or jump to the Photos app.
- **Ride soundtrack.** Songs you play in the Music app during a ride (30 s or more) are logged with
  when and where they played. Open them in Apple Music or share the list.
- **Friends.** Find riders inside the app by their **@handle** and send a friend request; once
  accepted you're friends both ways. See the rides they share (route, stops, the photos they
  picked, soundtrack), follow a friend's ride live, and add any of their stops to your wishlist. The
  first and last 500 m and your privacy zones are never shared, and nor is the destination.

**An account is required** (passwordless email link, Supabase Auth). The phone records offline in
SwiftData and syncs every ride, spot, photo link and song to the rider's own rows in
[Supabase](supabase/migrations) (row-level security per rider). Photo and video files stay in the
Photos library; only photos picked for friends are copied (2048 px JPEG). Maps, place search, routes
and weather come from **Google Maps Platform** with one iOS key. `CLAUDE.md` holds the current
product rules; [PLAN.md](PLAN.md) is the original plan and its history.

**Look:** the *Milestone* brand, after the Indian highway km-stone: highway yellow, asphalt and chalk,
wide signboard numbers, and a dark "instrument cluster" riding screen. The rules live in
`Shared/Brand.swift`.

## Project layout

| Path | What's there |
|---|---|
| `Packages/RideKit` | Pure Swift logic, fully unit-tested: Google Maps link building/parsing, Google Places / Routes / Weather requests and parsing, GPS filtering, ride stats, auto-pause, track storage and crash recovery, the ride-album time window, photo↔spot matching, wishlist auto-visit, famous places ahead, weather alerts and sunset, ride naming, GPX/KML export, the song log for ride soundtracks, the photo trail (stops, legs, km from start), friends' sharing privacy |
| `RideTracker/` | The iOS app: SwiftData models (versioned schema with migrations), services (account, Supabase sync, friends, location, Photos albums, spots, music, recorder, Live Activity) and SwiftUI screens, including media sharing |
| `supabase/` | Database schema, row-level security, storage buckets and friend requests, as migrations |
| `Config/` | `Secrets.example.xcconfig`: copy to the git-ignored `Secrets.xcconfig` with the Google key and Supabase host/key |
| `RideTrackerWidgets/` | Live Activity and Dynamic Island, with Mark spot and Pause buttons |
| `Shared/` | Code compiled into both the app and the widget (activity attributes, App Intents, brand palette and type) |
| `RideTrackerTests/` | App-level tests, including schema migration and media export |
| `TestRoutes/` | GPX routes for simulator location playback |
| `design/` | Art drawn in code: `make-icon-tread.swift` (the app icon: a tread mark ending in a map pin), `make-icon-3d.swift` (the retired km-stone icon), `make-stone-3d.swift` (the distance stone), `make-weather-3d.swift` (the 3D weather illustrations, written straight into `Assets.xcassets/Weather`), `make-icons.swift` (the line icons). The 3D scripts need Xcode: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift design/make-weather-3d.swift` |
| `project.yml` | XcodeGen definition. The `.xcodeproj` is generated, not committed |

## Getting started

1. Install **Xcode 26** from the Mac App Store, then:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app
   brew install xcodegen
   ```
2. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and fill in the Google key
   and the Supabase host and publishable key (the comments say where each comes from). Without the
   Google key, maps show a placeholder and places, routes and weather stay empty.
3. Generate and open the project:
   ```sh
   xcodegen generate
   open RideTracker.xcodeproj
   ```
4. In **Signing & Capabilities**, pick your team for both targets, or set `DEVELOPMENT_TEAM` in
   `project.yml`. TestFlight and the App Store need a paid Apple Developer Program membership.
5. Run on the simulator and sign in (the email link opens the app through `ridetracker://auth-callback`). The scheme replays `TestRoutes/DelhiToMurthal.gpx` (NH-44 at about
   60 km/h, with a 3-minute stop at Kundli). For real background tracking and Live Activities, use
   a device.
6. **Sample ride (Debug builds only):** add `-seedSampleRide` to the scheme's launch arguments, or
   `xcrun simctl launch <device> com.hatchedland.ridetracker -seedSampleRide`. The app (re)creates a
   Delhi → Murthal ride with a spot, a photo stop, a photo without location and two songs, and opens it.
   Photos point at whatever is in the simulator's library, so allow full Photos access first (on
   iOS 26 tap **Allow Full Access**; `simctl privacy grant` isn't honoured).
7. **Fake weather and music (Debug builds only):** the simulator has no rain on demand and no Music
   app, so the app reads two settings:
   ```sh
   xcrun simctl spawn booted defaults write com.hatchedland.ridetracker fakeWeather rain   # or rainSoon, storm, wind, heat, clearing, sunny, night, cloudy, sunset
   xcrun simctl spawn booted defaults write com.hatchedland.ridetracker fakeSong "Blinding Lights|The Weeknd"
   xcrun simctl spawn booted defaults delete com.hatchedland.ridetracker fakeWeather       # back to real weather
   ```
   Use these rather than launch arguments, which are lost when the app is reopened.

## Run on your own iPhone (free Apple ID)

No paid developer account is needed to test on your own phone. The **Personal** build has every
feature: it uses no entitlements, and the cloud copy is Supabase, not iCloud.

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

**No cable after the first time:** once the iPhone has been paired by cable, it can install over
Wi-Fi. Keep the iPhone and Mac on the **same Wi-Fi network** with the iPhone unlocked, and run the
script as usual. If it isn't found, open **Xcode › Window › Devices and Simulators**, select the iPhone
and tick **Connect via network**.

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

- [ ] Set the team and confirm the bundle IDs (`com.hatchedland.ridetracker` and `.widgets`)
- [ ] Google Cloud: the iOS key is restricted to the bundle ID and its **API restrictions** list Maps SDK for iOS, Places API (New), Routes API and **Weather API** (a missing one fails with `403 API_KEY_SERVICE_BLOCKED`). Set budget alerts: places, routes and weather are billed past the free allowance
- [ ] Supabase: own SMTP sender so sign-in can use the 6-digit code (free projects can't change the default email template), and the migrations in `supabase/migrations` applied to production
- [ ] Test Friends with **two accounts on two devices**: @handle search, friend request and accept, share a ride with photos, live ride, remove friend
- [ ] Publish a privacy policy page and add its URL in App Store Connect
- [ ] App Privacy: account email; rides, spots, photo **links** and songs synced to the rider's own Supabase rows; **rides shared with friends** (route, stops, chosen photos, live position) visible only to accepted friends; location sent to Google for places, routes and weather. Not used for tracking
- [ ] App Review notes: background location records the ride route, and full Photos access builds the ride album. Provide a demo account and attach a short screen recording
- [ ] Decide the App Store name (shortlist in [PLAN.md](PLAN.md) §11) and check the km-stone icon at small sizes
