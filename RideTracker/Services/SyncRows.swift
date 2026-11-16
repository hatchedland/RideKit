import CryptoKit
import Foundation
import RideKit

/// A row of one of the rider's Supabase tables (`supabase/migrations`), mapped to and from SwiftData.
/// Encoding sends only what the phone owns; `updated_at` is the server's and `deleted_at` is set by
/// `SyncService` when the phone deletes something.
protocol SyncRow: Codable, Sendable {
    var id: UUID { get }
    var updatedAt: Date? { get }
    var deletedAt: Date? { get }
}

extension SyncRow {
    /// Hash of exactly what gets uploaded, so "changed since the last sync" means "different upload".
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return UUID().uuidString }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct RideSyncRow: SyncRow {
    var id: UUID
    var userID: UUID?
    var name: String
    var notes: String
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var movingSeconds: Double
    var maxSpeedMps: Double
    var avgMovingSpeedMps: Double
    var elevationGainMeters: Double
    var trackPath: String?
    var includeScreenshots: Bool
    var destinationName: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var destinationSpotID: UUID?
    var destinationReachedAt: Date?
    var sharedWithFriends: Bool
    var sharedAt: Date?
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case userID = "user_id", startedAt = "started_at", endedAt = "ended_at"
        case distanceMeters = "distance_meters", movingSeconds = "moving_seconds", maxSpeedMps = "max_speed_mps"
        case avgMovingSpeedMps = "avg_moving_speed_mps", elevationGainMeters = "elevation_gain_meters"
        case trackPath = "track_path", includeScreenshots = "include_screenshots"
        case destinationName = "destination_name", destinationLatitude = "destination_latitude"
        case destinationLongitude = "destination_longitude", destinationSpotID = "destination_spot_id"
        case destinationReachedAt = "destination_reached_at"
        case sharedWithFriends = "shared_with_friends", sharedAt = "shared_at"
        case updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    init(_ ride: Ride, userID: UUID) {
        id = ride.id
        self.userID = userID
        name = ride.name
        notes = ride.notes
        startedAt = ride.startedAt
        endedAt = max(ride.endedAt, ride.startedAt)
        distanceMeters = ride.distanceMeters
        movingSeconds = ride.movingSeconds
        maxSpeedMps = ride.maxSpeedMps
        avgMovingSpeedMps = ride.avgMovingSpeedMps
        elevationGainMeters = ride.elevationGainMeters
        trackPath = ride.trackData == nil ? nil : SyncService.trackPath(userID: userID, rideID: ride.id)
        includeScreenshots = ride.includeScreenshots
        destinationName = ride.destinationName
        destinationLatitude = ride.destinationLatitude
        destinationLongitude = ride.destinationLongitude
        destinationSpotID = ride.destinationSpotID
        destinationReachedAt = ride.destinationReachedAt
        sharedWithFriends = ride.sharedWithFriends
        sharedAt = ride.sharedAt
    }

    func write(to ride: Ride) {
        ride.name = name
        ride.notes = notes
        ride.startedAt = startedAt
        ride.endedAt = endedAt
        ride.distanceMeters = distanceMeters
        ride.movingSeconds = movingSeconds
        ride.maxSpeedMps = maxSpeedMps
        ride.avgMovingSpeedMps = avgMovingSpeedMps
        ride.elevationGainMeters = elevationGainMeters
        ride.includeScreenshots = includeScreenshots
        ride.destinationName = destinationName
        ride.destinationLatitude = destinationLatitude
        ride.destinationLongitude = destinationLongitude
        ride.destinationSpotID = destinationSpotID
        ride.destinationReachedAt = destinationReachedAt
        ride.sharedWithFriends = sharedWithFriends
        ride.sharedAt = sharedAt
    }

    /// The server's own fields never go up.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(userID, forKey: .userID)
        try c.encode(name, forKey: .name)
        try c.encode(notes, forKey: .notes)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(distanceMeters, forKey: .distanceMeters)
        try c.encode(movingSeconds, forKey: .movingSeconds)
        try c.encode(maxSpeedMps, forKey: .maxSpeedMps)
        try c.encode(avgMovingSpeedMps, forKey: .avgMovingSpeedMps)
        try c.encode(elevationGainMeters, forKey: .elevationGainMeters)
        try c.encode(trackPath, forKey: .trackPath)
        try c.encode(includeScreenshots, forKey: .includeScreenshots)
        try c.encode(destinationName, forKey: .destinationName)
        try c.encode(destinationLatitude, forKey: .destinationLatitude)
        try c.encode(destinationLongitude, forKey: .destinationLongitude)
        try c.encode(destinationSpotID, forKey: .destinationSpotID)
        try c.encode(destinationReachedAt, forKey: .destinationReachedAt)
        try c.encode(sharedWithFriends, forKey: .sharedWithFriends)
        try c.encode(sharedAt, forKey: .sharedAt)
    }
}

struct SpotSyncRow: SyncRow {
    var id: UUID
    var rideID: UUID?
    var name: String
    var nameIsSuggested: Bool
    var notes: String
    var category: String
    var status: String
    var rating: Int?
    var priority: Int?
    var bestSeason: String?
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var address: String?
    var locality: String?
    var googleMapsURL: String
    var sourceURL: String?
    var visits: [Date]
    var autoVisitedByRideID: UUID?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, notes, category, status, rating, priority, latitude, longitude, altitude, address, locality, visits
        case rideID = "ride_id", nameIsSuggested = "name_is_suggested", bestSeason = "best_season"
        case googleMapsURL = "google_maps_url", sourceURL = "source_url", autoVisitedByRideID = "auto_visited_by_ride_id"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    init(_ spot: Spot) {
        id = spot.id
        rideID = spot.ride?.id
        name = spot.name
        nameIsSuggested = spot.nameIsSuggested
        notes = spot.notes
        category = spot.categoryRaw
        status = spot.statusRaw
        rating = spot.rating.map { min(5, max(1, $0)) }
        priority = spot.priority.map { min(3, max(1, $0)) }
        bestSeason = spot.bestSeason
        latitude = spot.latitude
        longitude = spot.longitude
        altitude = spot.altitude
        address = spot.address
        locality = spot.locality
        googleMapsURL = spot.googleMapsURL
        sourceURL = spot.sourceURL
        visits = spot.visits
        autoVisitedByRideID = spot.autoVisitedByRideID
        createdAt = spot.createdAt
    }

    func write(to spot: Spot, rides: (UUID) -> Ride?) {
        spot.name = name
        spot.nameIsSuggested = nameIsSuggested
        spot.notes = notes
        spot.categoryRaw = category
        spot.statusRaw = status
        spot.rating = rating
        spot.priority = priority
        spot.bestSeason = bestSeason
        spot.latitude = latitude
        spot.longitude = longitude
        spot.altitude = altitude
        spot.address = address
        spot.locality = locality
        spot.googleMapsURL = googleMapsURL
        spot.sourceURL = sourceURL
        spot.visits = visits
        spot.autoVisitedByRideID = autoVisitedByRideID
        spot.createdAt = createdAt
        spot.ride = rideID.flatMap(rides)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(rideID, forKey: .rideID)
        try c.encode(name, forKey: .name)
        try c.encode(nameIsSuggested, forKey: .nameIsSuggested)
        try c.encode(notes, forKey: .notes)
        try c.encode(category, forKey: .category)
        try c.encode(status, forKey: .status)
        try c.encode(rating, forKey: .rating)
        try c.encode(priority, forKey: .priority)
        try c.encode(bestSeason, forKey: .bestSeason)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(altitude, forKey: .altitude)
        try c.encode(address, forKey: .address)
        try c.encode(locality, forKey: .locality)
        try c.encode(googleMapsURL, forKey: .googleMapsURL)
        try c.encode(sourceURL, forKey: .sourceURL)
        try c.encode(visits, forKey: .visits)
        try c.encode(autoVisitedByRideID, forKey: .autoVisitedByRideID)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

/// A photo or video's details (never the file): which Photos item, when, where, and what it belongs to.
struct MediaSyncRow: SyncRow {
    var id: UUID
    var rideID: UUID?
    var spotID: UUID?
    var localIdentifier: String
    var cloudIdentifier: String?
    var kind: String
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    var isManual: Bool
    var sharedWithFriends: Bool
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, latitude, longitude
        case rideID = "ride_id", spotID = "spot_id", localIdentifier = "local_identifier", cloudIdentifier = "cloud_identifier"
        case capturedAt = "captured_at", isManual = "is_manual", sharedWithFriends = "shared_with_friends"
        case updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    init(_ link: MediaLink) {
        id = link.id
        rideID = link.ride?.id
        spotID = link.spot?.id
        localIdentifier = link.localIdentifier
        cloudIdentifier = link.cloudIdentifier
        kind = link.kindRaw
        capturedAt = link.capturedAt
        latitude = link.latitude
        longitude = link.longitude
        isManual = link.isManual
        sharedWithFriends = link.sharedWithFriends
    }

    func write(to link: MediaLink, rides: (UUID) -> Ride?, spots: (UUID) -> Spot?) {
        // Another device's Photos ID only works there; keep this phone's once it has resolved one.
        if link.localIdentifier.isEmpty { link.localIdentifier = localIdentifier }
        link.cloudIdentifier = cloudIdentifier
        link.kindRaw = kind
        link.capturedAt = capturedAt
        link.latitude = latitude
        link.longitude = longitude
        link.isManual = isManual
        link.sharedWithFriends = sharedWithFriends
        link.ride = rideID.flatMap(rides)
        link.spot = spotID.flatMap(spots)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(rideID, forKey: .rideID)
        try c.encode(spotID, forKey: .spotID)
        try c.encode(localIdentifier, forKey: .localIdentifier)
        try c.encode(cloudIdentifier, forKey: .cloudIdentifier)
        try c.encode(kind, forKey: .kind)
        try c.encode(capturedAt, forKey: .capturedAt)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(isManual, forKey: .isManual)
        try c.encode(sharedWithFriends, forKey: .sharedWithFriends)
    }
}

struct SongSyncRow: SyncRow {
    var id: UUID
    var rideID: UUID?
    var title: String
    var artist: String
    var album: String
    var storeID: String
    var startedAt: Date
    var listenedSeconds: Double
    var latitude: Double?
    var longitude: Double?
    var updatedAt: Date?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, latitude, longitude
        case rideID = "ride_id", storeID = "store_id", startedAt = "started_at", listenedSeconds = "listened_seconds"
        case updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    init(_ song: PlayedSong) {
        id = song.id
        rideID = song.ride?.id
        title = song.title
        artist = song.artist
        album = song.album
        storeID = song.storeID
        startedAt = song.startedAt
        listenedSeconds = song.listenedSeconds
        latitude = song.latitude
        longitude = song.longitude
    }

    func write(to song: PlayedSong, rides: (UUID) -> Ride?) {
        song.title = title
        song.artist = artist
        song.album = album
        song.storeID = storeID
        song.startedAt = startedAt
        song.listenedSeconds = listenedSeconds
        song.latitude = latitude
        song.longitude = longitude
        song.ride = rideID.flatMap(rides)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(rideID, forKey: .rideID)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encode(album, forKey: .album)
        try c.encode(storeID, forKey: .storeID)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(listenedSeconds, forKey: .listenedSeconds)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
    }
}
