// What friends may see of a ride. A line-for-line port of RideKit's SharePrivacy and
// SharedRide.redacted (Packages/RideKit/Sources/RideKit/Social), checked against the same golden files
// (spec/fixtures/share-privacy.json, shared-ride-redaction.json). Since 2026-11-18 this server copy is
// the one that decides what friends see; the apps only send the ride.
//
// Plain TypeScript with no runtime-specific APIs, so it runs in Deno (Edge Functions) and Node (tests).

export interface Coordinate {
  latitude: number;
  longitude: number;
}

export interface TrackPoint {
  /** Unix seconds. */
  t: number;
  coordinate: Coordinate;
  altitude: number | null;
  speed: number | null;
  course: number | null;
  horizontalAccuracy: number;
  lean: number | null;
}

export interface PrivacyZone {
  center: Coordinate;
  /** Meters. */
  radius: number;
}

export interface SharePrivacy {
  zones: PrivacyZone[];
  /** Meters cut from each end of a shared track. 0 turns it off. */
  endTrim: number;
}

export const defaultEndTrim = 500;
const earthRadius = 6_371_008.8;

/** Great-circle distance in meters (haversine), exactly as RideKit's Coordinate.distance. */
export function distance(a: Coordinate, b: Coordinate): number {
  const lat1 = (a.latitude * Math.PI) / 180;
  const lat2 = (b.latitude * Math.PI) / 180;
  const dLat = lat2 - lat1;
  const dLon = ((b.longitude - a.longitude) * Math.PI) / 180;
  const h = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return 2 * earthRadius * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/** `true` if a coordinate lies in any privacy zone. */
export function hides(privacy: SharePrivacy, c: Coordinate): boolean {
  return privacy.zones.some((z) => distance(z.center, c) <= z.radius);
}

/** The part of the track friends may see. */
export function redactTrack(privacy: SharePrivacy, track: TrackPoint[]): TrackPoint[] {
  const visible = track.filter((p) => !hides(privacy, p.coordinate));
  const endTrim = Math.max(0, privacy.endTrim);
  if (endTrim <= 0 || visible.length <= 1) return visible;

  const cumulative = [0];
  for (let i = 1; i < visible.length; i++) {
    cumulative.push(cumulative[i - 1] + distance(visible[i - 1].coordinate, visible[i].coordinate));
  }
  const total = cumulative[cumulative.length - 1];
  if (!(total > endTrim * 2)) return [];
  return visible.filter((_, i) => cumulative[i] >= endTrim && cumulative[i] <= total - endTrim);
}

/** `true` if a point of the ride may be shown: outside every zone and not near the ride's ends. */
export function shows(privacy: SharePrivacy, c: Coordinate, track: TrackPoint[]): boolean {
  if (hides(privacy, c)) return false;
  const endTrim = Math.max(0, privacy.endTrim);
  if (endTrim <= 0) return true;
  const ends = track.length ? [track[0].coordinate, track[track.length - 1].coordinate] : [];
  return ends.every((e) => distance(e, c) > endTrim);
}

export interface SharedStop {
  id: string;
  coordinate: Coordinate;
  photoIDs: string[];
  [key: string]: unknown;
}

export interface SharedPhoto {
  id: string;
  coordinate?: Coordinate | null;
  [key: string]: unknown;
}

/**
 * Removes what `privacy` doesn't allow: stops near home or the ride's ends, every photo taken at
 * such a stop, and photo locations there. Other fields pass through untouched.
 */
export function redactRide<S extends SharedStop, P extends SharedPhoto>(
  privacy: SharePrivacy,
  track: TrackPoint[],
  stops: S[],
  photos: P[],
): { stops: S[]; photos: P[] } {
  const hiddenStops = stops.filter((s) => !shows(privacy, s.coordinate, track));
  const hiddenPhotoIDs = new Set(hiddenStops.flatMap((s) => s.photoIDs));
  const keptStops = stops.filter((s) => shows(privacy, s.coordinate, track));
  const keptPhotos = photos
    .filter((p) => !hiddenPhotoIDs.has(p.id))
    .map((p) => (p.coordinate && !shows(privacy, p.coordinate, track) ? { ...p, coordinate: null } : p));
  return { stops: keptStops, photos: keptPhotos };
}
