import Foundation
import RideKit

/// User preferences, stored in `UserDefaults` (read with `@AppStorage` in views).
enum AppSettings {
    enum Key {
        static let autoPause = "settings.autoPauseSensitivity"
        static let includeScreenshots = "settings.includeScreenshots"
        static let nearbyAlerts = "settings.nearbyAlerts"
        static let famousPlaceAlerts = "settings.famousPlaceAlerts"
        static let weatherAlerts = "settings.weatherAlerts"
        static let spotRadius = "settings.spotRadius"
        static let hasSeenSafetyNotice = "settings.hasSeenSafetyNotice"
        static let trackSongs = "settings.trackSongs"
        static let riderName = "settings.friends.riderName"
        static let shareRidesByDefault = "settings.friends.shareRidesByDefault"
        static let hideRideEnds = "settings.friends.hideRideEnds"
        static let privacyZones = "settings.friends.privacyZones"
    }

    /// Always kilometres and km/h: riders here think in km (decided 2026-11-16, no setting).
    /// Kept as a flag so the formatting code stays unit-aware if that ever changes.
    static var usesMetric: Bool { true }

    private static var defaults: UserDefaults { .standard }

    static var autoPauseSensitivity: AutoPauseDetector.Sensitivity {
        AutoPauseDetector.Sensitivity(rawValue: defaults.string(forKey: Key.autoPause) ?? "") ?? .normal
    }

    static var includeScreenshots: Bool { defaults.bool(forKey: Key.includeScreenshots) }

    static var nearbyAlerts: Bool {
        defaults.object(forKey: Key.nearbyAlerts) as? Bool ?? true
    }

    /// Announce well-reviewed sights within 2 km ahead while riding (Google Places).
    static var famousPlaceAlerts: Bool {
        defaults.object(forKey: Key.famousPlaceAlerts) as? Bool ?? true
    }

    /// Storm, rain, wind, heat and sunset alerts while riding (Google Weather).
    static var weatherAlerts: Bool {
        defaults.object(forKey: Key.weatherAlerts) as? Bool ?? true
    }

    /// Log songs played in the Music app during rides.
    static var trackSongs: Bool {
        defaults.object(forKey: Key.trackSongs) as? Bool ?? true
    }

    // MARK: Friends

    /// How friends see the rider, e.g. "Rajan". Empty: the iCloud name is used.
    /// The name friends see; kept in step with the account profile.
    static var riderName: String {
        get { defaults.string(forKey: Key.riderName) ?? "" }
        set { defaults.set(newValue, forKey: Key.riderName) }
    }

    /// New rides start with "Share with friends" on (still changeable on the Start sheet).
    static var shareRidesByDefault: Bool { defaults.bool(forKey: Key.shareRidesByDefault) }

    /// Cut the first and last 500 m of every shared ride. On by default.
    static var hideRideEnds: Bool {
        defaults.object(forKey: Key.hideRideEnds) as? Bool ?? true
    }

    static var privacyZones: [PrivacyZone] {
        get {
            guard let data = defaults.data(forKey: Key.privacyZones) else { return [] }
            return (try? JSONDecoder().decode([PrivacyZone].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.privacyZones) }
    }

    /// What friends may see of any ride, from the settings above.
    static var sharePrivacy: SharePrivacy {
        SharePrivacy(zones: privacyZones, endTrim: hideRideEnds ? SharePrivacy.defaultEndTrim : 0)
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

    /// Like `distance`, but 1,000 km and more as "14.1k km", so it fits a narrow readout.
    static func shortDistance(_ meters: Double, usesMetric: Bool = AppSettings.usesMetric) -> String {
        let value = usesMetric ? meters / 1_000 : meters / 1_609.344
        guard value >= 1_000 else { return distance(meters, usesMetric: usesMetric) }
        return String(format: "%.1fk %@", value / 1_000, usesMetric ? "km" : "mi")
    }

    /// Distance split for signboard layouts: ("131", "KM"), ("34.8", "KM"), ("0.1", "KM").
    static func distanceParts(_ meters: Double, usesMetric: Bool = AppSettings.usesMetric) -> (value: String, unit: String) {
        let value = usesMetric ? meters / 1_000 : meters / 1_609.344
        return (value < 100 ? String(format: "%.1f", value) : String(format: "%.0f", value), usesMetric ? "KM" : "MI")
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
