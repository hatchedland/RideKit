@preconcurrency import GoogleMaps
import SwiftUI

/// Google Maps JSON styles for the app's two looks, in light and dark.
/// Points of interest and transit are always hidden: these maps are about the rider's own spots.
@MainActor
enum MapStyles {
    private static var cache: [String: GMSMapStyle] = [:]

    static func style(look: MapLook, dark: Bool) -> GMSMapStyle? {
        let key = "\(look)-\(dark)"
        if let cached = cache[key] { return cached }
        var rules = hidden
        if dark { rules += night }
        if look == .muted { rules.append(##"{"stylers":[{"saturation":-70}]}"##) }
        let style = try? GMSMapStyle(jsonString: "[\(rules.joined(separator: ","))]")
        cache[key] = style
        return style
    }

    private static let hidden = [
        ##"{"featureType":"poi","stylers":[{"visibility":"off"}]}"##,
        ##"{"featureType":"transit","stylers":[{"visibility":"off"}]}"##,
    ]

    /// Asphalt-toned night map for the riding screen and dark mode.
    private static let night = [
        ##"{"elementType":"geometry","stylers":[{"color":"#22211e"}]}"##,
        ##"{"elementType":"labels.text.stroke","stylers":[{"color":"#1b1a17"}]}"##,
        ##"{"elementType":"labels.text.fill","stylers":[{"color":"#9a968b"}]}"##,
        ##"{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d8d3c4"}]}"##,
        ##"{"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#262a22"}]}"##,
        ##"{"featureType":"road","elementType":"geometry","stylers":[{"color":"#3a3833"}]}"##,
        ##"{"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#1b1a17"}]}"##,
        ##"{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#b5b0a2"}]}"##,
        ##"{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#5a564c"}]}"##,
        ##"{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f6f3ea"}]}"##,
        ##"{"featureType":"water","elementType":"geometry","stylers":[{"color":"#16222e"}]}"##,
        ##"{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#56606b"}]}"##,
    ]
}

/// Hands the API key to the Google Maps SDK once, before the first map is created.
@MainActor
enum GoogleMapsSetup {
    private static var configured = false

    /// The key from Info.plist (`GMSApiKey`, filled from `Config/Secrets.xcconfig`), or `nil` if it wasn't set.
    static var apiKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "YOUR_KEY_HERE" ? nil : trimmed
    }

    static var hasKey: Bool { apiKey != nil }

    static func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        if let apiKey {
            GMSServices.provideAPIKey(apiKey)
        }
    }
}

/// Google's attribution under lists of Google Places results that aren't on a Google map.
struct PoweredByGoogle: View {
    var body: some View {
        Text("Results from Google Maps")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Search results from Google Maps")
    }
}
