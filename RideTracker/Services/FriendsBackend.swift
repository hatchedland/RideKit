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

/// Someone who sees your rides (you invited them).
struct Follower: Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
}

/// Friends on Supabase: invites, who sees whose rides, published rides with their trimmed tracks and
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

    // MARK: Invites and follows

    /// A fresh invite code (valid 7 days, one friend).
    func createInvite() async throws -> String {
        struct Invite: Decodable { var code: String }
        let invite: Invite = try await client.from("friend_invites").insert([String: String](), returning: .representation)
            .select("code").single().execute().value
        return invite.code
    }

    /// Accepts an invite; returns the inviter's name.
    func acceptInvite(_ code: String) async throws -> String {
        let owner: UUID = try await client.rpc("accept_friend_invite", params: ["invite_code": code]).execute().value
        struct Profile: Decodable { var display_name: String }
        let profile: Profile? = try? await client.from("profiles").select("display_name").eq("id", value: owner).single().execute().value
        let name = profile?.display_name ?? ""
        return name.isEmpty ? "your friend" : name
    }

    /// Stop seeing a friend's rides.
    func leave(friendID: String) async throws {
        let me = try await me()
        try await client.from("friend_shares").delete().eq("owner_id", value: friendID).eq("friend_id", value: me).execute()
    }

    /// People who see your rides.
    func followers() async throws -> [Follower] {
        let me = try await me()
        struct Share: Decodable { var friend_id: UUID }
        let shares: [Share] = try await client.from("friend_shares").select("friend_id").eq("owner_id", value: me).execute().value
        let names = try await displayNames(shares.map(\.friend_id))
        return shares.map { Follower(id: $0.friend_id, name: names[$0.friend_id] ?? "Rider") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func removeFollower(_ follower: Follower) async throws {
        let me = try await me()
        try await client.from("friend_shares").delete().eq("owner_id", value: me).eq("friend_id", value: follower.id).execute()
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

    /// Publishes (or republishes) a ride: the trimmed track, the picked photos as JPEG files, and the
    /// row friends read. `photoFiles` is keyed by `SharedRide.Photo.id` (the `MediaLink` id).
    func publish(_ ride: SharedRide, track: [TrackPoint], photoFiles: [String: URL]) async throws {
        let me = try await me()
        let folder = "\(me.uuidString.lowercased())/\(ride.id.uuidString.lowercased())"
        let storage = client.storage.from("shared")

        try await storage.upload("\(folder)/track", data: TrackCodec.encode(track),
                                 options: FileOptions(contentType: "application/octet-stream", upsert: true))
        try await client.from("shared_rides").upsert(SharedRideRow(ride, ownerID: me, trackPath: "\(folder)/track"),
                                                     onConflict: "ride_id", returning: .minimal).execute()

        // Photos: replace the set, so un-picked ones disappear for friends.
        try await client.from("shared_media").delete().eq("ride_id", value: ride.id).execute()
        var rows: [SharedMediaRow] = []
        for photo in ride.photos {
            guard let file = photoFiles[photo.id], let id = UUID(uuidString: photo.id) else { continue }
            let path = "\(folder)/photos/\(id.uuidString.lowercased()).jpg"
            try await storage.upload(path, fileURL: file, options: FileOptions(contentType: "image/jpeg", upsert: true))
            rows.append(SharedMediaRow(photo, rideID: ride.id, ownerID: me, path: path,
                                       stopID: ride.stops.first { $0.photoIDs.contains(photo.id) }?.id))
        }
        if !rows.isEmpty {
            try await client.from("shared_media").insert(rows, returning: .minimal).execute()
        }
    }

    func unpublish(rideID: UUID) async throws {
        let me = try await me()
        let folder = "\(me.uuidString.lowercased())/\(rideID.uuidString.lowercased())"
        try await client.from("shared_rides").delete().eq("ride_id", value: rideID).execute()
        let photos = (try? await client.storage.from("shared").list(path: "\(folder)/photos")) ?? []
        _ = try? await client.storage.from("shared").remove(paths: ["\(folder)/track"] + photos.map { "\(folder)/photos/\($0.name)" })
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

/// Finds an invite code in a link (`ridetracker://invite/<code>`) or anywhere in a pasted message.
enum InviteCode {
    /// Codes are 32 hex characters; the first such word in the text is the code.
    static func find(in text: String) -> String? {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        return words.first { $0.count == 32 && $0.allSatisfy(\.isHexDigit) }.map { $0.lowercased() }
    }

    static func link(_ code: String) -> URL {
        URL(string: "ridetracker://invite/\(code)")!
    }
}
