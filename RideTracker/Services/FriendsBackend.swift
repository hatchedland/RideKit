import Foundation
import RideKit
import Supabase

/// A friend whose rides you can see, with what they've shared.
struct FriendSnapshot: Identifiable, Sendable {
    /// The friend's account id.
    var id: String
    var name: String
    var rides: [Ride]
    var live: LiveRide?

    struct Ride: Identifiable, Sendable {
        var ride: SharedRide
        var track: [TrackPoint]
        /// `SharedRide.Photo.id` → cached JPEG.
        var photoFiles: [String: URL]

        var id: UUID { ride.id }
    }
}

/// A rider found by @handle.
struct RiderResult: Identifiable, Sendable, Hashable, Decodable {
    var id: UUID
    var username: String
    var displayName: String
    enum CodingKeys: String, CodingKey { case id, username, displayName = "display_name" }
}

/// A pending friend request, to or from you.
struct FriendRequest: Identifiable, Sendable, Hashable {
    var id: UUID
    /// The other rider.
    var riderID: UUID
    var name: String
    var username: String
    var incoming: Bool
}

/// Friends on Supabase: finding riders by @handle, friend requests (accepting makes friends both
/// ways), published rides with their trimmed tracks and
/// picked photos (bucket "shared"), and live rides. Row-level security in supabase/migrations makes
/// sure friends only ever read published copies, never the rider's own tables.
struct FriendsBackend: Sendable {
    let client: SupabaseClient

    private static let cache = URL.cachesDirectory.appending(path: "friends", directoryHint: .isDirectory)

    func me() async throws -> UUID {
        try await client.auth.session.user.id
    }

    // MARK: Profile

    func setDisplayName(_ name: String) async throws {
        let me = try await me()
        try await client.from("profiles").update(["display_name": String(name.prefix(60))]).eq("id", value: me).execute()
    }

    // MARK: Finding riders and friend requests

    func search(_ query: String) async throws -> [RiderResult] {
        try await client.rpc("search_riders", params: ["query": query]).execute().value
    }

    func sendRequest(to rider: UUID) async throws {
        try await client.from("friend_requests").insert(["to_id": rider], returning: .minimal).execute()
    }

    /// Requests to and from you, with the other rider's name and handle.
    func requests() async throws -> [FriendRequest] {
        let me = try await me()
        struct Row: Decodable { var id: UUID; var from_id: UUID; var to_id: UUID }
        let rows: [Row] = try await client.from("friend_requests").select("id, from_id, to_id").execute().value
        let others = rows.map { $0.from_id == me ? $0.to_id : $0.from_id }
        let profiles = try await profiles(others)
        return rows.map { row in
            let other = row.from_id == me ? row.to_id : row.from_id
            return FriendRequest(id: row.id, riderID: other, name: profiles[other]?.name ?? "Rider",
                                 username: profiles[other]?.username ?? "", incoming: row.to_id == me)
        }
    }

    /// Accepts a request; you're now friends both ways.
    func accept(_ request: FriendRequest) async throws {
        let _: UUID = try await client.rpc("accept_friend_request", params: ["request_id": request.id]).execute().value
    }

    /// Declines an incoming request or cancels one you sent.
    func dismiss(_ request: FriendRequest) async throws {
        try await client.from("friend_requests").delete().eq("id", value: request.id).execute()
    }

    /// Ends a friendship both ways.
    func unfriend(_ friendID: String) async throws {
        let me = try await me()
        try await client.from("friend_shares").delete().eq("owner_id", value: friendID).eq("friend_id", value: me).execute()
        try await client.from("friend_shares").delete().eq("owner_id", value: me).eq("friend_id", value: friendID).execute()
    }

    private func profiles(_ ids: [UUID]) async throws -> [UUID: (name: String, username: String)] {
        guard !ids.isEmpty else { return [:] }
        struct Profile: Decodable { var id: UUID; var display_name: String; var username: String? }
        let rows: [Profile] = try await client.from("profiles").select("id, display_name, username")
            .in("id", values: ids.map(\.uuidString)).execute().value
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, ($0.display_name.isEmpty ? "Rider" : $0.display_name, $0.username ?? "")) })
    }

    private func displayNames(_ ids: [UUID]) async throws -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        struct Profile: Decodable { var id: UUID; var display_name: String }
        let profiles: [Profile] = try await client.from("profiles").select("id, display_name")
            .in("id", values: ids.map(\.uuidString)).execute().value
        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.display_name.isEmpty ? "Rider" : $0.display_name) })
    }

    // MARK: Reading friends

    /// Everyone whose rides you can see, with their shared rides (track and photos cached on the
    /// phone) and their live ride, if any.
    func fetchFriends() async throws -> [FriendSnapshot] {
        let me = try await me()
        struct Share: Decodable { var owner_id: UUID }
        let shares: [Share] = try await client.from("friend_shares").select("owner_id").eq("friend_id", value: me)
            .execute().value
        let owners = shares.map(\.owner_id)
        guard !owners.isEmpty else { return [] }
        let ownerIDs = owners.map(\.uuidString)

        let names = try await displayNames(owners)
        let rides: [SharedRideRow] = try await client.from("shared_rides").select()
            .in("owner_id", values: ownerIDs).order("published_at", ascending: false).limit(200).execute().value
        let media: [SharedMediaRow] = rides.isEmpty ? [] : try await client.from("shared_media").select()
            .in("ride_id", values: rides.map(\.rideID.uuidString)).execute().value
        let lives: [LiveRow] = try await client.from("live_rides").select().in("owner_id", values: ownerIDs).execute().value

        var snapshots: [FriendSnapshot] = []
        for owner in owners {
            var friendRides: [FriendSnapshot.Ride] = []
            for row in rides where row.ownerID == owner {
                let photos = media.filter { $0.rideID == row.rideID }.sorted { $0.capturedAt < $1.capturedAt }
                let track = (try? await cachedTrack(row)) ?? []
                var files: [String: URL] = [:]
                for photo in photos {
                    if let url = try? await cachedPhoto(photo) { files[photo.id.uuidString] = url }
                }
                friendRides.append(FriendSnapshot.Ride(ride: row.sharedRide(photos: photos), track: track, photoFiles: files))
            }
            snapshots.append(FriendSnapshot(id: owner.uuidString, name: names[owner] ?? "Rider", rides: friendRides,
                                            live: lives.first { $0.ownerID == owner }?.liveRide))
        }
        return snapshots.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Tracks and photos are downloaded once per version and kept in Caches.
    private func cachedTrack(_ row: SharedRideRow) async throws -> [TrackPoint] {
        guard let path = row.trackPath else { return [] }
        let file = Self.cache.appending(path: "\(row.rideID.uuidString)-\(Int(row.updatedAt.timeIntervalSince1970)).track")
        if let data = try? Data(contentsOf: file) { return try TrackCodec.decode(data) }
        let data = try await client.storage.from("shared").download(path: path)
        try? FileManager.default.createDirectory(at: Self.cache, withIntermediateDirectories: true)
        try? data.write(to: file)
        return try TrackCodec.decode(data)
    }

    private func cachedPhoto(_ row: SharedMediaRow) async throws -> URL {
        let file = Self.cache.appending(path: "\(row.id.uuidString).jpg")
        if FileManager.default.fileExists(atPath: file.path()) { return file }
        let data = try await client.storage.from("shared").download(path: row.photoPath)
        try FileManager.default.createDirectory(at: Self.cache, withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }

    // MARK: Publishing your rides

    enum PublishError: Error, Equatable {
        /// The ride or its track isn't in the account yet (or still in the old format): sync, then retry.
        case needsSync
    }

    /// Publishes (or republishes) a ride through the `publish-shared-ride` Edge Function, which trims
    /// it with the privacy zones in the rider's account and writes what friends see. The picked photos
    /// (JPEG files keyed by `SharedRide.Photo.id`) go to a private outbox first, which friends can't
    /// read; the function moves only the allowed ones across.
    func publish(_ ride: SharedRide, photoFiles: [String: URL]) async throws {
        let me = try await me()
        let outbox = "\(me.uuidString.lowercased())/outbox/\(ride.id.uuidString.lowercased())"
        for (id, file) in photoFiles {
            try await client.storage.from("tracks").upload("\(outbox)/\(id.lowercased()).jpg", fileURL: file,
                                                           options: FileOptions(contentType: "image/jpeg", upsert: true))
        }
        do {
            try await client.functions.invoke("publish-shared-ride",
                                              options: FunctionInvokeOptions(body: PublishBody(ride: ride), encoder: Self.functionEncoder))
        } catch FunctionsError.httpError(let code, _) where code == 409 || code == 404 {
            throw PublishError.needsSync
        }
    }

    private struct PublishBody: Encodable { var ride: SharedRide }

    /// Dates as PostgREST writes them, because the function stores stops and songs as given.
    static let functionEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }()

    func unpublish(rideID: UUID) async throws {
        let me = try await me()
        let folder = "\(me.uuidString.lowercased())/\(rideID.uuidString.lowercased())"
        try await client.from("shared_rides").delete().eq("ride_id", value: rideID).execute()
        let photos = (try? await client.storage.from("shared").list(path: "\(folder)/photos")) ?? []
        _ = try? await client.storage.from("shared").remove(paths: ["\(folder)/track"] + photos.map { "\(folder)/photos/\($0.name)" })
    }

    // MARK: Privacy

    /// Privacy zones and "hide the start and end" live in the account, so every phone (and the server,
    /// which trims shared rides with them) has the same ones.
    func loadPrivacy() async throws -> (zones: [PrivacyZone], hideRideEnds: Bool) {
        let me = try await me()
        let zones: [ZoneRow] = try await client.from("privacy_zones").select().order("created_at").execute().value
        struct Profile: Decodable { var hide_ride_ends: Bool }
        let profile: Profile = try await client.from("profiles").select("hide_ride_ends").eq("id", value: me).single().execute().value
        return (zones.map(\.zone), profile.hide_ride_ends)
    }

    func savePrivacy(zones: [PrivacyZone], hideRideEnds: Bool) async throws {
        let me = try await me()
        try await client.from("profiles").update(["hide_ride_ends": hideRideEnds]).eq("id", value: me).execute()
        if !zones.isEmpty {
            try await client.from("privacy_zones").upsert(zones.map(ZoneRow.init), onConflict: "id", returning: .minimal).execute()
        }
        // Zones removed on this phone go from the account too.
        var removal = client.from("privacy_zones").delete().eq("user_id", value: me)
        if !zones.isEmpty {
            removal = removal.not("id", operator: .in, value: "(\(zones.map { $0.id.uuidString.lowercased() }.joined(separator: ",")))")
        }
        try await removal.execute()
    }

    // MARK: Live

    func publishLive(_ live: LiveRide) async throws {
        try await client.from("live_rides").upsert(LiveRow(live), onConflict: "owner_id", returning: .minimal).execute()
    }

    func endLive() async throws {
        let me = try await me()
        try await client.from("live_rides").delete().eq("owner_id", value: me).execute()
    }
}

// MARK: Rows

struct SharedRideRow: Codable, Sendable {
    var rideID: UUID
    var ownerID: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var movingSeconds: Double
    var maxSpeedMps: Double
    var avgMovingSpeedMps: Double
    var elevationGainMeters: Double
    var trackPath: String?
    var stops: [SharedRide.Stop]
    var songs: [SharedRide.Song]
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name, stops, songs
        case rideID = "ride_id", ownerID = "owner_id", startedAt = "started_at", endedAt = "ended_at"
        case distanceMeters = "distance_meters", movingSeconds = "moving_seconds", maxSpeedMps = "max_speed_mps"
        case avgMovingSpeedMps = "avg_moving_speed_mps", elevationGainMeters = "elevation_gain_meters"
        case trackPath = "track_path", updatedAt = "updated_at"
    }

    init(_ ride: SharedRide, ownerID: UUID, trackPath: String) {
        rideID = ride.id
        self.ownerID = ownerID
        name = ride.name
        startedAt = ride.startedAt
        endedAt = ride.endedAt
        distanceMeters = ride.distanceMeters
        movingSeconds = ride.movingSeconds
        maxSpeedMps = ride.maxSpeedMps
        avgMovingSpeedMps = ride.avgMovingSpeedMps
        elevationGainMeters = ride.elevationGainMeters
        self.trackPath = trackPath
        stops = ride.stops
        songs = ride.songs
        updatedAt = .now
    }

    /// The server sets updated_at and published_at itself.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rideID, forKey: .rideID)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(name, forKey: .name)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(distanceMeters, forKey: .distanceMeters)
        try c.encode(movingSeconds, forKey: .movingSeconds)
        try c.encode(maxSpeedMps, forKey: .maxSpeedMps)
        try c.encode(avgMovingSpeedMps, forKey: .avgMovingSpeedMps)
        try c.encode(elevationGainMeters, forKey: .elevationGainMeters)
        try c.encode(trackPath, forKey: .trackPath)
        try c.encode(stops, forKey: .stops)
        try c.encode(songs, forKey: .songs)
    }

    func sharedRide(photos: [SharedMediaRow]) -> SharedRide {
        SharedRide(id: rideID, name: name, startedAt: startedAt, endedAt: endedAt, distanceMeters: distanceMeters,
                   movingSeconds: movingSeconds, maxSpeedMps: maxSpeedMps, avgMovingSpeedMps: avgMovingSpeedMps,
                   elevationGainMeters: elevationGainMeters, stops: stops, songs: songs,
                   photos: photos.map { $0.photo })
    }
}

struct SharedMediaRow: Codable, Sendable {
    var id: UUID
    var rideID: UUID
    var ownerID: UUID
    var photoPath: String
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    var stopID: String?
    var isVideo: Bool

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude
        case rideID = "ride_id", ownerID = "owner_id", photoPath = "photo_path", capturedAt = "captured_at"
        case stopID = "stop_id", isVideo = "is_video"
    }

    init(_ photo: SharedRide.Photo, rideID: UUID, ownerID: UUID, path: String, stopID: String?) {
        id = UUID(uuidString: photo.id) ?? UUID()
        self.rideID = rideID
        self.ownerID = ownerID
        photoPath = path
        capturedAt = photo.capturedAt
        latitude = photo.coordinate?.latitude
        longitude = photo.coordinate?.longitude
        self.stopID = stopID
        isVideo = photo.isVideo
    }

    var photo: SharedRide.Photo {
        SharedRide.Photo(id: id.uuidString, capturedAt: capturedAt,
                         coordinate: latitude.flatMap { lat in longitude.map { Coordinate(latitude: lat, longitude: $0) } },
                         isVideo: isVideo)
    }
}

struct LiveRow: Codable, Sendable {
    var ownerID: UUID?
    var rideID: UUID
    var rideName: String
    var startedAt: Date
    var updatedAt: Date?
    var distanceMeters: Double
    var isPaused: Bool
    var latitude: Double
    var longitude: Double
    var path: [Coordinate]

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, path
        case ownerID = "owner_id", rideID = "ride_id", rideName = "ride_name", startedAt = "started_at"
        case updatedAt = "updated_at", distanceMeters = "distance_meters", isPaused = "is_paused"
    }

    init(_ live: LiveRide) {
        rideID = live.rideID
        rideName = live.rideName
        startedAt = live.startedAt
        distanceMeters = live.distanceMeters
        isPaused = live.isPaused
        latitude = live.position.latitude
        longitude = live.position.longitude
        path = live.path
    }

    /// owner_id defaults to the signed-in rider; updated_at is the server's clock.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rideID, forKey: .rideID)
        try c.encode(rideName, forKey: .rideName)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(distanceMeters, forKey: .distanceMeters)
        try c.encode(isPaused, forKey: .isPaused)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(path, forKey: .path)
    }

    var liveRide: LiveRide {
        LiveRide(rideID: rideID, rideName: rideName, startedAt: startedAt, updatedAt: updatedAt ?? startedAt,
                 position: Coordinate(latitude: latitude, longitude: longitude), distanceMeters: distanceMeters,
                 isPaused: isPaused, path: path)
    }
}

struct ZoneRow: Codable, Sendable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude
        case radiusMeters = "radius_meters"
    }

    init(_ zone: PrivacyZone) {
        id = zone.id
        name = zone.name
        latitude = zone.center.latitude
        longitude = zone.center.longitude
        radiusMeters = zone.radius
    }

    var zone: PrivacyZone {
        PrivacyZone(id: id, name: name, center: Coordinate(latitude: latitude, longitude: longitude), radius: radiusMeters)
    }
}
