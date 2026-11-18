import Foundation

/// Names for rides, which are also the names of their Photos albums.
public enum RideNaming {

    /// The final name for a ride started with `input` as typed by the rider.
    ///
    /// - Empty input → "Ride · 12 Oct 2026", so starting a ride is never blocked.
    /// - A name already used by another ride gets the date added, then a counter if still taken.
    public static func resolve(
        _ input: String,
        startedAt date: Date,
        existingNames: some Collection<String>,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")   // "/" reads like a folder path in Photos
        let dateText = formattedDate(date, calendar: calendar, locale: locale)
        let taken = Set(existingNames.map { $0.lowercased() })

        let base = trimmed.isEmpty ? "Ride · \(dateText)" : trimmed
        if !taken.contains(base.lowercased()) { return base }

        // A name that already ends with today's date (e.g. picked from suggestions) isn't dated twice.
        let alreadyDated = trimmed.lowercased().hasSuffix(" · \(dateText)".lowercased())
        let dated = trimmed.isEmpty || alreadyDated ? base : "\(trimmed) · \(dateText)"
        if !taken.contains(dated.lowercased()) { return dated }

        var counter = 2
        while taken.contains("\(dated) (\(counter))".lowercased()) { counter += 1 }
        return "\(dated) (\(counter))"
    }

    /// Suggestions under the name field: recent ride names first, then wishlist spot names,
    /// filtered by what's been typed, without duplicates.
    public static func suggestions(
        for input: String,
        recentRideNames: [String],
        wishlistSpotNames: [String],
        limit: Int = 6
    ) -> [String] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<String>()
        var result: [String] = []
        for name in recentRideNames + wishlistSpotNames {
            let key = name.lowercased()
            guard !name.isEmpty, !seen.contains(key) else { continue }
            guard query.isEmpty || key.contains(query) else { continue }
            guard key != query else { continue }
            seen.insert(key)
            result.append(name)
            if result.count == limit { break }
        }
        return result
    }

    static func formattedDate(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        return date.formatted(style.day().month(.abbreviated).year())
    }
}
