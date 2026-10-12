import Foundation

/// Metadata for the ride in progress, saved next to the point buffer so a killed app can recover it.
public struct ActiveRide: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var startedAt: Date
    /// `PHAssetCollection.localIdentifier` of the ride's Photos album, once created.
    public var albumIdentifier: String?
    /// Spots marked during this ride (their IDs), so recovery can re-link them.
    public var spotIDs: [UUID]

    public init(id: UUID = UUID(), name: String, startedAt: Date, albumIdentifier: String? = nil, spotIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.albumIdentifier = albumIdentifier
        self.spotIDs = spotIDs
    }
}

/// Append-only on-disk store for the ride in progress.
///
/// Each accepted fix is written immediately as a fixed-size record, so if iOS kills the app mid-ride
/// at most the last partially written record is lost. When the ride ends, the points are compressed
/// with `TrackCodec` into the SwiftData `Ride` and the buffer is cleared.
public final class TrackBuffer: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    private var handle: FileHandle?

    private var pointsURL: URL { directory.appending(path: "active-ride.points") }
    private var metadataURL: URL { directory.appending(path: "active-ride.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    deinit {
        try? handle?.close()
    }

    /// Starts a fresh buffer for `ride`, discarding any previous one.
    public func begin(_ ride: ActiveRide) throws {
        try lock.withLock {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? handle?.close()
            handle = nil
            try Data().write(to: pointsURL, options: .atomic)
            try writeMetadata(ride)
        }
    }

    public func updateMetadata(_ ride: ActiveRide) throws {
        try lock.withLock { try writeMetadata(ride) }
    }

    public func append(_ point: TrackPoint) throws {
        try lock.withLock {
            if handle == nil {
                handle = try FileHandle(forWritingTo: pointsURL)
                try handle?.seekToEnd()
            }
            try handle?.write(contentsOf: Self.record(for: point))
        }
    }

    /// The interrupted ride, if the app was killed while recording.
    public func recover() -> (ride: ActiveRide, points: [TrackPoint])? {
        lock.withLock {
            guard let metaData = try? Data(contentsOf: metadataURL),
                  let ride = try? JSONDecoder().decode(ActiveRide.self, from: metaData)
            else { return nil }
            let raw = (try? Data(contentsOf: pointsURL)) ?? Data()
            return (ride, Self.points(from: raw))
        }
    }

    public var hasActiveRide: Bool {
        FileManager.default.fileExists(atPath: metadataURL.path())
    }

    /// Removes the buffer after the ride has been saved.
    public func clear() {
        lock.withLock {
            try? handle?.close()
            handle = nil
            try? FileManager.default.removeItem(at: pointsURL)
            try? FileManager.default.removeItem(at: metadataURL)
        }
    }

    // MARK: Encoding

    private func writeMetadata(_ ride: ActiveRide) throws {
        // Default date coding on both sides keeps sub-second precision, which the album window relies on.
        try JSONEncoder().encode(ride).write(to: metadataURL, options: .atomic)
    }

    static func record(for p: TrackPoint) -> Data {
        var data = Data(capacity: TrackCodec.bytesPerPoint)
        data.appendLE(p.timestamp.timeIntervalSinceReferenceDate.bitPattern)
        data.appendLE(p.coordinate.latitude.bitPattern)
        data.appendLE(p.coordinate.longitude.bitPattern)
        data.appendLE(Float(p.altitude ?? .nan).bitPattern)
        data.appendLE(Float(p.speed ?? .nan).bitPattern)
        data.appendLE(Float(p.course ?? .nan).bitPattern)
        data.appendLE(Float(p.horizontalAccuracy).bitPattern)
        data.appendLE(Float(p.lean ?? .nan).bitPattern)
        return data
    }

    /// Decodes complete records; a trailing partial record (crash mid-write) is ignored.
    static func points(from raw: Data) -> [TrackPoint] {
        var reader = ByteReader(data: raw)
        var points: [TrackPoint] = []
        points.reserveCapacity(raw.count / TrackCodec.bytesPerPoint)
        while let t = reader.double(), let lat = reader.double(), let lon = reader.double(),
              let alt = reader.float(), let speed = reader.float(), let course = reader.float(),
              let hAcc = reader.float(), let lean = reader.float() {
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
