# Shared golden fixtures

The behaviour both apps must agree on, as data. The Swift RideKit (`Packages/RideKit`) and the
Kotlin `ridekit` module load the same files here and must produce the same `expected` values.
If the platforms disagree, the app is wrong — not the rider.

| File | Swift source | What it checks |
|---|---|---|
| `track-v2.bin` + `track-v2.json` | `Tracking/TrackCodec.swift` | Track file decoding ([format](../track-codec.md)) |
| `share-privacy.json` | `Social/SharePrivacy.swift` | Privacy zones, 500 m end trim, `shows` for photos |
| `wishlist.json` | `Spots/WishlistMatcher.swift`, `Spots/StopDetector.swift` | Auto-visit (stop ≥ 2 min or photo ≤ 150 m), 2 km nearby alert, 100 m revisit |
| `ride-time-plan.json` | `Rides/RideTimePlan.swift`, `Weather/WeatherAlerts.swift` (`Sun`) | Rider's pace, honest arrival time, sunset, leave-by |
| `weather-alerts.json` | `Weather/WeatherAlerts.swift`, `Weather/GoogleWeather.swift` (`WeatherHour`) | Alert priority, start-only rain, hourly / 15-min limits, sunset, outlook |
| `famous-places.json` | `Spots/FamousPlaces.swift` | ≥ 500 reviews & ≥ 4.0, 2 km, not behind, nearest 3, heading, search spacing |
| `trail.json` | `Media/Trail.swift` | Stops, photo clusters, photos without GPS, legs, songs |
| `ride-naming.json` | `Rides/RideNaming.swift` | Default names, de-duplication, suggestions |

## File shape

```json
{ "about": "what is being tested",
  "cases": [ { "name": "…", "input": { … }, "expected": { … } } ] }
```

Each file's `about` and the Swift test (`Packages/RideKit/Tests/RideKitTests/SharedFixtures.swift`)
say exactly which functions run on `input`. Conventions:

- **Times** are Unix seconds (Double). **Distances** are meters. **Coordinates** are `{"lat", "lon"}`.
- **Track points** are arrays: `[t, lat, lon, alt, speed, course, hAcc, lean]`, `null` when unknown.
- **A missing key means `null`** (Swift leaves `nil` values out).
- Spot ids are uppercase UUID strings; compare them as strings.
- Calls run in order where a case has `steps` (weather alerts share one state across them).

## Comparing on Android

Same algorithm, same constants, but floating-point maths can differ in the last bits between
platforms. Compare:

- distances (meters): ± 0.01
- durations and times (seconds): ± 0.001, except **sunset and anything derived from it: ± 1**
- headings (degrees): ± 0.0001
- everything else (ids, indices, booleans, strings, ints, counts, order): exactly

Inputs keep a margin from every threshold (no point sits on the 500 m trim edge, etc.), so these
tolerances never flip a decision. Keep it that way when adding cases.

## Changing behaviour

1. Change the Swift code and its normal tests.
2. Add or edit the case in `SharedFixtures.swift`, then regenerate:
   `RIDEKIT_WRITE_FIXTURES=1 ./scripts/test.sh --filter "SharedFixture|TrackCodecFixture"`
3. Read the diff of the JSON: every changed `expected` value must be a change you meant.
4. Make the Kotlin port pass the new files in the same PR.
