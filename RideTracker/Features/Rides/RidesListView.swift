import SwiftData
import SwiftUI

struct RidesListView: View {
    @Query(sort: \Ride.startedAt, order: .reverse) private var rides: [Ride]
    @Environment(RideRecorder.self) private var recorder

    private var finished: [Ride] {
        rides.filter { $0.id != recorder.active?.id }
    }

    private var byMonth: [(month: Date, rides: [Ride])] {
        let calendar = Calendar.current
        return Dictionary(grouping: finished) { calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt }
            .map { ($0.key, $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(byMonth, id: \.month) { group in
                    Section {
                        ForEach(group.rides) { ride in
                            NavigationLink(value: ride) { RideRow(ride: ride) }
                        }
                    } header: {
                        let total = group.rides.reduce(0) { $0 + $1.distanceMeters }
                        Text("\(group.month.formatted(.dateTime.month(.wide).year())) · \(Format.distance(total))")
                    }
                }
            }
            .overlay {
                if finished.isEmpty {
                    ContentUnavailableView("No rides yet", systemImage: "road.lanes",
                                           description: Text("Your rides, their spots and photo albums show up here."))
                }
            }
            .navigationTitle("Rides")
            .navigationDestination(for: Ride.self) { RideDetailView(ride: $0) }
            .navigationDestination(for: Spot.self) { SpotDetailView(spot: $0) }
        }
    }
}

struct RideRow: View {
    let ride: Ride

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ride.name).font(.headline)
            HStack(spacing: 10) {
                Text(ride.startedAt.formatted(date: .abbreviated, time: .shortened))
                Label(Format.distance(ride.distanceMeters), systemImage: "road.lanes")
                if let spots = ride.spots, !spots.isEmpty {
                    Label("\(spots.count)", systemImage: "mappin")
                }
                if let media = ride.media, !media.isEmpty {
                    Label("\(media.count)", systemImage: "photo")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
