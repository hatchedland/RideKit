import Foundation

/// Builds and parses Google Maps links.
///
/// Building uses Google's documented cross-platform "Maps URLs" format, which needs no API key:
/// https://developers.google.com/maps/documentation/urls/get-started
public enum GoogleMapsLink {

    // MARK: Building

    /// `https://www.google.com/maps/search/?api=1&query=28.613900,77.209000`
    public static func url(for coordinate: Coordinate) -> URL {
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: coordinate.queryString),
        ]
        return components.url!
    }

    /// Opens the Google Maps app directly (requires `comgooglemaps` in `LSApplicationQueriesSchemes`).
    public static func appURL(for coordinate: Coordinate) -> URL {
        var components = URLComponents()
        components.scheme = "comgooglemaps"
        components.host = ""
        components.queryItems = [
            URLQueryItem(name: "q", value: coordinate.queryString),
            URLQueryItem(name: "center", value: coordinate.queryString),
        ]
        return components.url!
    }

    /// Multi-stop directions, e.g. for "ride to these wishlist spots".
    /// Google allows up to 9 waypoints between origin and destination.
    public static func directionsURL(through stops: [Coordinate]) -> URL? {
        guard let destination = stops.last else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: destination.queryString),
            URLQueryItem(name: "travelmode", value: "driving"),
        ]
        let waypoints = stops.dropLast().prefix(9)
        if !waypoints.isEmpty {
            items.append(URLQueryItem(name: "waypoints", value: waypoints.map(\.queryString).joined(separator: "|")))
        }
        components.queryItems = items
        return components.url
    }

    // MARK: Parsing

    public enum ParseResult: Equatable, Sendable {
        /// Coordinates found directly in the link (or the text).
        case coordinate(Coordinate)
        /// A short link (`maps.app.goo.gl/…`) that must be resolved with an HTTP request first.
        case needsResolution(URL)
        /// A Google Maps link without coordinates (e.g. a text-only search) or not a maps link at all.
        case unrecognized
    }

    /// Extracts coordinates from anything a user might paste: a full Google Maps URL in any of
    /// its common shapes, a short share link, or plain "lat, lon" text.
    public static func parse(_ input: String) -> ParseResult {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let coordinate = plainCoordinate(in: text) {
            return .coordinate(coordinate)
        }

        // Share sheets often paste "Place name\nhttps://maps.app.goo.gl/…", so look for the URL inside.
        guard let url = firstURL(in: text), let host = url.host()?.lowercased() else {
            return .unrecognized
        }

        if isShortLinkHost(host, path: url.path()) {
            return .needsResolution(url)
        }
        guard isGoogleMapsHost(host, path: url.path()) else {
            return .unrecognized
        }
        if let coordinate = coordinate(inGoogleMapsURL: url) {
            return .coordinate(coordinate)
        }
        return .unrecognized
    }

    /// Coordinates from an already-expanded Google Maps URL.
    public static func coordinate(inGoogleMapsURL url: URL) -> Coordinate? {
        let absolute = url.absoluteString.removingPercentEncoding ?? url.absoluteString

        // 1. `!3d<lat>!4d<lon>` is the place's own location. Prefer it over `@lat,lon`,
        //    which is only where the map viewport happened to be centred.
        if let match = absolute.firstMatch(of: /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/),
           let c = makeCoordinate(match.1, match.2) {
            return c
        }

        // 2. Query parameters used by the various URL generations.
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["query", "q", "ll", "center", "destination", "daddr", "sll"] {
            if let value = items.first(where: { $0.name == name })?.value,
               let c = plainCoordinate(in: value) {
                return c
            }
        }

        // 3. Path segments: `/place/28.6,77.2`, `/search/28.6,+77.2`.
        for segment in url.pathComponents {
            let cleaned = (segment.removingPercentEncoding ?? segment).replacingOccurrences(of: "+", with: " ")
            if let c = plainCoordinate(in: cleaned) {
                return c
            }
        }

        // 4. Viewport centre `@lat,lon,zoom` as a last resort.
        if let match = absolute.firstMatch(of: /@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/),
           let c = makeCoordinate(match.1, match.2) {
            return c
        }
        return nil
    }

    // MARK: Helpers

    static func isShortLinkHost(_ host: String, path: String) -> Bool {
        host == "maps.app.goo.gl" || (host == "goo.gl" && path.hasPrefix("/maps"))
    }

    static func isGoogleMapsHost(_ host: String, path: String) -> Bool {
        if host == "maps.google.com" || host.hasPrefix("maps.google.") { return true }
        let isGoogle = host == "google.com" || host.hasPrefix("google.") || host.hasPrefix("www.google.")
        return isGoogle && path.hasPrefix("/maps")
    }

    /// Exactly "lat,lon" or "lat, lon" (the whole string), with sane ranges.
    static func plainCoordinate(in text: String) -> Coordinate? {
        guard let match = text.wholeMatch(of: /\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*/) else {
            return nil
        }
        return makeCoordinate(match.1, match.2)
    }

    static func makeCoordinate(_ lat: Substring, _ lon: Substring) -> Coordinate? {
        guard let latitude = Double(lat), let longitude = Double(lon) else { return nil }
        let c = Coordinate(latitude: latitude, longitude: longitude)
        return c.isValid ? c : nil
    }

    static func firstURL(in text: String) -> URL? {
        guard let match = text.firstMatch(of: /https?:\/\/[^\s<>"]+/) else { return nil }
        return URL(string: String(match.0))
    }
}
