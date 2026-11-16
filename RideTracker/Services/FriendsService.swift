import Foundation
import Observation
import Photos
import RideKit
import UIKit

/// Friends: sharing your rides (and a ride in progress) with people you invite, and seeing theirs.
/// Runs on the rider's Supabase account (`FriendsBackend`); works in every build, Personal included.
@MainActor
@Observable
final class FriendsService {
    enum Availability: Equatable {
        case checking
        case available
        /// No account yet (the app shows sign-in first, so this is brief).
        case signedOut
    }

    private(set) var availability: Availability = .checking
    /// People who see your rides.
    private(set) var followers: [Follower] = []
    private(set) var friends: [FriendSnapshot] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?
    /// Name of a friend whose invitation was just accepted, for the "share back" prompt.
    var justAccepted: String?

    private var liveThrottle = LivePublishThrottle()
    private var liveTask: Task<Void, Never>?
    private var backend: FriendsBackend?
    private weak var account: AccountService?
    private weak var sync: SyncService?

    /// Connects friends to the rider's account (and to sync, so a ride exists in the account before
    /// it's published). Called once at launch.
    func configure(account: AccountService, sync: SyncService) {
        self.account = account
        self.sync = sync
        backend = account.client.map(FriendsBackend.init)
    }

    /// Friends currently riding (live and not expired), newest first.
    func ridingNow(at now: Date = .now) -> [(friend: FriendSnapshot, live: LiveRide)] {
        friends.compactMap { friend in
            guard let live = friend.live, live.status(at: now) != .expired else { return nil }
            return (friend, live)
        }
        .sorted { $0.live.updatedAt > $1.live.updatedAt }
    }

    /// Every friend's shared rides, newest first.
    var feed: [(friend: FriendSnapshot, ride: FriendSnapshot.Ride)] {
        friends.flatMap { friend in friend.rides.map { (friend, $0) } }
            .sorted { $0.ride.ride.endedAt > $1.ride.ride.endedAt }
    }

    // MARK: Lifecycle

    /// Clears a live ride left behind by a crash, keeps the profile name current, and loads friends.
    func start(isRidingLive: Bool) async {
        await checkAvailability()
        guard availability == .available, let backend else { return }
        if !isRidingLive { try? await backend.endLive() }
        let name = AppSettings.riderName
        if !name.isEmpty { try? await backend.setDisplayName(name) }
        await refresh()
    }

    func checkAvailability() async {
        availability = account?.isSignedIn == true && backend != nil ? .available : .signedOut
    }

    func refresh() async {
        if availability != .available { await checkAvailability() }
        guard availability == .available, let backend, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            friends = try await backend.fetchFriends()
            followers = try await backend.followers()
            lastRefresh = .now
            lastError = nil
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: Invitations

    func lastErrorFromInvite() {
        lastError = "Couldn't make an invite. Check your connection and try again."
    }

    /// A message to send through the share sheet: a link that opens the app, and the code itself for
    /// apps that don't make `ridetracker://` links tappable.
    func inviteMessage() async throws -> String {
        guard let backend else { throw URLError(.userAuthenticationRequired) }
        let code = try await backend.createInvite()
        let name = AppSettings.riderName
        return """
        \(name.isEmpty ? "Ride" : "\(name) wants to ride") with you on Ride Tracker 🏍️
        Tap to see my rides: \(InviteCode.link(code).absoluteString)
        Or open Ride Tracker › Friends › Paste invite. Code: \(code)
        (valid for 7 days)
        """
    }

    /// Accepts an invite from a link or a pasted message.
    func acceptInvite(from text: String) async {
        guard let code = InviteCode.find(in: text) else {
            lastError = "There's no invite code in that. Ask your friend to send the invite again."
            return
        }
        guard let backend else { return }
        do {
            justAccepted = try await backend.acceptInvite(code)
            lastError = nil
            await refresh()
        } catch {
            lastError = "That invite has expired or was already used. Ask your friend for a new one."
        }
    }

    /// Stop seeing a friend's rides. They keep seeing yours until you remove them from your followers.
    func leave(_ friend: FriendSnapshot) async {
        do {
            try await backend?.leave(friendID: friend.id)
            friends.removeAll { $0.id == friend.id }
        } catch {
            lastError = Self.message(for: error)
        }
    }

    /// Stop someone seeing your rides.
    func removeFollower(_ follower: Follower) async {
        do {
            try await backend?.removeFollower(follower)
            followers.removeAll { $0.id == follower.id }
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: Sharing rides

    /// Publishes the ride for friends, with the photos marked `sharedWithFriends`, after removing
    /// everything inside privacy zones and near the ride's start and end.
    func publish(_ ride: Ride) async {
        if availability != .available { await checkAvailability() }
        guard availability == .available, let backend else { return }
        // The published copy must point at a ride that's already in the rider's account.
        await sync?.sync()
        let privacy = AppSettings.sharePrivacy
        let fullTrack = ride.decodedTrack()
        let shared = Self.sharedRide(from: ride, track: fullTrack).redacted(by: privacy, track: fullTrack)
        let localIDs = Dictionary((ride.media ?? []).map { ($0.id.uuidString, $0.localIdentifier) }, uniquingKeysWith: { a, _ in a })
        let photoFiles = await Self.exportPhotos(shared.photos.compactMap { photo in localIDs[photo.id].map { (photo.id, $0) } })
        // Photos that couldn't be exported (deleted, iCloud offline) are left out.
        var final = shared
        final.photos = shared.photos.filter { photoFiles[$0.id] != nil }
        let photoIDs = Set(final.photos.map(\.id))
        final.stops = final.stops.map { var stop = $0; stop.photoIDs.removeAll { !photoIDs.contains($0) }; return stop }

        do {
            try await backend.publish(final, track: privacy.redact(fullTrack), photoFiles: photoFiles)
            ride.sharedWithFriends = true
            ride.sharedAt = .now
            lastError = nil
        } catch {
            lastError = Self.message(for: error)
        }
        for url in photoFiles.values { try? FileManager.default.removeItem(at: url) }
    }

    func unpublish(_ ride: Ride) async {
        ride.sharedWithFriends = false
        ride.sharedAt = nil
        guard availability == .available, let backend else { return }
        do {
            try await backend.unpublish(rideID: ride.id)
        } catch {
            lastError = Self.message(for: error)
        }
    }

    /// The ride reduced to what friends may see, before privacy redaction.
    static func sharedRide(from ride: Ride, track: [TrackPoint]) -> SharedRide {
        let media = (ride.media ?? []).filter(\.sharedWithFriends).sorted { $0.capturedAt < $1.capturedAt }
        let window = ride.startedAt...max(ride.startedAt, ride.endedAt)
        var spots: [Spot] = ride.spots ?? []
        for link in media { if let spot = link.spot, !spots.contains(where: { $0.id == spot.id }) { spots.append(spot) } }

        let trail = Trail.build(
            rideStart: ride.startedAt,
            rideEnd: ride.endedAt,
            track: track,
            // MediaLink ids, not Photos ids: they're the same on every phone and safe in storage paths.
            media: media.map { Trail.Media(id: $0.id.uuidString, capturedAt: $0.capturedAt, coordinate: $0.coordinate, spotID: $0.spot?.id) },
            spots: spots.map { spot in
                Trail.Spot(id: spot.id, coordinate: spot.coordinate, markedAt: spot.visits.filter { window.contains($0) }.min() ?? spot.createdAt)
            }
        )
        let stops = trail.stops.map { stop -> SharedRide.Stop in
            var name = "", category = SpotCategory.other.rawValue
            if case .spot(let id) = stop.kind, let spot = spots.first(where: { $0.id == id }) {
                name = spot.nameIsSuggested && spot.name.isEmpty ? "" : spot.displayName
                category = spot.categoryRaw
            }
            return SharedRide.Stop(id: stop.id, name: name, category: category, coordinate: stop.coordinate,
                                   arrivedAt: stop.arrivedAt, distanceFromStart: stop.distanceFromStart, photoIDs: stop.mediaIDs)
        }
        return SharedRide(
            id: ride.id,
            name: ride.name,
            startedAt: ride.startedAt,
            endedAt: ride.endedAt,
            distanceMeters: ride.distanceMeters,
            movingSeconds: ride.movingSeconds,
            maxSpeedMps: ride.maxSpeedMps,
            avgMovingSpeedMps: ride.avgMovingSpeedMps,
            elevationGainMeters: ride.elevationGainMeters,
            stops: stops,
            songs: ride.soundtrack.map {
                SharedRide.Song(title: $0.title, artist: $0.artist, storeID: $0.storeID.isEmpty ? nil : $0.storeID, startedAt: $0.startedAt)
            },
            photos: media.map {
                SharedRide.Photo(id: $0.id.uuidString, capturedAt: $0.capturedAt, coordinate: $0.coordinate, isVideo: $0.isVideo)
            }
        )
    }

    /// JPEG copies (longest side 2048 px) of the chosen photos; a video is shared as a still frame.
    /// Keyed by `SharedRide.Photo.id`; `items` pairs each with its Photos local identifier.
    private static func exportPhotos(_ items: [(id: String, localIdentifier: String)]) async -> [String: URL] {
        let folder = URL.temporaryDirectory.appending(path: "friends-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [String: URL] = [:]
        for (index, item) in items.enumerated() {
            guard let image = await PhotoImages.image(for: item.localIdentifier, size: CGSize(width: 2048, height: 2048), contentMode: .aspectFit),
                  let data = image.jpegData(compressionQuality: 0.8) else { continue }
            let url = folder.appending(path: "\(index).jpg")
            if (try? data.write(to: url)) != nil { files[item.id] = url }
        }
        return files
    }

    // MARK: Live

    /// Called with every accepted fix while the rider shares live. Publishes about once a minute.
    func updateLive(rideID: UUID, rideName: String, startedAt: Date, track: [TrackPoint], distance: Double, isPaused: Bool) {
        guard availability == .available, let last = track.last else { return }
        let privacy = AppSettings.sharePrivacy
        // Nothing until the rider is clear of the start (and outside any zone), so home stays private.
        let start = track[0].coordinate
        let visible = track.lazy.map(\.coordinate).filter { !privacy.hides($0) && $0.distance(to: start) > privacy.endTrim }
        guard !privacy.hides(last.coordinate), last.coordinate.distance(to: start) > privacy.endTrim,
              liveThrottle.shouldPublish(at: last.timestamp, position: last.coordinate, isPaused: isPaused) else { return }

        let live = LiveRide(rideID: rideID, rideName: rideName, startedAt: startedAt, updatedAt: last.timestamp,
                            position: last.coordinate, distanceMeters: distance, isPaused: isPaused,
                            path: LiveRide.thinned(Array(visible)))
        // Only the latest position matters: a slower upload is replaced, never queued.
        liveTask?.cancel()
        liveTask = Task { [backend] in try? await backend?.publishLive(live) }
    }

    func endLive() {
        liveTask?.cancel()
        liveThrottle.reset()
        liveTask = Task { [backend] in try? await backend?.endLive() }
    }

    // MARK: Errors

    static func message(for error: Error) -> String {
        if let error = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            return "You're offline. Friends will update when you're back online."
        }
        return "Something went wrong with Friends. Try again in a moment."
    }
}
