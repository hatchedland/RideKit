# Track file format (TrackCodec)

One file per ride: on the phone (SwiftData / Room blob), in Storage (`tracks/<user>/<ride>.track`,
`shared/<user>/<ride>/track`). iOS: `Packages/RideKit/Sources/RideKit/Tracking/TrackCodec.swift`.
Android must produce and read byte-compatible files. The golden file is `fixtures/track-v2.bin`,
with its expected values in `fixtures/track-v2.json`; both apps' tests decode it.

## Version 2 (current, written since 2026-11-18)

All integers and floats little-endian.

| Offset | Size | Field |
|---|---|---|
| 0 | 3 | ASCII `RTK` |
| 3 | 1 | version = `0x02` |
| 4 | 4 | point count, UInt32 |
| 8 | … | **raw DEFLATE** (RFC 1951, no zlib/gzip header) of `count × 44` bytes; absent when count = 0 |

Each 44-byte point:

| Size | Field | Unknown |
|---|---|---|
| Float64 | time, **Unix seconds** (fractional) | never |
| Float64 | latitude, degrees | never |
| Float64 | longitude, degrees | never |
| Float32 | altitude, m | NaN |
| Float32 | speed, m/s | NaN |
| Float32 | course, degrees from true north | NaN |
| Float32 | horizontal accuracy, m | never |
| Float32 | lean, degrees (negative = left) | NaN |

- Android: `java.util.zip.Deflater(level, nowrap = true)` / `Inflater(nowrap = true)`.
- Apple: `NSData.compressed(using: .zlib)` (which is raw DEFLATE despite its name).
- Compressed bytes may differ between encoders; only the decoded points must match.

## Version 1 (read-only, iOS only)

Same header and points, but time counts from **2001-01-01 UTC** and the whole file (header
included) is **LZFSE**-compressed, so it doesn't start with `RTK`. iOS upgrades v1 blobs to v2
before uploading (`TrackCodec.upgraded`), so Storage only ever holds v2 once every iPhone has
synced. Android doesn't read v1 and shows "Track needs your iPhone to sync once" if it meets one.
