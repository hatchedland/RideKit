// TrackCodec v2 (spec/track-codec.md): "RTK" + 0x02 + count(UInt32 LE), then raw DEFLATE of 44-byte
// points. Uses only web-standard APIs (CompressionStream), so it runs in Deno and Node.

import type { TrackPoint } from "./privacy.ts";

const bytesPerPoint = 44;
const headerSize = 8;

export type TrackFormatCode = "legacy" | "bad_header" | "unsupported_version" | "truncated";

export class TrackFormatError extends Error {
  code: TrackFormatCode;
  constructor(code: TrackFormatCode, message: string) {
    super(message);
    this.code = code;
  }
}

async function pipe(data: Uint8Array, stream: CompressionStream | DecompressionStream): Promise<Uint8Array> {
  const out = new Response(new Blob([data]).stream().pipeThrough(stream));
  return new Uint8Array(await out.arrayBuffer());
}

const nanToNull = (v: number): number | null => (Number.isNaN(v) ? null : v);

export async function decodeTrack(data: Uint8Array): Promise<TrackPoint[]> {
  if (data.length < 4 || data[0] !== 0x52 || data[1] !== 0x54 || data[2] !== 0x4b) {
    // Not "RTK": a v1 (LZFSE) blob that the iPhone hasn't upgraded yet.
    throw new TrackFormatError("legacy", "Track is in the old format; the iPhone upgrades it on its next sync.");
  }
  if (data[3] !== 2) throw new TrackFormatError("unsupported_version", `Unsupported track version ${data[3]}`);
  if (data.length < headerSize) throw new TrackFormatError("bad_header", "Track header is cut short");
  const count = new DataView(data.buffer, data.byteOffset, data.byteLength).getUint32(4, true);
  if (count === 0) return [];

  let body: Uint8Array;
  try {
    body = await pipe(data.subarray(headerSize), new DecompressionStream("deflate-raw"));
  } catch {
    throw new TrackFormatError("truncated", "Track data is damaged");
  }
  if (body.length < count * bytesPerPoint) throw new TrackFormatError("truncated", "Track data is cut short");

  const view = new DataView(body.buffer, body.byteOffset, body.byteLength);
  const points: TrackPoint[] = [];
  for (let i = 0; i < count; i++) {
    const o = i * bytesPerPoint;
    points.push({
      t: view.getFloat64(o, true),
      coordinate: { latitude: view.getFloat64(o + 8, true), longitude: view.getFloat64(o + 16, true) },
      altitude: nanToNull(view.getFloat32(o + 24, true)),
      speed: nanToNull(view.getFloat32(o + 28, true)),
      course: nanToNull(view.getFloat32(o + 32, true)),
      horizontalAccuracy: view.getFloat32(o + 36, true),
      lean: nanToNull(view.getFloat32(o + 40, true)),
    });
  }
  return points;
}

export async function encodeTrack(points: TrackPoint[]): Promise<Uint8Array> {
  const header = new Uint8Array(headerSize);
  header.set([0x52, 0x54, 0x4b, 2]);
  new DataView(header.buffer).setUint32(4, points.length, true);
  if (points.length === 0) return header;

  const body = new Uint8Array(points.length * bytesPerPoint);
  const view = new DataView(body.buffer);
  points.forEach((p, i) => {
    const o = i * bytesPerPoint;
    view.setFloat64(o, p.t, true);
    view.setFloat64(o + 8, p.coordinate.latitude, true);
    view.setFloat64(o + 16, p.coordinate.longitude, true);
    view.setFloat32(o + 24, p.altitude ?? NaN, true);
    view.setFloat32(o + 28, p.speed ?? NaN, true);
    view.setFloat32(o + 32, p.course ?? NaN, true);
    view.setFloat32(o + 36, p.horizontalAccuracy, true);
    view.setFloat32(o + 40, p.lean ?? NaN, true);
  });
  const compressed = await pipe(body, new CompressionStream("deflate-raw"));
  const out = new Uint8Array(headerSize + compressed.length);
  out.set(header);
  out.set(compressed, headerSize);
  return out;
}
