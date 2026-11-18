// Publishes a ride for friends. The app sends the ride as it sees it (stats, stops, songs, the photos
// it picked, already uploaded to its private outbox tracks/<owner>/outbox/<ride>/<id>.jpg, which friends
// can't read); this function reads the full
// track from the owner's Storage, the owner's privacy zones and "hide ride ends" setting from the
// database, and writes what friends may see: the trimmed track, the shared_rides row, the allowed
// photos (moved out of the outbox) and their shared_media rows. One implementation for iOS and Android (decided 2026-11-18).
//
// POST { ride: SharedRide JSON (dates ISO 8601, as PostgREST rows) }  with the rider's access token.
// 200 { photos: [id…], trackPoints: n }   409 { code: "track_not_synced" | "track_needs_sync" }

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.119.0";
import { type Coordinate, defaultEndTrim, redactRide, redactTrack, type SharePrivacy } from "../_shared/privacy.ts";
import { decodeTrack, encodeTrack, TrackFormatError } from "../_shared/track-codec.ts";

interface Stop {
  id: string;
  coordinate: Coordinate;
  photoIDs: string[];
  [key: string]: unknown;
}

interface Photo {
  id: string;
  capturedAt: string;
  coordinate?: Coordinate | null;
  isVideo?: boolean;
  [key: string]: unknown;
}

interface RideBody {
  id: string;
  name: string;
  startedAt: string;
  endedAt: string;
  distanceMeters: number;
  movingSeconds: number;
  maxSpeedMps: number;
  avgMovingSpeedMps: number;
  elevationGainMeters: number;
  stops: Stop[];
  songs: unknown[];
  photos: Photo[];
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function isCoordinate(c: unknown): c is Coordinate {
  const v = c as Coordinate;
  return !!v && Number.isFinite(v.latitude) && Number.isFinite(v.longitude) &&
    Math.abs(v.latitude) <= 90 && Math.abs(v.longitude) <= 180;
}

/** Rejects anything the rest of the function would trust. */
function parseRide(input: unknown): RideBody | string {
  const r = input as RideBody;
  if (!r || typeof r !== "object") return "ride is missing";
  if (typeof r.id !== "string" || !uuid.test(r.id)) return "ride.id must be a UUID";
  if (typeof r.name !== "string") return "ride.name must be text";
  for (const key of ["startedAt", "endedAt"] as const) {
    if (typeof r[key] !== "string" || Number.isNaN(Date.parse(r[key]))) return `ride.${key} must be a date`;
  }
  for (const key of ["distanceMeters", "movingSeconds", "maxSpeedMps", "avgMovingSpeedMps", "elevationGainMeters"] as const) {
    if (!Number.isFinite(r[key])) return `ride.${key} must be a number`;
  }
  if (!Array.isArray(r.stops) || !Array.isArray(r.songs) || !Array.isArray(r.photos)) return "stops, songs and photos must be lists";
  for (const s of r.stops) {
    if (typeof s?.id !== "string" || !isCoordinate(s.coordinate) || !Array.isArray(s.photoIDs)) return "a stop is malformed";
  }
  for (const p of r.photos) {
    if (typeof p?.id !== "string" || !uuid.test(p.id) || Number.isNaN(Date.parse(p.capturedAt))) return "a photo is malformed";
    if (p.coordinate != null && !isCoordinate(p.coordinate)) return "a photo location is malformed";
  }
  return r;
}

async function privacyFor(admin: SupabaseClient, owner: string): Promise<SharePrivacy> {
  const [zones, profile] = await Promise.all([
    admin.from("privacy_zones").select("latitude, longitude, radius_meters").eq("user_id", owner),
    admin.from("profiles").select("hide_ride_ends").eq("id", owner).maybeSingle(),
  ]);
  if (zones.error) throw zones.error;
  if (profile.error) throw profile.error;
  return {
    zones: (zones.data ?? []).map((z) => ({ center: { latitude: z.latitude, longitude: z.longitude }, radius: z.radius_meters })),
    // Missing profile or setting: the safe default, ends hidden.
    endTrim: profile.data?.hide_ride_ends === false ? 0 : defaultEndTrim,
  };
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply(405, { error: "Use POST", code: "method_not_allowed" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  // Who is asking: validated with the auth server, not just decoded.
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const { data: auth, error: authError } = await admin.auth.getUser(token);
  if (authError || !auth.user) return reply(401, { error: "Sign in again", code: "unauthenticated" });
  const owner = auth.user.id.toLowerCase();

  let body: { ride?: unknown };
  try {
    body = await request.json();
  } catch {
    return reply(400, { error: "Body must be JSON", code: "bad_request" });
  }
  const parsed = parseRide(body.ride);
  if (typeof parsed === "string") return reply(422, { error: parsed, code: "invalid_ride" });
  const ride = parsed;
  const rideID = ride.id.toLowerCase();

  try {
    // Only the rider's own, synced, not-deleted ride.
    const { data: row, error: rowError } = await admin.from("rides")
      .select("id, track_path, deleted_at").eq("id", rideID).eq("user_id", owner).maybeSingle();
    if (rowError) throw rowError;
    if (!row || row.deleted_at) return reply(404, { error: "Ride not found in your account", code: "ride_not_found" });
    if (!row.track_path) return reply(409, { error: "The ride's track hasn't synced yet", code: "track_not_synced" });

    const file = await admin.storage.from("tracks").download(`${owner}/${rideID}.track`);
    if (file.error || !file.data) return reply(409, { error: "The ride's track hasn't synced yet", code: "track_not_synced" });
    const fullTrack = await decodeTrack(new Uint8Array(await file.data.arrayBuffer()));

    const privacy = await privacyFor(admin, owner);
    const track = redactTrack(privacy, fullTrack);
    const { stops, photos } = redactRide(privacy, fullTrack, ride.stops, ride.photos);

    const folder = `${owner}/${rideID}`;
    const upload = await admin.storage.from("shared").upload(`${folder}/track`, await encodeTrack(track), {
      contentType: "application/octet-stream",
      upsert: true,
    });
    if (upload.error) throw upload.error;

    const { error: rideError } = await admin.from("shared_rides").upsert({
      ride_id: rideID,
      owner_id: owner,
      name: ride.name.slice(0, 200),
      started_at: ride.startedAt,
      ended_at: ride.endedAt,
      distance_meters: ride.distanceMeters,
      moving_seconds: ride.movingSeconds,
      max_speed_mps: ride.maxSpeedMps,
      avg_moving_speed_mps: ride.avgMovingSpeedMps,
      elevation_gain_meters: ride.elevationGainMeters,
      track_path: `${folder}/track`,
      stops,
      songs: ride.songs,
    }, { onConflict: "ride_id" });
    if (rideError) throw rideError;

    // Photos: the allowed ones that reached the outbox replace whatever friends saw before.
    const outbox = `${owner}/outbox/${rideID}`;
    const fileName = (id: string) => `${id.toLowerCase()}.jpg`;
    const listed = await admin.storage.from("tracks").list(outbox, { limit: 1000 });
    if (listed.error) throw listed.error;
    const inOutbox = new Set((listed.data ?? []).map((f) => f.name));
    const kept = photos.filter((p) => inOutbox.has(fileName(p.id)));

    const { error: clearError } = await admin.from("shared_media").delete().eq("ride_id", rideID);
    if (clearError) throw clearError;
    const previous = await admin.storage.from("shared").list(`${folder}/photos`, { limit: 1000 });
    if (previous.error) throw previous.error;
    if (previous.data?.length) {
      const removed = await admin.storage.from("shared").remove(previous.data.map((f) => `${folder}/photos/${f.name}`));
      if (removed.error) throw removed.error;
    }
    for (const p of kept) {
      const moved = await admin.storage.from("tracks").move(`${outbox}/${fileName(p.id)}`, `${folder}/photos/${fileName(p.id)}`,
        { destinationBucket: "shared" });
      if (moved.error) throw moved.error;
    }
    if (kept.length) {
      const { error: mediaError } = await admin.from("shared_media").insert(kept.map((p) => ({
        id: p.id.toLowerCase(),
        ride_id: rideID,
        owner_id: owner,
        photo_path: `${folder}/photos/${fileName(p.id)}`,
        captured_at: p.capturedAt,
        latitude: p.coordinate?.latitude ?? null,
        longitude: p.coordinate?.longitude ?? null,
        stop_id: stops.find((s) => s.photoIDs.includes(p.id))?.id ?? null,
        is_video: p.isVideo === true,
      })));
      if (mediaError) throw mediaError;
    }
    // Whatever wasn't allowed (a photo at home) never leaves the outbox; clear it.
    const leftovers = [...inOutbox].filter((name) => !kept.some((p) => fileName(p.id) === name)).map((n) => `${outbox}/${n}`);
    if (leftovers.length) {
      const removed = await admin.storage.from("tracks").remove(leftovers);
      if (removed.error) console.error("publish-shared-ride: outbox not cleared", removed.error.message);
    }

    return reply(200, { photos: kept.map((p) => p.id), trackPoints: track.length });
  } catch (error) {
    if (error instanceof TrackFormatError && error.code === "legacy") {
      return reply(409, { error: error.message, code: "track_needs_sync" });
    }
    console.error("publish-shared-ride failed", error instanceof Error ? error.message : error);
    return reply(500, { error: "Couldn't publish the ride", code: "internal" });
  }
});
