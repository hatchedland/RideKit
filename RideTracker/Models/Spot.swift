import Foundation
import RideKit
import SwiftData

enum SpotStatus: String, Codable, CaseIterable, Identifiable {
    case wantToGo
    case visited

    var id: Self { self }

    var title: String {
        switch self {
        case .wantToGo: "Want to go"
        case .visited: "Visited"
        }
    }

    var systemImage: String {
        switch self {
        case .wantToGo: "star"
        case .visited: "checkmark.seal.fill"
        }
    }
}

enum SpotCategory: String, Codable, CaseIterable, Identifiable {
    case viewpoint, food, fuel, monument, stay, mechanic, nature, other

    var id: Self { self }

    var title: String {
        switch self {
        case .viewpoint: "Viewpoint"
        case .food: "Food & chai"
        case .fuel: "Fuel"
        case .monument: "Temple / monument"
        case .stay: "Stay"
        case .mechanic: "Mechanic"
        case .nature: "Lake / waterfall"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .viewpoint: "binoculars.fill"
        case .food: "cup.and.saucer.fill"
        case .fuel: "fuelpump.fill"
        case .monument: "building.columns.fill"
        case .stay: "bed.double.fill"
        case .mechanic: "wrench.and.screwdriver.fill"
        case .nature: "drop.fill"
        case .other: "mappin"
        }
    }
}

/// A place the rider marked or wants to visit. Every spot keeps its Google Maps link.
///
/// CloudKit rules apply to every model: no unique constraints, every property has a default
/// or is optional, and every relationship is optional.
@Model
final class Spot {
    var id: UUID = UUID()
    var name: String = ""
    /// True while `name` is still an automatic suggestion the rider hasn't confirmed.
    var nameIsSuggested: Bool = false
    var notes: String = ""
    var categoryRaw: String = SpotCategory.other.rawValue
    var statusRaw: String = SpotStatus.visited.rawValue
    var rating: Int?
    /// Wishlist only: 1 (low) – 3 (high).
    var priority: Int?
    /// Wishlist only, free text, e.g. "May – June".
    var bestSeason: String?

    var latitude: Double = 0
    var longitude: Double = 0
    var altitude: Double?
    var address: String?
    /// City / area, used to group the Places view.
    var locality: String?

    /// Normalised coordinate link, always present.
    var googleMapsURL: String = ""
    /// The Google Maps link exactly as pasted, if the spot came from one.
    var sourceURL: String?

    var createdAt: Date = Date.now
    var visits: [Date] = []
    /// Set when a ride auto-marked this wishlist spot as visited, so the summary can offer "Undo".
    var autoVisitedByRideID: UUID?

    var ride: Ride?
    @Relationship(deleteRule: .cascade, inverse: \MediaLink.spot) var media: [MediaLink]? = []

    init(
        name: String = "",
        coordinate: Coordinate,
        status: SpotStatus,
        category: SpotCategory = .other,
        sourceURL: String? = nil
    ) {
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.statusRaw = status.rawValue
        self.categoryRaw = category.rawValue
        self.sourceURL = sourceURL
        self.googleMapsURL = GoogleMapsLink.url(for: coordinate).absoluteString
        if status == .visited { visits = [.now] }
    }

    var coordinate: Coordinate {
        get { Coordinate(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
            googleMapsURL = GoogleMapsLink.url(for: newValue).absoluteString
        }
    }

    var status: SpotStatus {
        get { SpotStatus(rawValue: statusRaw) ?? .visited }
        set { statusRaw = newValue.rawValue }
    }

    var category: SpotCategory {
        get { SpotCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var displayName: String {
        if !name.isEmpty { return name }
        if let address, !address.isEmpty { return address }
        return "Spot at \(coordinate.queryString)"
    }

    var reference: SpotReference { SpotReference(id: id, coordinate: coordinate) }

    var lastVisit: Date? { visits.max() }

    func markVisited(on date: Date, byRide rideID: UUID? = nil) {
        status = .visited
        if !visits.contains(date) { visits.append(date) }
        autoVisitedByRideID = rideID
    }

    /// Undoes an automatic visit from `rideID`, returning the spot to the wishlist.
    func undoAutoVisit(fromRide rideID: UUID, on date: Date) {
        guard autoVisitedByRideID == rideID else { return }
        visits.removeAll { $0 == date }
        autoVisitedByRideID = nil
        if visits.isEmpty { status = .wantToGo }
    }
}
