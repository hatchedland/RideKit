# Ride Tracker — iOS App Plan

A native iOS app for motorcycle / scooter riders that is built around **places**. While riding, you
record your route and mark **spots** (landmarks, viewpoints, dhabas, fuel stops) with one tap. Each
spot saves its exact location and a **Google Maps link**. Your **photos and videos are organised
automatically** by the spot and ride where you took them.

Data stays on the device and syncs through the user's own iCloud. The app is built for
**App Store release**.

_Last updated: 2026-10-15_

> **Status:** v1.0.0 and **v1.1.0 are released** on `main`. The **Milestone brand** and the **photo
> trail** are merged into `dev` and going to `main` (version not bumped yet). The app runs on the
> owner's iPhone through the free **Personal** build (no paid Apple Developer Program yet, so iCloud
> sync, TestFlight and the App Store are on hold). Real-ride field testing is in progress.
> **Friends** (phases 1–2, see §3) is built on `feature/friends`; it needs iCloud, so it can only be
> tried once the Developer Program is active. **Next: Trips.**

---

## 1. Core idea

```
            Ride (route recorded in the background)
  ●━━━━━━━━━━━━━━━━━━★━━━━━━━━━━━━━━━━━━━━━━━★━━━━━━━━━━━━━━━━━━━━●
 start               │                       │                    end
                  Spot A                  Spot B
            "Old fort viewpoint"      "Chai stall on NH-44"
          google.com/maps/…?query=…  google.com/maps/…?query=…
             📷📷🎥 (3 items)           📷 (1 item)
                                                  + 12 other photos from the
                                                    ride, placed along the route
```

1. **Spots are the main thing.** You can mark one in a single tap during a ride, by long-pressing on
   the map, by pasting a Google Maps link, or from your current location at any time.
2. **Wishlist:** save places you *want* to go. When a ride passes one, it is marked **Visited**.
3. **Every spot has a Google Maps URL** that is saved, copyable, shareable, and opens in the Google
   Maps app.
4. **Every ride gets its own album in the Photos app.** Every photo and video taken between
   **Start ride** and **End ride** is put into it automatically.
5. **Inside the app, photos are also organised by location.** Each ride item is attached to the
   nearest spot, or placed along the route.

---

## 2. Decisions

| Area | Decision | Why |
|---|---|---|
| Platform | iOS 26+, iPhone first, Swift 6.2, SwiftUI | Newest APIs, no fallback code needed |
| Persistence | SwiftData + CloudKit (private database) | No backend, no login, private by default |
| Friends | CloudKit **sharing**: one zone per rider, shared with invited friends (decided 2026-10-15) | Social without a backend or accounts; friends-only by construction; no public content to moderate. Costs: iPhone-only friends, ~1 min live latency |
| Location tracking | `CLLocationUpdate.liveUpdates()` + `CLBackgroundActivitySession` | Tracks in the background with only "When In Use" permission |
| Place names | MapKit `MKReverseGeocodingRequest` + `MKLocalPointsOfInterestRequest` | Free and built in. Suggests a landmark name for a new spot (`CLGeocoder` is deprecated in iOS 26) |
| Google Maps link | Built from coordinates using the official [Maps URLs](https://developers.google.com/maps/documentation/urls) format | Works everywhere, with **no API key and no cost** |
| Photos/videos | **Reference** items in the Photos library through PhotoKit; don't copy them | No duplicate storage, no iCloud quota blow-up, and edits made in Photos still show up |
| Organising in Photos | **Automatic album per ride** in a "Ride Tracker" folder in the Photos app, containing everything captured between ride start and end | Your organisation stays visible outside our app too |
| Maps | MapKit for SwiftUI, with spot clustering | No API keys |
| Dependencies | Apple frameworks only | Simpler review and privacy story |

**Not in v1:** a backend or accounts, Google Places API lookups (they need a paid key), turn-by-turn
navigation, and crash detection. (Social arrived later as **Friends**, still without a backend.)

---

## 3. Feature scope

### v1.0.0 — MVP (released)

**A. Spots (core)**
- **Mark a spot while riding** without unlocking or looking at the phone for long:
  - a big "📍 Mark spot" button on the riding screen
  - a button on the **Lock Screen Live Activity** (an interactive `LiveActivityIntent`)
  - the **Action button** and **Siri** ("Mark spot in Ride Tracker") through App Intents
  - the spot is saved instantly with its coordinates and time. You can name it later.
- **Other ways to add a spot:** long-press on the map, "current location", or **paste a Google Maps
  link**. We parse the coordinates from it, and short `maps.app.goo.gl` links are followed to their
  full URL first.
- **Spot details:** name (with a suggested nearby landmark or address), category (viewpoint, food,
  fuel, temple/monument, stay, mechanic, custom), notes, rating, visit date(s) and linked ride.
- **Google Maps URL:** saved on the spot, with Copy, Share, and Open in Google Maps (uses the app if
  installed, otherwise the web). Apple Maps is also available.
- **Spots map:** every spot on one map, clustered, filterable by category or ride, and searchable.
- **Revisits:** marking a spot within ~100 m of an existing one offers "Add visit to *X*?" instead of
  creating a duplicate.

**B. Wishlist (core)**
- Every spot has a status: **Want to go** or **Visited**.
- Wishlist spots can be added at any time, without a ride: paste a Google Maps link, long-press the
  map, or search by name (`MKLocalSearch`).
- The map shows wishlist and visited spots in different colours, and you can filter by status.
- **Auto-visit:** when a recorded ride passes within the radius of a wishlist spot (default 150 m),
  the spot is switched to **Visited** with that ride and date attached. You confirm or undo this on
  the ride summary.
- **Nearby alert while riding:** "📍 *Chandratal Lake* (wishlist) is 2 km away". This uses the
  live ride location, so it needs no extra permission. It can be turned off in Settings.
- Optional fields for planning: notes, "best season", and a priority.

**C. Ride album in the Photos app (core)**
- **On Start ride:** create an album with the ride's name (see E. Ride recording) inside a **"Ride Tracker"**
  folder in the Photos app.
- **While riding:** a Photos library observer adds new photos and videos as they're taken. The app
  is already running in the background because of location tracking, so this works with the phone
  locked.
- **On End ride:** a final pass fetches *every* item with a capture time between start and end
  (**including paused time**, because stopping is exactly when you take photos), adds any that are missing.
- **Late arrivals:** items that show up in the library after the ride (iCloud sync from another
  device, a Live Photo still processing, AirDrop from a friend's phone keeps its original capture
  time) are swept into the album the next time the app opens, for 48 hours after the ride.
- **Included:** photos, videos, Live Photos, and photos from any camera app, because matching is by
  capture time. **Excluded by default:** screenshots and screen recordings (a toggle in Settings).
- Renaming the ride renames the album. Deleting the ride asks whether to also delete the album; the
  photos themselves are never deleted.

**D. Photos organised by location inside the app**
- Each ride item that has GPS data and was taken within the radius of a spot is attached to that
  spot. Other items are placed on the route at the point where they were taken.
- Items without GPS (location turned off) stay in the ride album and gallery without a map pin.
- **Manual fixes:** move an item to another spot, detach it, or add items from the picker.
- **Browse:**
  - spot → photo/video grid (videos play inline)
  - ride → **photo trail** (default) or grid, and photos along the route on the map
  - "Places" view → media grouped by area/city (from reverse geocoding)
- **Photo trail** (added after v1.1.0): the ride told in order, `START → road → stop → road → … → END`.
  - **Stops:** a spot (photos within the spot radius, or a spot marked/visited on the ride, even
    without photos), or a **cluster** of photos within 150 m and 10 min of each other.
  - Each stop shows a milestone marker, its name, **km from the start**, the time and a swipeable
    photo strip. Tapping a photo opens the full-screen viewer; tapping a spot opens it.
  - **Unnamed clusters** get a suggested name (nearest Apple Maps landmark, else "near *town*", ✦)
    cached on the device (not synced), and a **Save as spot** button. The new spot's visit is dated
    when the photos were taken, and its photos attach to it.
  - **Road between stops:** distance and riding time, the songs that started on that stretch, and
    photos without GPS taken away from any stop ("On the road").
  - **Photos without GPS** join the stop closest in time (within 10 min); they're placed in the
    trail only and still **never get a map pin**.
  - Pure logic in RideKit (`Trail.build`), tested; the app maps models to it (`RideTrailRows`,
    `TrailNamer`). No schema change.

**E. Ride recording (the frame around spots)**
- **Start ride → name it:** a sheet with a text field (keyboard opens automatically) and a large
  **Start** button. Recent names and wishlist spot names appear as suggestions (for example
  *"Rishikesh run"*). If the field is left empty, the default is *"Ride · 12 Oct 2026"*, so starting is
  never blocked. The name is used for the ride and its Photos album, for example
  *Ride Tracker / Rishikesh run*. Two rides with the same name get the date added.
- Pause/resume and stop. Tracking continues in the background with the screen locked.
- Starting from the Action button or Siri uses "Start ride *name*" if a name is spoken, and the
  default name otherwise. You can rename the ride later.
- Live stats: speed, distance, time, average and max speed. Auto-pause at stops.
- Crash-safe: points are appended to disk as they arrive, and an interrupted ride is recovered on the
  next launch.
- Ride detail: route map coloured by speed, spots ★, photo pins 📷, stats and a speed chart.

**F. Live Activity / Dynamic Island:** speed, distance and time, the photo count in the ride album, and the **Mark spot** button.

**G. iCloud sync and export:** spots (including the wishlist), rides and links sync across your
devices. Spots can be exported as GPX or KML, which **imports into Google My Maps**.

### v1.1.0 (released)
- **Share photos and videos** from a ride or spot to any app (WhatsApp, Instagram, Messages, AirDrop,
  Files…) as original full-quality files: from the full-screen viewer, by long-pressing a thumbnail,
  or with **Share all**. **Open Photos** jumps to the Photos app (iOS can't open it at a specific
  item).
- **Ride soundtrack:** songs played in the **Music app** for 30+ seconds during a ride are logged with
  time and place. A 🎵 Soundtrack list in ride detail and the summary opens songs in Apple Music, and
  the list can be shared. Other apps (Spotify, …) can't be read by iOS apps. There's a Settings toggle.
- **Free iPhone testing:** a Personal build without iCloud plus `scripts/run-on-iphone.sh`, so the app
  runs on your own iPhone with a free Apple ID (reinstall every 7 days).

### v1.2.0 (on `dev`, not yet versioned)
- **Milestone brand:** the Indian highway km-stone as the app's identity (see §12).
- **Photo trail** on ride detail (see D above), with **Save as spot** for unnamed stops.
- Debug-only `-seedSampleRide` launch argument for checking screens in the simulator.

### Friends (on `feature/friends`, decided 2026-10-15)

Positioning: not "another Strava feed" — live dots already exist (WhatsApp, Google Maps, Strava
Beacon, Riser, REVER). What nobody does well is **where my friends stopped, what they shot, and
stealing their spots for my wishlist**. That loop is the point: friend's ride → your wishlist → your
ride → their feed.

- **Invite:** Friends tab › Invite a friend sends an iCloud share link (WhatsApp, Messages…). Sharing is
  one-way; after accepting, the app prompts "Invite <name> back". "Who sees my rides" is Apple's
  participant list (remove anyone). Swipe a friend › "Stop seeing" leaves their share.
- **Phase 1 – shared rides:** chosen on the Start sheet ("Share with friends after the ride", default
  in Settings) or later from ride detail. Friends see the route, stats, stops (as a trail), soundtrack
  and **only the photos the rider picks** (2048 px JPEG copies; videos as a still frame). Every stop
  has **Add to my wishlist** / Open in Google Maps; a **Friends' spots** map shows all their named stops.
- **Phase 2 – live:** "Let friends follow live" on the Start sheet. About one update a minute (or
  every km), only the latest is sent; friends see the road so far, the last position and a calm status
  (Live / Stopped / Last update 5 min ago / No signal since 14:02 — common on remote roads). No live
  speed. Ends at End, after 12 h, or after a crash (never resumed automatically). A passive "Live" chip
  on the riding screen and Live Activity; nothing else social while riding.
- **Privacy:** the first and last **500 m** of every shared ride are cut (Settings toggle, on by
  default), and **privacy zones** (Settings › Friends, 500 m, "Add current location") hide route,
  stops, photos and live position. No comments or likes in v1 (no moderation burden).
- **Data:** zone "Friends" in the private DB, shared zone-wide. Records: `SharedRide` (JSON payload,
  redacted track asset, photo assets), `LiveRide` (JSON). Schema V3 adds `Ride.sharedWithFriends`,
  `Ride.sharedAt`, `MediaLink.sharedWithFriends`. Friends refresh on open and every 30 s while the tab
  is visible (no push yet).
- **Not done yet:** push updates for friends' rides (CloudKit database subscription), reactions,
  testing on two real devices (needs the paid Developer Program, two Apple IDs).
- **Phase 3 – group rides (planned):** one live map for the whole group and a shared album for the
  ride. This is where it could become the app a riding group uses together.

### Next (planned)
- **Trips** (next to build; decided 2026-10-13):
  - A trip groups rides, for example "Ladakh 2026": combined map with each day in its own colour,
    Day 1…N with rest days, total km, all spots, photos and soundtrack. The photo trail becomes the
    trip's day-by-day story.
  - **Active trip:** start a trip once; every ride started afterwards (including from the Action
    button and Siri) joins it until the trip is ended. Rides can be added to or removed from a trip
    afterwards, or a trip made from selected rides.
  - **Photos:** each trip is a folder, `Ride Tracker / Ladakh 2026 / <ride albums>`. Adding or removing
    a ride moves its album; deleting a trip moves albums back and never deletes photos.
  - **Naming:** an empty ride name inside a trip defaults to *"Ladakh 2026 · Day 4"* (also the album
    name). Outside a trip it stays *"Ride · 12 Oct 2026"*.
  - **Not in the first cut:** photos from rest days (no ride, so no album).
  - Build order: RideKit `TripDays` / `TripSummary` / naming / auto-end suggestion → schema V3 (freeze
    V2 as nested copies, add `Trip` + `Ride.trip`, migration tests V2→V3 and V1→V3) → Photos folder
    nesting and moves → active-trip lifecycle → UI → v1.2.0 or v1.3.0.
- **Road character** (after Trips, field test first): surface (smooth / rough / broken) from the
  motion sensor when the phone is rigidly mounted, road shape (highway / twisties / ghat / city /
  off-road) from the GPS track, NH/SH names from sampled reverse geocoding if Apple's data has them.
  Shown after the ride only (map colour toggle, summary line), never as alerts. Start with a hidden
  debug logger on real rides to confirm the signal is usable.
- Rider ideas to weigh: km since last fuel on the Live Activity, "daylight left" (sunset computed on
  device), an evening queue for naming today's spots, a one-tap "Reached, safe" share, keeping the
  trail and map in sync while scrolling.
- **Home Screen widgets:** "Mark spot" and "Last spot".
- **Share a spot card:** an image with the photo, name, map snippet and Google Maps link.
- **Nearby wishlist alerts without a ride** (region monitoring, which needs "Always" location — opt-in).
- **Plan a route** through wishlist spots, and open it in Google Maps as a multi-stop link.
- Garage: multiple bikes, odometer, fuel log and service reminders.
- Lean angle (needs a rigid phone mount).

### Later / maybe
- Apple Watch "Mark spot" button.
- Auto-start a ride when connected to the bike's Bluetooth intercom.
- Import your existing Google Maps "Saved" places (from a Google Takeout file).

---

## 4. Architecture

```
┌──────────────────────────── SwiftUI Views ─────────────────────────────┐
│ RecordView   SpotsMapView   SpotDetailView   RideDetailView   PlacesView │
└──────┬──────────────┬──────────────────┬───────────────────────────────┘
       │              │ @Query           │
┌──────▼──────┐ ┌─────▼────────┐  ┌──────▼─────────┐
│ RideRecorder│ │ SpotService  │  │ MediaOrganizer │──▶ PhotoKit (PHAsset, albums)
└─┬───────────┘ │ (create,     │  │ (match by time │
  │             │  geocode,    │  │  + distance,   │
  │             │  link parse) │  │  observe lib)  │
  │             └─────┬────────┘  └──────┬─────────┘
  │                   └─────────┬────────┘
  │                      ┌──────▼──────┐
  ├─ LocationService     │  SwiftData  │◀──▶ CloudKit (private DB)
  ├─ TrackBuffer (disk)  └─────────────┘
  └─ LiveActivityController ◀── MarkSpotIntent (Lock Screen / Action button / Siri)
```

- **`SpotService`** creates spots from coordinates, reverse-geocodes them and looks up nearby
  landmarks (in the background, after saving), builds Google Maps URLs, parses pasted Google Maps
  links, and detects revisits.
- **`MediaOrganizer`** queries `PHAsset`s by creation-date window, matches them by distance or by
  stores links, and owns the **ride album lifecycle**: create on start, add live through
  `PHPhotoLibraryChangeObserver`, final sweep on end, 48 h late-arrival sweep, rename and delete.
- **`MarkSpotIntent`** is an `AppIntent` / `LiveActivityIntent`. It runs without opening the app, so
  it is used from the Lock Screen, the Action button and Siri.

### Google Maps URL

```swift
// Official cross-platform Maps URL — no API key
func googleMapsURL(lat: Double, lon: Double) -> URL {
    URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)")!
}
```

Supported paste formats: `…/maps/search/?api=1&query=lat,lon`, `…/maps/@lat,lon,zoom`,
`…/place/…/data=…!3dLAT!4dLON`, `?q=lat,lon`, and `maps.app.goo.gl/…` (resolved through the HTTP
redirect first). We keep the URL exactly as pasted, plus a normalised coordinate URL.

### Data model (SwiftData, CloudKit-compatible: no `.unique`, everything optional or defaulted)

```swift
@Model final class Spot {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var category: String = "other"       // SpotCategory raw value
    var rating: Int?
    var status: String = "visited"      // wantToGo | visited
    var priority: Int?                    // wishlist only
    var bestSeason: String?               // wishlist only
    var latitude: Double = 0
    var longitude: Double = 0
    var altitude: Double?
    var address: String?                  // reverse-geocoded
    var locality: String?                 // city/area, used by the "Places" view
    var googleMapsURL: String = ""        // normalised coordinate URL
    var sourceURL: String?                // original pasted Google Maps link, if any
    var createdAt: Date = Date.now
    var visits: [Date] = []
    var ride: Ride?
    @Relationship(deleteRule: .cascade, inverse: \MediaLink.spot) var media: [MediaLink]? = []
}

@Model final class MediaLink {           // a reference to a Photos item, never a copy
    var id: UUID = UUID()
    var localIdentifier: String = ""      // PHAsset id on this device
    var cloudIdentifier: String?          // PHCloudIdentifier — stable across devices
    var mediaType: String = "photo"       // photo | video | livePhoto
    var capturedAt: Date = Date.now
    var latitude: Double?
    var longitude: Double?
    var locationSource: String = "exif"   // exif | manual | none
    var isManual: Bool = false            // the user placed it; auto-matching won't move it
    var spot: Spot?
    var ride: Ride?
}

@Model final class Ride {
    var id: UUID = UUID()
    var title: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date = Date.now
    var distanceMeters: Double = 0
    var movingSeconds: Double = 0
    var maxSpeedMps: Double = 0
    var avgMovingSpeedMps: Double = 0
    @Attribute(.externalStorage) var trackData: Data?   // compressed points, one blob
    var albumLocalIdentifier: String?     // the ride's PHAssetCollection in Photos
    var albumSweepUntil: Date?            // endedAt + 48 h: late-arrival sweep window
    @Relationship(deleteRule: .nullify, inverse: \Spot.ride) var spots: [Spot]? = []
    @Relationship(deleteRule: .nullify, inverse: \MediaLink.ride) var media: [MediaLink]? = []
}
```

**Cross-device photos:** a `PHAsset.localIdentifier` is different on each device. We also store the
`PHCloudIdentifier` and map it back on the other device
(`PHPhotoLibrary.localIdentifierMappings(for:)`). This means that with iCloud Photos enabled, a spot's
photos also appear on your iPad.

**Schema versions:** v1.0.0 is `RideTrackerSchemaV1` (frozen as nested copies of its models).
v1.1.0 is `RideTrackerSchemaV2`, which adds `PlayedSong` (title, artist, album, Apple Music ID, start
time, seconds listened, where it started) and `Ride.songs`, with a lightweight migration from V1.

---

## 5. Permissions and Info.plist

| Permission | Purpose string (draft) | Notes |
|---|---|---|
| Location — When In Use | "Ride Tracker uses your location to record your route and save the spots you mark while riding." | Plus the background mode "Location updates" |
| Photos — **Full access** | "Ride Tracker reads the location and time of your photos and videos to organise them by the spots and rides where you took them." | With *Limited* access, auto-matching only sees the selected items. The UI explains this and still works. |
| Apple Music | "Ride Tracker keeps a list of the songs you play in the Music app during a ride, so you can see and replay each ride's soundtrack." | v1.1.0. Asked at the first ride start; can be turned off in Settings |
| Motion | — | Future (lean angle) |

Other requirements:
- `LSApplicationQueriesSchemes`: `comgooglemaps` (to open the Google Maps app).
- `NSSupportsLiveActivities = YES`.
- iCloud / CloudKit capability.
- `PrivacyInfo.xcprivacy`: precise location and photos are used on-device only, are not linked to
  identity, and are not used for tracking.

---

## 6. Hard parts and how we handle them

| Risk | Mitigation |
|---|---|
| **Marking a spot while riding is unsafe if it needs attention** | One tap from the Lock Screen, Action button or Siri. Save first, name later. A haptic and sound confirm the save. |
| **Photo missed by the album** (app killed mid-ride, or iCloud delivers it late) | The album is built from the capture-time window, not only from live events. The end-of-ride sweep, crash-recovery sweep and 48 h late-arrival sweep catch everything. |
| **Album operations need write access to Photos** | Ask for full read-write Photos access at the first ride start, not at app launch, with a clear explanation. With limited access, fall back to an in-app gallery only. |
| **Photos from before Start or after End** (you forgot to tap Start) | On the ride summary, offer "Add photos from the 30 min before / after?" and an "Adjust ride time window" option. |
| **Auto-visit false positives** (passing near a wishlist spot on a highway without stopping) | Require a stop (speed below 5 km/h for 2 min or more) within the radius, *or* a photo taken there. Always confirmable on the summary. |
| **Large libraries** (50k+ items) | Query only by date windows (`PHFetchOptions` predicate on `creationDate`), process in batches in the background, and never load full-size images for matching. |
| **Limited Photos access** | Detect it, explain what won't work, and offer `PHPicker` for manual adding. |
| **Pasted short links** (`maps.app.goo.gl`) | Follow the redirect with a `HEAD` request and parse the final URL. If no coordinates are found, ask the user to drop a pin. |
| **Background survival and battery** | `CLBackgroundActivitySession`, append-only disk buffer, 1 Hz UI updates, and field testing for battery % per hour. |
| **CloudKit schema is permanent once in production** | Finalise the models before release and use a `VersionedSchema` from day one. |
| **App Review** (background location, full Photos access) | Both are clearly core features. Write precise purpose strings and include a demo video in the review notes. |

---

## 7. Milestones

| # | Milestone | Outcome | Est. |
|---|---|---|---|
| 0 | **Setup** | Install Xcode, enroll in the Developer Program, create the project and capabilities, git repo | 1–2 days |
| 1 | **Spots** | Spot model, create from current location or map, geocoding and landmark suggestion, Google Maps URL (copy/share/open), link paste parser, spots map + list, revisit detection | 1.5 weeks |
| 2 | **Ride tracking** | LocationService, TrackBuffer, recorder, live screen, auto-pause, crash recovery, ride detail map | 1.5 weeks |
| 3 | **Mark spot while riding** | `MarkSpotIntent`, Live Activity with the button, Action button and Siri | 4–5 days |
| 4 | **Ride albums** | PhotoKit permission flow, album create on start, live add, end sweep, late-arrival sweep, rename and delete, screenshot filter | 1 week |
| 5 | **Wishlist** | Status, search to add, map colours and filters, auto-visit with a stop or photo rule, nearby alert while riding | 4–5 days |
| 6 | **Media by location** | Spot/ride matching by distance, galleries, video playback, manual fixes, Places view, GPX/KML export | 1.5 weeks |
| 7 | **Sync & polish** | iCloud sync on two devices (including cloud photo identifiers), onboarding, accessibility, dark mode, icon | 1 week |
| 8 | **Field testing** | TestFlight rides: spot accuracy, matching quality, battery | 1–2 weeks |
| 9 | **App Store submission** | Privacy policy, screenshots, App Privacy labels, review notes and video | 2–3 days |

Roughly **10–12 weeks** to submission for one developer.

**Status (2026-10-12):** milestones 0–6 are code-complete in v1.0.0 and checked on the simulator and
the owner's iPhone. Milestone 7's iCloud sync can't be tested until the paid Developer Program is
joined. Milestone 8 is happening on the owner's iPhone with the free Personal build instead of
TestFlight. Milestone 9 hasn't started.

---

## 8. Testing

- **Unit (Swift Testing):** Google Maps link parser (each URL format, plus malformed input), URL
  builder, distance matching, ride-window asset selection (pauses included, screenshots excluded,
  edge times), auto-visit rule, revisit detection, stats, the track codec. Target at least 80%
  coverage on `Spots/`, `Media/`, `Tracking/`.
- **Simulator:** GPX route playback, plus a seeded test photo library with known locations and times.
- **Device:** real rides. Mark spots from the Lock Screen, take photos at the spots and check they
  attach correctly, and confirm every photo and video from the ride is in its Photos album, including
  ones taken with the phone locked and from other camera apps. Then force-quit mid-ride and check recovery.
- **Migrations:** every schema version needs a test that writes a store with the previous version
  and opens it with the new one (`RideTrackerTests/MigrationTests.swift`).
- **Sync:** two devices on the same Apple ID with iCloud Photos on. Check that spots and their photos
  appear on both.

---

## 9. Prerequisites (action needed from you)

- [x] **Xcode 26** installed (26.6, with the iOS 26.5 simulator). Still to do once:
      `sudo xcode-select -s /Applications/Xcode.app`.
- [x] App name and bundle ID: **Ride Tracker**, `com.hatchedland.ridetracker`.
- [x] An iPhone for testing (iPhone 16, free Personal Team build).
- [ ] **Apple Developer Program** ($99/yr). Needed for iCloud sync, **Friends**, TestFlight and the App Store.
- [ ] A privacy policy URL before submission.
- [ ] A phone mount and a few real rides for testing.

---

## 10. Settled

- Spot radius for attaching photos and auto-visit: **150 m** (adjustable in Settings).
- Rides are **named by you when starting**, and the Photos album uses the same name.
- No GoPro or action-camera support. The wishlist is in v1. Albums are created automatically for every ride.
- Testing happens on the owner's iPhone with a **free Apple ID** (Personal build, no iCloud). There's
  no TestFlight or other testers for now.
- Shared photos and videos are the **original files**, sent through the system share sheet.
- The ride soundtrack covers the **Music app only**, songs count after 30 s, and it's on by default.
- The app is **for motorcycles and scooters only**: no car mode or vehicle type (decided 2026-10-13).
- **Friends** via CloudKit sharing, no backend; chosen photos are copied for friends (the only
  exception to "reference, never copy"); live sharing in the first Friends release (decided 2026-10-15).
- Ride photos are shown as a **trail** by default; unnamed photo stops are **suggested, never
  auto-saved** as spots; photos without GPS are placed in the trail by time but stay off the map.

## 11. Open questions

1. Do you want to import your existing **Google Maps saved places** into the wishlist (from a Google Takeout file)?
2. **App Store name.** "Ride Tracker" describes the app rather than naming it. Checked on the India
   App Store (2026-10-13): **KM Stone** (free, recommended, subtitle e.g. "Ride spots & road
   journal"), **Ghumakkad** (free, most character, harder to spell outside India), "Milestone"
   (crowded and unrelated, risky to trademark; fine as the internal design-system name), "Safarnama"
   and "Meel" (taken).
3. Version for the brand + trail release: **v1.2.0** (with Trips in v1.3.0) or hold the bump until
   Trips ships?

## 12. Brand: Milestone

The Indian highway kilometre stone: a slab with a half-round coloured cap. Every rider in India knows
it, and the cap colour already encodes road type (yellow NH, green SH, …).

| Token (`Shared/Brand.swift`) | Value | Use |
|---|---|---|
| `highwayYellow` | `#F5C400` | **Fills only**, always with asphalt text on it (10.6:1). Never text on white (1.6:1). Wishlist spots, Start / Mark spot buttons, route line while riding, trail road |
| `asphalt` | `#1B1A17` | Riding screen background, text on yellow, visited spots |
| `chalk` | `#F6F3EA` | The stone's body, light surfaces |
| `accent` | `#8A6100` light / `#F5C400` dark | Tinted text and controls (5.5:1 on white); also the `AccentColor` asset |
| `signal` | `#C22E22` light / `#FF5A4A` dark | Recording, End and problems only |

- **Type:** big numbers in SF Pro **expanded** width (signboard feel, `Brand.readout`, `Brand.stat`,
  `Brand.label`); everything else is the system font. No custom font files.
- **Two modes:** while riding the screen is an always-dark instrument cluster (yellow on asphalt);
  after the ride it's a journal (light, milestone markers, photos first).
- **Status chips:** counters are quiet asphalt chips; only state that needs attention gets colour.
- **Speed colours** on the ride map are data, not brand, and keep their ramp.
- **Icon:** a km-stone with a yellow cap and a map pin cut into it, beside a road with a dashed yellow
  centre line. Rendered by `design/make-icon.swift`.
- **Voice (to do):** short and warm like road signs, e.g. "Saved. Name it at the chai stop."
