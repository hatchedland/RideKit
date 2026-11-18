import Foundation

/// A marketing version like "1.2.0", compared part by part ("1.10" > "1.9"; "1.2" == "1.2.0").
/// Anything after the numbers ("1.3.0-beta", "2.0 (45)") is ignored.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var parts: [Int] = []
        for piece in text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false) {
            let digits = piece.prefix { $0.isASCII && $0.isNumber }
            guard let value = Int(digits) else { break }
            parts.append(value)
            if digits.count < piece.count { break }
        }
        guard !parts.isEmpty else { return nil }
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    /// The server's `app_config.min_version` says this build is too old to sync safely.
    /// Unreadable versions never block: a typo on the server must not lock riders out.
    public static func needsUpdate(current: String, minimum: String?) -> Bool {
        guard let minimum, let min = AppVersion(minimum), let now = AppVersion(current) else { return false }
        return now < min
    }
}
