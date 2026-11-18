import Foundation

/// Compact binary encoding for a ride's track: one blob on the phone and one file in Storage.
///
/// **Version 2** (written since 2026-11-18; readable on iOS and Android, spec in `spec/track-codec.md`):
/// ```
/// header : "RTK" + 0x02 + count(UInt32)                  ← plain, not compressed
/// body   : raw DEFLATE (RFC 1951, no zlib/gzip wrapper) of `count` points:
/// point  : t(Float64, Unix seconds) lat(Float64) lon(Float64)
///          alt(Float32) speed(Float32) course(Float32) hAcc(Float32) lean(Float32)
/// ```
/// **Version 1** (read only): the same header and points, but `t` counts from 2001-01-01 and the
/// whole thing, header included, is LZFSE-compressed. Android can't read LZFSE, so iOS upgrades
/// v1 blobs before uploading them (`upgraded(_:)`).
///
/// Little-endian throughout. Unknown optional values are NaN. 44 bytes per point before compression.
public enum TrackCodec {
    static let magic: [UInt8] = Array("RTK".utf8)
    static let version: UInt8 = 2
    static let headerSize = 8
    static let bytesPerPoint = 8 * 3 + 4 * 5

    public enum DecodeError: Error, Equatable {
        case notCompressed
        case badHeader
        case unsupportedVersion(UInt8)
        case truncated
    }

    public static func encode(_ points: [TrackPoint]) throws -> Data {
        var body = Data(capacity: points.count * bytesPerPoint)
        for p in points {
            body.appendPoint(p, time: p.timestamp.timeIntervalSince1970)
        }
        var out = Data(capacity: headerSize + body.count / 2)
        out.append(contentsOf: magic)
        out.append(version)
        out.appendLE(UInt32(points.count))
        if !points.isEmpty {
            out.append(try (body as NSData).compressed(using: .zlib) as Data)
        }
        return out
    }

    public static func decode(_ data: Data) throws -> [TrackPoint] {
        if data.starts(with: magic) {
            var reader = ByteReader(data: data)
            _ = reader.bytes(3)
            guard let v = reader.bytes(1)?.first else { throw DecodeError.badHeader }
            guard v == version else { throw DecodeError.unsupportedVersion(v) }
            guard let count = reader.uint32() else { throw DecodeError.truncated }
            if count == 0 { return [] }
            let body: Data
            do {
                body = try (data.dropFirst(headerSize) as NSData).decompressed(using: .zlib) as Data
            } catch {
                throw DecodeError.truncated
            }
            var points = ByteReader(data: body)
            return try readPoints(&points, count: count) { Date(timeIntervalSince1970: $0) }
        }
        return try decodeV1(data)
    }

    /// True for a blob in the old LZFSE format (iOS only).
    public static func isLegacy(_ data: Data) -> Bool {
        !data.starts(with: magic)
    }

    /// Re-encodes a v1 blob as v2; `nil` when it's already current (or unreadable).
    public static func upgraded(_ data: Data) -> Data? {
        guard isLegacy(data), let points = try? decodeV1(data) else { return nil }
        return try? encode(points)
    }

    // MARK: Internals

    private static func decodeV1(_ data: Data) throws -> [TrackPoint] {
        let raw: Data
        do {
            raw = try (data as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw DecodeError.notCompressed
        }
        var reader = ByteReader(data: raw)
        guard let header = reader.bytes(3), header == magic else { throw DecodeError.badHeader }
        guard let v = reader.bytes(1)?.first else { throw DecodeError.badHeader }
        guard v == 1 else { throw DecodeError.unsupportedVersion(v) }
        guard let count = reader.uint32() else { throw DecodeError.truncated }
        return try readPoints(&reader, count: count) { Date(timeIntervalSinceReferenceDate: $0) }
    }

    private static func readPoints(_ reader: inout ByteReader, count: UInt32,
                                   date: (Double) -> Date) throws -> [TrackPoint] {
        var points: [TrackPoint] = []
        points.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let t = reader.double(), let lat = reader.double(), let lon = reader.double(),
                  let alt = reader.float(), let speed = reader.float(), let course = reader.float(),
                  let hAcc = reader.float(), let lean = reader.float()
            else { throw DecodeError.truncated }
            points.append(TrackPoint(
                timestamp: date(t),
                coordinate: Coordinate(latitude: lat, longitude: lon),
                altitude: alt.isNaN ? nil : Double(alt),
                speed: speed.isNaN ? nil : Double(speed),
                course: course.isNaN ? nil : Double(course),
                horizontalAccuracy: Double(hAcc),
                lean: lean.isNaN ? nil : Double(lean)
            ))
        }
        return points
    }

    /// v1 encoder, kept only so tests can produce old blobs.
    static func encodeV1(_ points: [TrackPoint]) throws -> Data {
        var raw = Data(capacity: headerSize + points.count * bytesPerPoint)
        raw.append(contentsOf: magic)
        raw.append(1)
        raw.appendLE(UInt32(points.count))
        for p in points {
            raw.appendPoint(p, time: p.timestamp.timeIntervalSinceReferenceDate)
        }
        return try (raw as NSData).compressed(using: .lzfse) as Data
    }
}

// MARK: - Byte helpers

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func appendPoint(_ p: TrackPoint, time: Double) {
        appendLE(time.bitPattern)
        appendLE(p.coordinate.latitude.bitPattern)
        appendLE(p.coordinate.longitude.bitPattern)
        appendLE(Float(p.altitude ?? .nan).bitPattern)
        appendLE(Float(p.speed ?? .nan).bitPattern)
        appendLE(Float(p.course ?? .nan).bitPattern)
        appendLE(Float(p.horizontalAccuracy).bitPattern)
        appendLE(Float(p.lean ?? .nan).bitPattern)
    }
}

struct ByteReader {
    let data: Data
    var offset: Int

    init(data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    mutating func bytes(_ n: Int) -> [UInt8]? {
        guard offset + n <= data.endIndex else { return nil }
        defer { offset += n }
        return Array(data[offset..<offset + n])
    }

    mutating func integer<T: FixedWidthInteger>(_: T.Type) -> T? {
        guard let b = bytes(MemoryLayout<T>.size) else { return nil }
        var value: T = 0
        for (i, byte) in b.enumerated() { value |= T(byte) << (8 * i) }
        return value
    }

    mutating func uint32() -> UInt32? { integer(UInt32.self) }
    mutating func double() -> Double? { integer(UInt64.self).map(Double.init(bitPattern:)) }
    mutating func float() -> Float? { integer(UInt32.self).map(Float.init(bitPattern:)) }
}
