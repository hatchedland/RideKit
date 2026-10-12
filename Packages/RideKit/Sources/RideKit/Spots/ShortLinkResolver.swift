import Foundation

/// Expands `maps.app.goo.gl/…` share links by following their redirects, then parses the final URL.
public struct ShortLinkResolver: Sendable {
    /// Returns the final URL after redirects. Injected so tests don't hit the network.
    public typealias Fetch = @Sendable (URL) async throws -> URL

    private let fetch: Fetch

    public init(fetch: @escaping Fetch = ShortLinkResolver.followRedirects) {
        self.fetch = fetch
    }

    public enum ResolveError: Error, Equatable {
        case noCoordinates(finalURL: URL)
    }

    /// Parses `input`, resolving a short link if needed.
    /// Returns `nil` when the text isn't a Google Maps link at all.
    public func coordinate(from input: String) async throws -> Coordinate? {
        switch GoogleMapsLink.parse(input) {
        case .coordinate(let c):
            return c
        case .unrecognized:
            return nil
        case .needsResolution(let shortURL):
            let finalURL = try await fetch(shortURL)
            if let c = GoogleMapsLink.coordinate(inGoogleMapsURL: finalURL) {
                return c
            }
            throw ResolveError.noCoordinates(finalURL: finalURL)
        }
    }

    @Sendable public static func followRedirects(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        // A desktop UA makes Google redirect to the full /maps/place/… URL instead of an app interstitial.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        return response.url ?? url
    }
}
