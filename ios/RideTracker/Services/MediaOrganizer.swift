import Foundation
import RideKit
import SwiftData

/// Turns a ride's album items into in-app `MediaLink`s placed at spots or along the route, and
/// marks wishlist spots the ride visited.
@MainActor
final class MediaOrganizer {
    private let context: ModelContext
    private let photos: PhotoLibraryService

    init(context: ModelContext, photos: PhotoLibraryService) {
        self.context = context
        self.photos = photos
    }

    /// Links `items` to `ride`, attaching each to the nearest spot within the radius.
    /// Items already linked are skipped; manually placed items are never moved.
    func link(_ items: [MediaCandidate], to ride: Ride, radius: Double) {
        let existing = Set((ride.media ?? []).map(\.localIdentifier))
        let fresh = items.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }

        let spots = allSpots()
        let placements = MediaPlacer.place(fresh, spots: spots.map(\.reference), radius: radius)
        let cloudIDs = photos.cloudIdentifiers(for: fresh.map(\.id))

        for item in fresh {
            let link = MediaLink(candidate: item, cloudIdentifier: cloudIDs[item.id])
            link.ride = ride
            if case .spot(let spotID)? = placements[item.id] {
                link.spot = spots.first { $0.id == spotID }
            }
            context.insert(link)
        }
        try? context.save()
    }

    /// Re-places automatically linked items after spots changed (e.g. a spot was added on the summary).
    func replace(mediaOf ride: Ride, radius: Double) {
        let spots = allSpots()
        let references = spots.map(\.reference)
        for link in ride.media ?? [] where !link.isManual {
            let candidate = MediaCandidate(id: link.localIdentifier, capturedAt: link.capturedAt, coordinate: link.coordinate, kind: link.kind)
            if case .spot(let id) = MediaPlacer.place(candidate, spots: references, radius: radius) {
                link.spot = spots.first { $0.id == id }
            } else {
                link.spot = nil
            }
        }
        try? context.save()
    }

    /// Marks wishlist spots as visited when the ride stopped there or took a photo there.
    /// Returns them so the summary can show "Visited ✓ — Undo".
    func applyWishlistVisits(for ride: Ride, track: [TrackPoint], radius: Double) -> [Spot] {
        let wishlist = allSpots().filter { $0.status == .wantToGo }
        guard !wishlist.isEmpty else { return [] }
        let media = (ride.media ?? []).map {
            MediaCandidate(id: $0.localIdentifier, capturedAt: $0.capturedAt, coordinate: $0.coordinate, kind: $0.kind)
        }
        let visits = WishlistMatcher.visits(wishlist: wishlist.map(\.reference), track: track, media: media, radius: radius)
        var visited: [Spot] = []
        for visit in visits {
            guard let spot = wishlist.first(where: { $0.id == visit.spotID }) else { continue }
            spot.markVisited(on: visit.date, byRide: ride.id)
            visited.append(spot)
        }
        try? context.save()
        return visited
    }

    /// Photos for a spot or ride on *this* device, mapping cloud identifiers from other devices.
    func resolveLocalIdentifiers(_ links: [MediaLink]) {
        let missing = links.filter { photos.asset($0.localIdentifier) == nil }
        let mapping = photos.localIdentifiers(forCloud: missing.compactMap(\.cloudIdentifier))
        var changed = false
        for link in missing {
            if let cloud = link.cloudIdentifier, let local = mapping[cloud] {
                link.localIdentifier = local
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    private func allSpots() -> [Spot] {
        (try? context.fetch(FetchDescriptor<Spot>())) ?? []
    }
}
