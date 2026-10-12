import ActivityKit
import Foundation

/// Live Activity data for a ride in progress. Compiled into both the app and the widget extension.
struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var speedMps: Double
        var distanceMeters: Double
        var isPaused: Bool
        /// Photos and videos added to the ride's album so far.
        var albumItemCount: Int
        /// Shown briefly after "Mark spot", e.g. "📍 Spot saved".
        var lastSpotName: String?
        /// Metric or imperial, chosen in the app's Settings.
        var usesMetric: Bool
    }

    var rideName: String
    var startedAt: Date
}

extension RideActivityAttributes.ContentState {
    var speedText: String {
        let value = usesMetric ? speedMps * 3.6 : speedMps * 2.236_936
        return String(format: "%.0f", max(0, value))
    }

    var speedUnit: String { usesMetric ? "km/h" : "mph" }

    var distanceText: String {
        let value = usesMetric ? distanceMeters / 1_000 : distanceMeters / 1_609.344
        return String(format: value < 100 ? "%.1f" : "%.0f", value) + (usesMetric ? " km" : " mi")
    }
}
