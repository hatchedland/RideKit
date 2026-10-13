import Foundation
import RideKit

/// User preferences, stored in `UserDefaults` (read with `@AppStorage` in views).
enum AppSettings {
    enum Key {
        static let units = "settings.units"
        static let autoPause = "settings.autoPauseSensitivity"
        static let includeScreenshots = "settings.includeScreenshots"
        static let nearbyAlerts = "settings.nearbyAlerts"
        static let spotRadius = "settings.spotRadius"
        static let hasSeenSafetyNotice = "settings.hasSeenSafetyNotice"
        static let trackSongs = "settings.trackSongs"
    }

    enum Units: String, CaseIterable, Identifiable {
        case system, metric, imperial
        var id: Self { self }
        var title: String {
            switch self {
            case .system: "Automatic"
            case .metric: "Kilometres"
            case .imperial: "Miles"
            }
        }
    }

    private static var defaults: UserDefaults { .standard }

    static var units: Units {
        Units(rawValue: defaults.string(forKey: Key.units) ?? "") ?? .system
    }

    static var usesMetric: Bool {
        switch units {
        case .metric: true
        case .imperial: false
        case .system: Locale.current.measurementSystem != .us
        }
    }

    static var autoPauseSensitivity: AutoPauseDetector.Sensitivity {
        AutoPauseDetector.Sensitivity(rawValue: defaults.string(forKey: Key.autoPause) ?? "") ?? .normal
    }

    static var includeScreenshots: Bool { defaults.bool(forKey: Key.includeScreenshots) }

    static var nearbyAlerts: Bool {
        defaults.object(forKey: Key.nearbyAlerts) as? Bool ?? true
    }

    /// Log songs played in the Music app during rides.
    static var trackSongs: Bool {
        defaults.object(forKey: Key.trackSongs) as? Bool ?? true
    }

    /// Radius for attaching photos to spots and for wishlist auto-visit.
    static var spotRadius: Double {
        let value = defaults.double(forKey: Key.spotRadius)
        return value > 0 ? value : MediaPlacer.defaultSpotRadius
    }
}

/// Formatting that follows the units setting.
enum Format {
    static func distance(_ meters: Double, usesMetric: Bool = AppSettings.usesMetric) -> String {
        let value = usesMetric ? meters / 1_000 : meters / 1_609.344
        let unit = usesMetric ? "km" : "mi"
        return value < 100 ? String(format: "%.1f %@", value, unit) : String(format: "%.0f %@", value, unit)
    }

    static func speed(_ mps: Double, usesMetric: Bool = AppSettings.usesMetric) -> String {
        String(format: "%.0f", speedValue(mps, usesMetric: usesMetric))
    }

    static func speedValue(_ mps: Double, usesMetric: Bool = AppSettings.usesMetric) -> Double {
        max(0, usesMetric ? mps * 3.6 : mps * 2.236_936)
    }

    static func speedUnit(usesMetric: Bool = AppSettings.usesMetric) -> String {
        usesMetric ? "km/h" : "mph"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Position along a ride, read like a milestone: "km 38".
    static func milestone(_ meters: Double, usesMetric: Bool = AppSettings.usesMetric) -> String {
        usesMetric ? "km \(Int(meters / 1_000))" : "mi \(Int(meters / 1_609.344))"
    }

    /// A stretch of road: "52 min", "1 h 10 min".
    static func roadTime(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(60, seconds)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func elevation(_ meters: Double, usesMetric: Bool = AppSettings.usesMetric) -> String {
        usesMetric ? String(format: "%.0f m", meters) : String(format: "%.0f ft", meters * 3.280_84)
    }
}
