import Foundation

/// A ride as friends see it: summary, stops, songs and the photos the rider chose to share.
/// Stored as JSON in the rider's shared CloudKit zone; the track and photo files travel alongside
/// it as assets. Everything in here has already passed `SharePrivacy`.
public struct SharedRide: Hashable, Sendable, Codable, Identifiable {
    public var formatVersion: Int = SharedRide.currentFormatVersion
    public var id: UUID
    public var name: String
    public var startedAt: Date
    public var endedAt: Date
    public var distanceMeters: Double
    public var movingSeconds: Double
    public var maxSpeedMps: Double
    public var avgMovingSpeedMps: Double
    public var elevationGainMeters: Double
    public var stops: [Stop]
    public var songs: [Song]
    /// In the order of the photo assets stored with the ride.
    public var photos: [Photo]

    public static let currentFormatVersion = 1

    public struct Stop: Hashable, Sendable, Codable, Identifiable {
        public var id: String
        /// Empty for an unnamed photo stop.
        public var name: String
        /// `SpotCategory` raw value in the app ("food", "viewpoint", …).
        public var category: String
        public var coordinate: Coordinate
        public var arrivedAt: Date
        /// Meters from the start of the (unredacted) ride, if known.
        public var distanceFromStart: Double?
        /// `Photo.id`s taken at this stop.
        public var photoIDs: [String]

        public init(id: String, name: String, category: String, coordinate: Coordinate, arrivedAt: Date,
                    distanceFromStart: Double? = nil, photoIDs: [String] = []) {
            self.id = id
            self.name = name
            self.category = category
            self.coordinate = coordinate
            self.arrivedAt = arrivedAt
            self.distanceFromStart = distanceFromStart
            self.photoIDs = photoIDs
        }

        public var googleMapsURL: URL { GoogleMapsLink.url(for: coordinate) }
    }

    public struct Song: Hashable, Sendable, Codable {
        public var title: String
        public var artist: String
        public var storeID: String?
        public var startedAt: Date

        public init(title: String, artist: String, storeID: String?, startedAt: Date) {
            self.title = title
            self.artist = artist
            self.storeID = storeID
            self.startedAt = startedAt
        }

        public var appleMusicURL: URL? {
            AppleMusicLink.url(for: NowPlayingSong(id: storeID ?? "\(title)|\(artist)", title: title, artist: artist, storeID: storeID))
        }
    }

    public struct Photo: Hashable, Sendable, Codable, Identifiable {
        public var id: String
        public var capturedAt: Date
        /// `nil` for photos without location, or whose location falls in a privacy zone.
        public var coordinate: Coordinate?
        public var isVideo: Bool

        public init(id: String, capturedAt: Date, coordinate: Coordinate?, isVideo: Bool = false) {
            self.id = id
            self.capturedAt = capturedAt
            self.coordinate = coordinate
            self.isVideo = isVideo
        }
    }

    public init(id: UUID, name: String, startedAt: Date, endedAt: Date, distanceMeters: Double = 0,
                movingSeconds: Double = 0, maxSpeedMps: Double = 0, avgMovingSpeedMps: Double = 0,
                elevationGainMeters: Double = 0, stops: [Stop] = [], songs: [Song] = [], photos: [Photo] = []) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.movingSeconds = movingSeconds
        self.maxSpeedMps = maxSpeedMps
        self.avgMovingSpeedMps = avgMovingSpeedMps
        self.elevationGainMeters = elevationGainMeters
        self.stops = stops
        self.songs = songs
        self.photos = photos
    }

    /// Removes what `privacy` doesn't allow: stops near home or the ride's ends, photo locations
    /// there, and photos that only existed at a hidden stop. Songs keep no place, only a time.
    public func redacted(by privacy: SharePrivacy, track: [TrackPoint]) -> SharedRide {
        var copy = self
        let hiddenStops = stops.filter { !privacy.shows($0.coordinate, track: track) }
        let hiddenPhotoIDs = Set(hiddenStops.flatMap(\.photoIDs))
        copy.stops = stops.filter { privacy.shows($0.coordinate, track: track) }
        copy.photos = photos.compactMap { photo in
            if hiddenPhotoIDs.contains(photo.id) { return nil }
            var photo = photo
            if let coordinate = photo.coordinate, !privacy.shows(coordinate, track: track) { photo.coordinate = nil }
            return photo
        }
        return copy
    }

    public func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SharedRide {
        let ride = try decoder.decode(SharedRide.self, from: data)
        guard ride.formatVersion <= currentFormatVersion else { throw FormatError.newerVersion(ride.formatVersion) }
        return ride
    }

    public enum FormatError: Error, Equatable {
        /// Shared by a newer app version; the friend needs to update.
        case newerVersion(Int)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
