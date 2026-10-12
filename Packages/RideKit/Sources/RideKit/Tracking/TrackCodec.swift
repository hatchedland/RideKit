import Foundation

/// Compact binary encoding for a ride's track, stored as one SwiftData blob (synced as a CKAsset).
///
/// Layout (little-endian), then LZFSE-compressed:
/// ```
/// header : "RTK" + version(UInt8) + count(UInt32)
/// point  : t(Float64, seconds since 2001) lat(Float64) lon(Float64)
///          alt(Float32) speed(Float32) course(Float32) hAcc(Float32) lean(Float32)
/// ```
/// Unknown optional values are stored as NaN. 44 bytes per point before compression.
public enum TrackCodec {
    static let magic: [UInt8] = Array("RTK".utf8)
    static let version: UInt8 = 1
    static let bytesPerPoint = 8 * 3 + 4 * 5

    public enum DecodeError: Error, Equatable {
        case notCompressed
        case badHeader
        case unsupportedVersion(UInt8)
        case truncated
    }

    public static func encode(_ points: [TrackPoint]) throws -> Data {
        var raw = Data(capacity: 8 + points.count * bytesPerPoint)
        raw.append(contentsOf: magic)
        raw.append(version)
        raw.appendLE(UInt32(points.count))
        for p in points {
            raw.appendLE(p.timestamp.timeIntervalSinceReferenceDate.bitPattern)
            raw.appendLE(p.coordinate.latitude.bitPattern)
            raw.appendLE(p.coordinate.longitude.bitPattern)
            raw.appendLE(Float(p.altitude ?? .nan).bitPattern)
            raw.appendLE(Float(p.speed ?? .nan).bitPattern)
            raw.appendLE(Float(p.course ?? .nan).bitPattern)
            raw.appendLE(Float(p.horizontalAccuracy).bitPattern)
            raw.appendLE(Float(p.lean ?? .nan).bitPattern)
        }
        return try (raw as NSData).compressed(using: .lzfse) as Data
    }

    public static func decode(_ data: Data) throws -> [TrackPoint] {
        let raw: Data
        do {
            raw = try (data as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw DecodeError.notCompressed
        }
        var reader = ByteReader(data: raw)
        guard let header = reader.bytes(3), header == magic else { throw DecodeError.badHeader }
        guard let v = reader.bytes(1)?.first else { throw DecodeError.badHeader }
        guard v == version else { throw DecodeError.unsupportedVersion(v) }
        guard let count = reader.uint32() else { throw DecodeError.truncated }

        var points: [TrackPoint] = []
        points.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let t = reader.double(), let lat = reader.double(), let lon = reader.double(),
                  let alt = reader.float(), let speed = reader.float(), let course = reader.float(),
                  let hAcc = reader.float(), let lean = reader.float()
            else { throw DecodeError.truncated }
            points.append(TrackPoint(
                timestamp: Date(timeIntervalSinceReferenceDate: t),
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
}

// MARK: - Byte helpers

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
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
