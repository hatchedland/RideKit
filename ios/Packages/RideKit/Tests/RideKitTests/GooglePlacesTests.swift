import Foundation
import Testing
@testable import RideKit

@Suite("Google Places")
struct GooglePlacesTests {
    let mandya = Coordinate(latitude: 12.5218, longitude: 76.8951)

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func nearbyRequestIsRestrictedAndRankedByDistance() throws {
        let request = GooglePlaces.nearbyRequest(around: mandya, radius: 150, apiKey: "KEY", bundleID: "com.example.app")
        #expect(request.url == GooglePlaces.nearbyURL)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == "KEY")
        #expect(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") == "com.example.app")
        #expect(request.value(forHTTPHeaderField: "X-Goog-FieldMask")?.contains("places.displayName") == true)
        let json = try body(request)
        #expect(json["rankPreference"] as? String == "DISTANCE")
        #expect(json["maxResultCount"] as? Int == 10)
        let circle = try #require((json["locationRestriction"] as? [String: Any])?["circle"] as? [String: Any])
        #expect(circle["radius"] as? Double == 150)
        let center = try #require(circle["center"] as? [String: Double])
        #expect(center["latitude"] == 12.5218 && center["longitude"] == 76.8951)
    }

    @Test func nearbyNamesOnlyComeFromPlacesRidersStopAt() throws {
        let json = try body(GooglePlaces.nearbyRequest(around: mandya, radius: 150, apiKey: "K", bundleID: "b"))
        let types = try #require(json["includedTypes"] as? [String])
        #expect(types.contains("gas_station") && types.contains("hindu_temple") && types.contains("tea_house"))
        #expect(!types.contains("bank") && !types.contains("doctor"))
        // Every type the filter allows lands in a real category or is a general attraction.
        for type in types {
            #expect(GooglePlaces.spotCategory(primaryType: type, types: []) != "other", "\(type) has no category")
        }
        let unfiltered = try body(GooglePlaces.nearbyRequest(around: mandya, radius: 150, types: [], apiKey: "K", bundleID: "b"))
        #expect(unfiltered["includedTypes"] == nil)
    }

    @Test func requestLimitsAreClamped() throws {
        let json = try body(GooglePlaces.nearbyRequest(around: mandya, radius: 999_999, maxResults: 99, apiKey: "K", bundleID: "b"))
        #expect(json["maxResultCount"] as? Int == 20)
        let circle = try #require((json["locationRestriction"] as? [String: Any])?["circle"] as? [String: Any])
        #expect(circle["radius"] as? Double == 50_000)
    }

    @Test func textRequestBiasesTowardsTheRider() throws {
        let json = try body(GooglePlaces.textRequest("Zostel Ooty", near: mandya, apiKey: "K", bundleID: "b", languageCode: "hi"))
        #expect(json["textQuery"] as? String == "Zostel Ooty")
        #expect(json["languageCode"] as? String == "hi")
        #expect(json["locationBias"] != nil)
        let anywhere = try body(GooglePlaces.textRequest("Spiti", near: nil, apiKey: "K", bundleID: "b"))
        #expect(anywhere["locationBias"] == nil)
    }

    @Test func parsesPlacesAndSkipsBrokenEntries() throws {
        let json = """
        {"places":[
          {"displayName":{"text":"HP Petrol Pump","languageCode":"en"},"location":{"latitude":12.52,"longitude":76.89},
           "primaryType":"gas_station","types":["gas_station","point_of_interest"],"shortFormattedAddress":"Mysore Rd, Mandya"},
          {"displayName":{"text":"  "},"location":{"latitude":1,"longitude":2}},
          {"displayName":{"text":"No location"}},
          {"displayName":{"text":"Bad"},"location":{"latitude":123,"longitude":2}}
        ]}
        """
        let places = try GooglePlaces.places(from: Data(json.utf8))
        #expect(places.count == 1)
        let pump = try #require(places.first)
        #expect(pump.name == "HP Petrol Pump")
        #expect(pump.coordinate == Coordinate(latitude: 12.52, longitude: 76.89))
        #expect(pump.address == "Mysore Rd, Mandya")
        #expect(pump.spotCategory == "fuel")
    }

    @Test func emptyAnswerMeansNoPlaces() throws {
        #expect(try GooglePlaces.places(from: Data("{}".utf8)).isEmpty)
        #expect(throws: (any Error).self) { try GooglePlaces.places(from: Data("not json".utf8)) }
    }

    @Test func errorMessageComesFromGoogle() {
        let data = Data(#"{"error":{"code":403,"message":"Requests from this iOS client application are blocked.","status":"PERMISSION_DENIED"}}"#.utf8)
        #expect(GooglePlaces.error(status: 403, data: data) == .init(status: 403, message: "Requests from this iOS client application are blocked."))
        #expect(GooglePlaces.error(status: 500, data: Data()).message == "HTTP 500")
    }

    @Test(arguments: [
        ("gas_station", [String](), "fuel"),
        ("south_indian_restaurant", [], "food"),
        ("tea_house", [], "food"),
        ("hindu_temple", ["tourist_attraction"], "monument"),
        ("tourist_attraction", [], "viewpoint"),
        ("observation_deck", [], "viewpoint"),
        ("lodging", [], "stay"),
        ("car_repair", [], "mechanic"),
        ("national_park", [], "nature"),
        ("car_wash", [], "other"),
    ])
    func categoriesForRiders(primary: String, types: [String], expected: String) {
        #expect(GooglePlaces.spotCategory(primaryType: primary, types: types) == expected)
    }

    @Test func secondaryTypesCountWhenThePrimaryIsGeneric() {
        #expect(GooglePlaces.spotCategory(primaryType: "point_of_interest", types: ["point_of_interest", "waterfall"]) == "nature")
        #expect(GooglePlaces.spotCategory(primaryType: nil, types: []) == "other")
    }
}
