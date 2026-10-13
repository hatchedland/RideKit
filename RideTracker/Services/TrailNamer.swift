import Foundation
import MapKit
import RideKit

/// Suggests names for trail stops that aren't spots: the nearest Apple Maps landmark, else
/// "near <town>". Answers are cached on disk (not synced) so reopening a ride doesn't hit
/// Apple's geocoding limits again.
@MainActor
@Observable
final class TrailNamer {
    struct Suggestion: Codable, Equatable {
        var name: String
        /// A real point of interest, as opposed to "near <town>".
        var isLandmark: Bool
        var categoryRaw: String

        var category: SpotCategory { SpotCategory(rawValue: categoryRaw) ?? .other }
    }

    private(set) var suggestions: [String: Suggestion] = [:]
    private let spots: SpotService
    private var inFlight: Set<String> = []
    private static let fileURL = URL.cachesDirectory.appending(path: "trail-names.json")

    init(spots: SpotService) {
        self.spots = spots
        if let data = try? Data(contentsOf: Self.fileURL),
           let cached = try? JSONDecoder().decode([String: Suggestion].self, from: data) {
            suggestions = cached
        }
    }

    func suggestion(for coordinate: Coordinate) -> Suggestion? {
        suggestions[Self.key(coordinate)]
    }

    /// Looks up names for `coordinates` one at a time, skipping cached ones.
    func resolve(_ coordinates: [Coordinate]) async {
        for coordinate in coordinates {
            let key = Self.key(coordinate)
            guard suggestions[key] == nil, !inFlight.contains(key) else { continue }
            inFlight.insert(key)
            defer { inFlight.remove(key) }

            if let landmark = await spots.landmarks(near: coordinate).first, let name = landmark.name {
                suggestions[key] = Suggestion(name: name, isLandmark: true,
                                              categoryRaw: SpotCategory(landmark.pointOfInterestCategory).rawValue)
            } else if let locality = await SpotService.reverseGeocode(coordinate).locality {
                suggestions[key] = Suggestion(name: "near \(locality)", isLandmark: false, categoryRaw: SpotCategory.other.rawValue)
            } else {
                continue // Offline or nothing nearby: try again next time.
            }
            save()
        }
    }

    private func save() {
        try? JSONEncoder().encode(suggestions).write(to: Self.fileURL, options: .atomic)
    }

    /// ~11 m grid, so a re-clustered stop still finds its name.
    private static func key(_ coordinate: Coordinate) -> String {
        String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }
}
