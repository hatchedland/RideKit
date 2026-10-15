import CloudKit
import Foundation
import Observation
import Photos
import RideKit
import UIKit

/// Friends: sharing your rides (and a ride in progress) with people you invite, and seeing theirs.
/// Runs on CloudKit sharing (`FriendsCloud`): no accounts, no servers. Needs iCloud, so the free
/// Personal build has no friends.
@MainActor
@Observable
final class FriendsService {
    enum Availability: Equatable {
        case checking
        case available
        /// Signed out of iCloud, or iCloud Drive restricted.
        case needsICloud
        /// The free Personal build has no iCloud entitlement.
        case unsupportedBuild
    }

    private(set) var availability: Availability = .checking
    private(set) var friends: [FriendSnapshot] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?
    /// Name of a friend whose invitation was just accepted, for the "share back" prompt.
    var justAccepted: String?

    private var liveThrottle = LivePublishThrottle()
    private var liveTask: Task<Void, Never>?

    static var isSupportedBuild: Bool {
        #if PERSONAL_TEAM
        false
        #else
        true
        #endif
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

    /// Checks iCloud, clears a live ride left behind by a crash, and loads friends.
    func start(isRidingLive: Bool) async {
        await checkAvailability()
        guard availability == .available else { return }
        if !isRidingLive { try? await FriendsCloud.endLive() }
        await refresh()
    }

    func checkAvailability() async {
        guard Self.isSupportedBuild else {
            availability = .unsupportedBuild
            return
        }
        let status = try? await FriendsCloud.container.accountStatus()
        availability = status == .available ? .available : .needsICloud
    }

    func refresh() async {
        guard availability == .available, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            friends = try await FriendsCloud.fetchFriends()
            lastRefresh = .now
            lastError = nil
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: Invitations

    /// The share friends join through; the share sheet sends its link.
    nonisolated static func inviteShare() async throws -> CKShare {
        let name = await MainActor.run { AppSettings.riderName }
        return try await FriendsCloud.share(title: name.isEmpty ? "My rides" : "\(name)’s rides")
    }

    func accept(_ metadata: CKShare.Metadata) async {
        guard Self.isSupportedBuild else { return }
        do {
            justAccepted = try await FriendsCloud.accept(metadata)
            await refresh()
        } catch {
            lastError = Self.message(for: error)
        }
    }

    /// Stop seeing a friend's rides. They keep seeing yours until removed under "Who sees my rides".
    func leave(_ friend: FriendSnapshot) async {
        do {
            try await FriendsCloud.leave(zoneID: friend.zoneID)
            friends.removeAll { $0.id == friend.id }
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: Sharing rides

    /// Publishes the ride for friends, with the photos marked `sharedWithFriends`, after removing
    /// everything inside privacy zones and near the ride's start and end.
    func publish(_ ride: Ride) async {
        guard availability == .available else { return }
        let privacy = AppSettings.sharePrivacy
        let fullTrack = ride.decodedTrack()
        let shared = Self.sharedRide(from: ride, track: fullTrack).redacted(by: privacy, track: fullTrack)
        let photoFiles = await Self.exportPhotos(shared.photos.map(\.id))
        // Photos that couldn't be exported (deleted, iCloud offline) are left out.
        var final = shared
        final.photos = shared.photos.filter { photoFiles[$0.id] != nil }
        let photoIDs = Set(final.photos.map(\.id))
        final.stops = final.stops.map { var stop = $0; stop.photoIDs.removeAll { !photoIDs.contains($0) }; return stop }

        do {
            try await FriendsCloud.publish(final, track: privacy.redact(fullTrack), photoFiles: final.photos.compactMap { photoFiles[$0.id] })
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
        guard availability == .available else { return }
        do {
            try await FriendsCloud.unpublish(rideID: ride.id)
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
            media: media.map { Trail.Media(id: $0.localIdentifier, capturedAt: $0.capturedAt, coordinate: $0.coordinate, spotID: $0.spot?.id) },
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
                SharedRide.Photo(id: $0.localIdentifier, capturedAt: $0.capturedAt, coordinate: $0.coordinate, isVideo: $0.isVideo)
            }
        )
    }

    /// JPEG copies (longest side 2048 px) of the chosen photos; a video is shared as a still frame.
    private static func exportPhotos(_ localIDs: [String]) async -> [String: URL] {
        let folder = URL.temporaryDirectory.appending(path: "friends-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [String: URL] = [:]
        for (index, id) in localIDs.enumerated() {
            guard let image = await PhotoImages.image(for: id, size: CGSize(width: 2048, height: 2048), contentMode: .aspectFit),
                  let data = image.jpegData(compressionQuality: 0.8) else { continue }
            let url = folder.appending(path: "\(index).jpg")
            if (try? data.write(to: url)) != nil { files[id] = url }
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
        liveTask = Task { try? await FriendsCloud.publishLive(live) }
    }

    func endLive() {
        liveTask?.cancel()
        liveThrottle.reset()
        liveTask = Task { try? await FriendsCloud.endLive() }
    }

    // MARK: Errors

    static func message(for error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .networkUnavailable, .networkFailure: return "You're offline. Friends will update when you're back online."
        case .notAuthenticated: return "Sign in to iCloud to use Friends."
        case .quotaExceeded: return "Your iCloud storage is full, so this ride couldn't be shared."
        case .participantMayNeedVerification: return "Check the invitation in Settings › iCloud and try again."
        default: return error.localizedDescription
        }
    }
}
