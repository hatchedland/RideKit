import Foundation
import MapKit
import RideKit

/// Suggests names for trail stops that aren't spots: the nearest Google Places landmark, else
/// "near <town>" from Apple's reverse geocoder. Answers are cached on device (not synced) so
/// reopening a ride doesn't look them up, and pay for them, again.
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
    private static let fileURL = URL.cachesDirectory.appending(path: "trail-names-google.json")  // new name: drops the old Apple Maps answers

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

            if let landmark = await spots.landmarks(near: coordinate).first {
                suggestions[key] = Suggestion(name: landmark.name, isLandmark: true, categoryRaw: landmark.spotCategory)
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
