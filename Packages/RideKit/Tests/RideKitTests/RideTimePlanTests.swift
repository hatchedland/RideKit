import Foundation
import Testing
@testable import RideKit

@Suite("Ride time plan")
struct RideTimePlanTests {
    let delhi = Fixtures.indiaGate
    /// 15 Mar 2026, 06:30 UTC = noon in Delhi; sunset there is around 18:30 IST (13:00 UTC).
    let noon = Date(timeIntervalSince1970: 1_773_556_200)

    func ride(km: Double, movingMin: Double, elapsedMin: Double) -> RidePace.Sample {
        RidePace.Sample(distanceMeters: km * 1000, movingSeconds: movingMin * 60, elapsedSeconds: elapsedMin * 60)
    }

    // MARK: Pace

    @Test func defaultsWithoutHistory() {
        #expect(RidePace.learn(from: []) == .default)
        // One ride isn't a habit.
        #expect(RidePace.learn(from: [ride(km: 100, movingMin: 120, elapsedMin: 150)]) == .default)
    }

    @Test func shortRidesAreIgnored() {
        let pace = RidePace.learn(from: [ride(km: 5, movingMin: 15, elapsedMin: 40), ride(km: 8, movingMin: 25, elapsedMin: 30),
                                         ride(km: 15, movingMin: 10, elapsedMin: 12)])
        #expect(pace == .default)
    }

    @Test func learnsDistanceWeightedSpeedAndMedianStops() {
        let pace = RidePace.learn(from: [
            ride(km: 120, movingMin: 120, elapsedMin: 160),  // 60 km/h, 25% stopped
            ride(km: 60, movingMin: 90, elapsedMin: 100),    // 40 km/h, 10% stopped
            ride(km: 30, movingMin: 30, elapsedMin: 40),     // 60 km/h, 25% stopped
        ])
        #expect(pace.rideCount == 3)
        // 210 km in 240 min = 52.5 km/h.
        #expect(abs((pace.movingSpeedMps ?? 0) * 3.6 - 52.5) < 0.01)
        #expect(abs(pace.stopShare - 0.25) < 0.0001)
    }

    @Test func stopShareIsClampedAndEvenCountsAverageTheMiddle() {
        let pace = RidePace.learn(from: [
            ride(km: 50, movingMin: 60, elapsedMin: 60),     // 0% → 5%
            ride(km: 50, movingMin: 60, elapsedMin: 600),    // forgot to end → 45%
        ])
        #expect(abs(pace.stopShare - 0.25) < 0.0001)
    }

    @Test func onlyRecentRidesCount() {
        let recent = (0..<RidePace.recentRides).map { _ in ride(km: 100, movingMin: 100, elapsedMin: 120) }
        let old = ride(km: 1000, movingMin: 2000, elapsedMin: 2400) // 30 km/h, would drag the speed down
        let pace = RidePace.learn(from: recent + [old])
        #expect(pace.rideCount == RidePace.recentRides)
        #expect(abs((pace.movingSpeedMps ?? 0) * 3.6 - 60) < 0.01)
    }

    // MARK: Plan

    @Test func defaultPaceAddsBreaksToGooglesTime() {
        let plan = RideTimePlan(departure: noon, distanceMeters: 100_000, roadSeconds: 6000, destination: delhi, pace: .default)
        #expect(plan.movingSeconds == 6000)
        #expect(abs(plan.breakSeconds - 6000 * 0.15 / 0.85) < 0.001)
        #expect(plan.arrival == noon.addingTimeInterval(plan.totalSeconds))
    }

    @Test func slowerRiderGetsAnHonestTime() {
        // Google: 100 km in 1 h 20. This rider averages 40 km/h → 2 h 30 alone; the average is 1 h 55.
        let pace = RidePace(movingSpeedMps: 40 / 3.6, stopShare: 0.2, rideCount: 10)
        let plan = RideTimePlan(departure: noon, distanceMeters: 100_000, roadSeconds: 4800, destination: delhi, pace: pace)
        #expect(abs(plan.movingSeconds - (4800 + 9000) / 2) < 0.001)
        #expect(abs(plan.breakSeconds - plan.movingSeconds * 0.25) < 0.001)
    }

    @Test func neverFasterThanGoogleNorAbsurdlySlower() {
        let fast = RidePace(movingSpeedMps: 150 / 3.6, stopShare: 0.1, rideCount: 5)
        #expect(RideTimePlan(departure: noon, distanceMeters: 100_000, roadSeconds: 4800, destination: delhi, pace: fast)
            .movingSeconds == 4800)
        let crawl = RidePace(movingSpeedMps: 5 / 3.6, stopShare: 0.1, rideCount: 5)
        #expect(RideTimePlan(departure: noon, distanceMeters: 100_000, roadSeconds: 4800, destination: delhi, pace: crawl)
            .movingSeconds == 4800 * RideTimePlan.slowestFactor)
    }

    @Test func daylightArrivalAndLeaveBy() throws {
        let plan = RideTimePlan(departure: noon, distanceMeters: 100_000, roadSeconds: 3600 * 2, destination: delhi, pace: .default)
        let sunset = try #require(plan.sunset)
        #expect(Calendar(identifier: .gregorian).isDate(sunset, inSameDayAs: noon))
        #expect(!plan.arrivesAfterDark)
        let leaveBy = try #require(plan.latestDeparture)
        #expect(abs(leaveBy.addingTimeInterval(plan.totalSeconds + RideTimePlan.daylightMargin).timeIntervalSince(sunset)) < 0.001)
        #expect(plan.canStillArriveInDaylight)
    }

    @Test func lateStartArrivesAfterDark() {
        let plan = RideTimePlan(departure: noon, distanceMeters: 400_000, roadSeconds: 3600 * 7, destination: delhi, pace: .default)
        #expect(plan.arrivesAfterDark)
        #expect(!plan.canStillArriveInDaylight)
    }

    @Test func nightDepartureFindsThatEveningsSunset() {
        // 23:00 IST: arriving after midnight must not find the next day's sunset and call it daylight.
        let night = noon.addingTimeInterval(11 * 3600)
        let plan = RideTimePlan(departure: night, distanceMeters: 100_000, roadSeconds: 3 * 3600, destination: delhi, pace: .default)
        #expect(plan.arrivesAfterDark)
    }

    @Test func multiDayRideHasNoSunsetVerdict() {
        let plan = RideTimePlan(departure: noon, distanceMeters: 1_500_000, roadSeconds: 20 * 3600, destination: delhi, pace: .default)
        #expect(plan.sunset == nil)
        #expect(plan.latestDeparture == nil)
        #expect(!plan.arrivesAfterDark)
        #expect(plan.canStillArriveInDaylight)
    }
}
