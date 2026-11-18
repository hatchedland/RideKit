// Checks the server's privacy and track code against the golden files RideKit generates.
// Run: node --test supabase/functions/_shared/   (or ./scripts/test-functions.sh)

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { hides, redactRide, redactTrack, shows, type SharePrivacy, type TrackPoint } from "./privacy.ts";
import { decodeTrack, encodeTrack, TrackFormatError } from "./track-codec.ts";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "../../../spec/fixtures");
const load = (name: string) => JSON.parse(readFileSync(join(fixtures, name), "utf8"));

type LatLon = { lat: number; lon: number };
const coord = (c: LatLon) => ({ latitude: c.lat, longitude: c.lon });
const point = (a: (number | null)[]): TrackPoint => ({
  t: a[0]!, coordinate: { latitude: a[1]!, longitude: a[2]! },
  altitude: a[3], speed: a[4], course: a[5], horizontalAccuracy: a[6]!, lean: a[7],
});
const privacyOf = (input: { zones: { center: LatLon; radius: number }[]; endTrim: number }): SharePrivacy => ({
  zones: input.zones.map((z) => ({ center: coord(z.center), radius: z.radius })),
  endTrim: input.endTrim,
});

for (const c of load("share-privacy.json").cases) {
  test(`share-privacy: ${c.name}`, () => {
    const privacy = privacyOf(c.input);
    const track: TrackPoint[] = c.input.track.map(point);
    const kept = redactTrack(privacy, track);
    assert.deepEqual(kept.map((p) => track.indexOf(p)), c.expected.visible);
    assert.deepEqual(c.input.probes.map((p: LatLon) => shows(privacy, coord(p), track)), c.expected.shows);
  });
}

for (const c of load("shared-ride-redaction.json").cases) {
  test(`shared-ride-redaction: ${c.name}`, () => {
    const privacy = privacyOf(c.input);
    const track: TrackPoint[] = c.input.track.map(point);
    const result = redactRide(
      privacy,
      track,
      c.input.stops.map((s: { id: string; at: LatLon; photoIDs: string[] }) => ({ id: s.id, coordinate: coord(s.at), photoIDs: s.photoIDs })),
      c.input.photos.map((p: { id: string; at?: LatLon }) => ({ id: p.id, coordinate: p.at ? coord(p.at) : null })),
    );
    assert.deepEqual(result.stops.map((s) => s.id), c.expected.stops);
    assert.deepEqual(
      result.photos.map((p) => ({ id: p.id, at: p.coordinate ? { lat: p.coordinate.latitude, lon: p.coordinate.longitude } : undefined })),
      c.expected.photos.map((p: { id: string; at?: LatLon }) => ({ id: p.id, at: p.at })),
    );
  });
}

test("track v2 golden file decodes", async () => {
  const expected = load("track-v2.json").points;
  const points = await decodeTrack(new Uint8Array(readFileSync(join(fixtures, "track-v2.bin"))));
  assert.equal(points.length, expected.length);
  points.forEach((p, i) => {
    const e = expected[i];
    const f32 = (v: number | null) => (v === null ? null : Math.fround(v));
    assert.equal(p.t, e.t);
    assert.equal(p.coordinate.latitude, e.lat);
    assert.equal(p.coordinate.longitude, e.lon);
    assert.equal(p.altitude, f32(e.alt));
    assert.equal(p.speed, f32(e.speed));
    assert.equal(p.course, f32(e.course));
    assert.equal(p.horizontalAccuracy, f32(e.hAcc));
    assert.equal(p.lean, f32(e.lean));
  });
});

test("track v2 round-trips, empty included", async () => {
  const points = (await decodeTrack(new Uint8Array(readFileSync(join(fixtures, "track-v2.bin")))));
  assert.deepEqual(await decodeTrack(await encodeTrack(points)), points);
  assert.deepEqual(await decodeTrack(await encodeTrack([])), []);
});

test("old LZFSE tracks are refused with a clear code", async () => {
  await assert.rejects(decodeTrack(new Uint8Array([0x62, 0x76, 0x78, 0x32, 0, 0, 0, 0])), (e: unknown) =>
    e instanceof TrackFormatError && e.code === "legacy");
});

test("zones use the same radius rule as the app", () => {
  const privacy: SharePrivacy = { zones: [{ center: { latitude: 12.97, longitude: 77.59 }, radius: 100 }], endTrim: 0 };
  assert.equal(hides(privacy, { latitude: 12.97, longitude: 77.59 }), true);
  assert.equal(hides(privacy, { latitude: 12.972, longitude: 77.59 }), false);
});
