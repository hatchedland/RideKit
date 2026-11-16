import Foundation

/// A place from Google Places, as the app uses it: suggested spot names, nearby landmarks and
/// "Where to?" search results.
public struct Place: Hashable, Sendable {
    public var name: String
    public var coordinate: Coordinate
    /// Google's main type for it, e.g. "gas_station" or "hindu_temple".
    public var primaryType: String?
    public var types: [String]
    /// "MG Road, Mandya": short enough for a list row.
    public var address: String?

    public init(name: String, coordinate: Coordinate, primaryType: String? = nil, types: [String] = [], address: String? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.primaryType = primaryType
        self.types = types
        self.address = address
    }

    /// The `SpotCategory` raw value this place belongs in ("fuel", "food", …, "other").
    public var spotCategory: String { GooglePlaces.spotCategory(primaryType: primaryType, types: types) }
}

/// Google Places API (New): building the two requests the app makes, and reading the answers.
/// Pure, so it's tested without the network; `GooglePlacesClient` in the app sends them.
///
/// Only the fields the app shows are requested (the field mask), which also keeps each call in the
/// cheapest SKU that has names. The key is an iOS key restricted to the app's bundle id, which
/// Google checks through the `X-Ios-Bundle-Identifier` header.
public enum GooglePlaces {
    public static let nearbyURL = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
    public static let textURL = URL(string: "https://places.googleapis.com/v1/places:searchText")!
    static let fieldMask = "places.displayName,places.location,places.primaryType,places.types,places.shortFormattedAddress"

    /// Places riders stop at. Nearby search without this names spots after banks, clinics and
    /// housing societies. All are Google "Table A" types (others make the request fail).
    public static let riderTypes = [
        "gas_station", "electric_vehicle_charging_station",
        "restaurant", "cafe", "coffee_shop", "tea_house", "bakery", "fast_food_restaurant", "food_court", "meal_takeaway",
        "lodging", "hotel", "motel", "hostel", "guest_house", "campground", "resort_hotel",
        "hindu_temple", "church", "mosque", "buddhist_temple",
        "historical_landmark", "historical_place", "monument", "museum", "cultural_landmark",
        "tourist_attraction", "observation_deck", "national_park", "state_park", "park", "hiking_area", "beach",
        "car_repair",
    ]

    /// Places of `types` within `radius` meters of `center`, nearest first (suggested names).
    public static func nearbyRequest(
        around center: Coordinate, radius: Double, maxResults: Int = 10, types: [String] = riderTypes,
        apiKey: String, bundleID: String, languageCode: String = "en"
    ) -> URLRequest {
        var body: [String: Any] = [
            "maxResultCount": max(1, min(20, maxResults)),
            "rankPreference": "DISTANCE",
            "languageCode": languageCode,
            "locationRestriction": ["circle": ["center": point(center), "radius": max(1, min(50_000, radius))]],
        ]
        if !types.isEmpty { body["includedTypes"] = types }
        return request(nearbyURL, body: body, apiKey: apiKey, bundleID: bundleID)
    }

    /// Places matching `query`, preferring ones near `near` ("Where to?", adding a wishlist spot).
    public static func textRequest(
        _ query: String, near: Coordinate?, maxResults: Int = 8,
        apiKey: String, bundleID: String, languageCode: String = "en"
    ) -> URLRequest {
        var body: [String: Any] = [
            "textQuery": query,
            "maxResultCount": max(1, min(20, maxResults)),
            "languageCode": languageCode,
        ]
        if let near {
            // 50 km is the largest bias Google accepts; far places still come back, just lower.
            body["locationBias"] = ["circle": ["center": point(near), "radius": 50_000.0]]
        }
        return request(textURL, body: body, apiKey: apiKey, bundleID: bundleID)
    }

    private static func point(_ c: Coordinate) -> [String: Double] {
        ["latitude": c.latitude, "longitude": c.longitude]
    }

    private static func request(_ url: URL, body: [String: Any], apiKey: String, bundleID: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // MARK: Responses

    private struct Response: Decodable {
        struct Item: Decodable {
            struct Text: Decodable { var text: String? }
            struct Location: Decodable { var latitude: Double?; var longitude: Double? }
            var displayName: Text?
            var location: Location?
            var primaryType: String?
            var types: [String]?
            var shortFormattedAddress: String?
        }
        var places: [Item]?
    }

    public struct APIError: Error, Equatable, Sendable {
        public var status: Int
        public var message: String
    }

    /// Places from a response body. Google sends `{}` when nothing matches; entries without a name
    /// or a valid location are skipped.
    public static func places(from data: Data) throws -> [Place] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.places ?? []).compactMap { item in
            guard let name = item.displayName?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let lat = item.location?.latitude, let lon = item.location?.longitude else { return nil }
            let coordinate = Coordinate(latitude: lat, longitude: lon)
            guard coordinate.isValid else { return nil }
            return Place(name: name, coordinate: coordinate, primaryType: item.primaryType,
                         types: item.types ?? [], address: item.shortFormattedAddress)
        }
    }

    /// Google's error message from a failed call, for logs ("API key not valid…").
    public static func error(status: Int, data: Data) -> APIError {
        struct Body: Decodable { struct E: Decodable { var message: String? }; var error: E? }
        let message = (try? JSONDecoder().decode(Body.self, from: data))?.error?.message ?? "HTTP \(status)"
        return APIError(status: status, message: message)
    }

    // MARK: Categories

    /// Google place types → the app's spot categories, checked in this order so a temple that is
    /// also a tourist attraction stays a monument.
    private static let categories: [(category: String, types: Set<String>)] = [
        ("fuel", ["gas_station", "electric_vehicle_charging_station"]),
        ("mechanic", ["car_repair", "motorcycle_repair", "auto_parts_store", "tire_shop"]),
        ("stay", ["lodging", "hotel", "motel", "hostel", "guest_house", "campground", "camping_cabin",
                  "resort_hotel", "bed_and_breakfast", "farmstay", "cottage", "inn", "extended_stay_hotel"]),
        ("monument", ["hindu_temple", "church", "mosque", "synagogue", "buddhist_temple", "place_of_worship",
                      "historical_landmark", "historical_place", "monument", "museum", "cultural_landmark", "castle"]),
        ("nature", ["national_park", "state_park", "park", "hiking_area", "beach", "lake", "river",
                    "waterfall", "natural_feature", "botanical_garden", "wildlife_park", "wildlife_refuge"]),
        ("viewpoint", ["observation_deck", "scenic_spot", "tourist_attraction", "vista_point"]),
        ("food", ["restaurant", "cafe", "coffee_shop", "tea_house", "bakery", "food_court", "meal_takeaway",
                  "fast_food_restaurant", "dessert_shop", "juice_shop", "snack_bar", "diner", "food"]),
    ]

    public static func spotCategory(primaryType: String?, types: [String]) -> String {
        let candidates = [primaryType].compactMap { $0 } + types
        for type in candidates {
            if let match = categories.first(where: { $0.types.contains(type) }) { return match.category }
            // Google has dozens of "<cuisine>_restaurant" types.
            if type.hasSuffix("_restaurant") { return "food" }
        }
        return "other"
    }
}
