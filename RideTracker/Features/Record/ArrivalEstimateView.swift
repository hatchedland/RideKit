import RideKit
import SwiftData
import SwiftUI

/// "4 h 40 with your usual breaks · Arrive around 3:10 pm · Sunset 6:02 pm" — Google's road time
/// made honest with the rider's own pace and stops (`RideTimePlan`), and a daylight check. Shown
/// before the ride only (route preview, Start sheet); nothing to look at while riding.
struct ArrivalEstimateView: View {
    let destination: RideDestination
    let route: RideRoute
    /// The route preview leads with big numbers; the Start sheet already shows the place.
    var prominent = true

    @Query(sort: \Ride.startedAt, order: .reverse) private var rides: [Ride]

    private var pace: RidePace {
        RidePace.learn(from: rides.map {
            RidePace.Sample(distanceMeters: $0.distanceMeters, movingSeconds: $0.movingSeconds, elapsedSeconds: $0.duration)
        })
    }

    var body: some View {
        // Re-worked every minute, so "leave by" stays true while the sheet is open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let plan = RideTimePlan(departure: context.date, distanceMeters: route.distanceMeters,
                                    roadSeconds: route.durationSeconds, destination: destination.coordinate, pace: pace)
            VStack(alignment: .leading, spacing: 6) {
                if prominent {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(Format.distance(route.distanceMeters)).font(Brand.stat)
                        Text(Format.roadTime(plan.totalSeconds)).font(Brand.stat).foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(Format.distance(route.distanceMeters)) by road · \(Format.roadTime(plan.totalSeconds))")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                Text(Self.paceLine(plan))
                    .font(.footnote).foregroundStyle(.secondary)
                Label {
                    Text(Self.arrivalLine(plan, now: context.date))
                } icon: {
                    Image(systemName: plan.arrivesAfterDark ? "moon.fill" : "sun.horizon.fill")
                }
                .font(.subheadline)
                if plan.arrivesAfterDark {
                    Text(Self.darkLine(plan, now: context.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.signal)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Copy

    static func paceLine(_ plan: RideTimePlan) -> String {
        let breaks = Format.roadTime(plan.breakSeconds)
        if plan.pace.rideCount == 0 {
            return "Includes about \(breaks) of breaks. It learns your pace as you ride."
        }
        return "With your usual breaks (about \(breaks)), from your last \(plan.pace.rideCount) rides."
    }

    static func arrivalLine(_ plan: RideTimePlan, now: Date) -> String {
        var line = "Arrive around \(time(plan.arrival, now: now))"
        if let sunset = plan.sunset { line += " · Sunset \(time(sunset, now: now))" }
        return line
    }

    static func darkLine(_ plan: RideTimePlan, now: Date) -> String {
        if plan.canStillArriveInDaylight, let leaveBy = plan.latestDeparture {
            return "After dark. Leave by \(time(leaveBy, now: now)) to arrive in daylight."
        }
        return "After dark. Ride with care, or plan a stay on the way."
    }

    /// "3:10 pm", or "Sat 1:10 am" when it isn't today.
    static func time(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
