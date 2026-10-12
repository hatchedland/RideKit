import RideKit
import SwiftData
import SwiftUI

/// Shown when a ride ends: stats, the album, spots to name, wishlist visits (with Undo) and
/// photos taken just before Start or after End.
struct RideSummaryView: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @Bindable var ride: Ride

    @State private var edge: (before: [MediaCandidate], after: [MediaCandidate]) = ([], [])
    @State private var autoVisited: [Spot] = []

    var body: some View {
        List {
            Section {
                RideStatsGrid(ride: ride)
            }

            Section("Photos album") {
                Label {
                    Text("\(ride.media?.count ?? 0) photos & videos in “\(ride.name)”")
                } icon: {
                    Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.purple)
                }
                if ride.albumLocalIdentifier == nil {
                    Text("No album was created because Ride Tracker doesn't have full access to Photos. You can allow it in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !edge.before.isEmpty {
                    Button("Add \(edge.before.count) taken in the 30 min before Start") {
                        add(edge.before)
                    }
                }
                if !edge.after.isEmpty {
                    Button("Add \(edge.after.count) taken in the 30 min after End") {
                        add(edge.after)
                    }
                }
            }

            if !autoVisited.isEmpty {
                Section {
                    ForEach(autoVisited) { spot in
                        HStack {
                            Label(spot.displayName, systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Undo") {
                                recorder.undoAutoVisit(spot, ride: ride)
                                autoVisited.removeAll { $0.id == spot.id }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text("Wishlist visited 🎉")
                } footer: {
                    Text("You stopped or took photos within \(Int(AppSettings.spotRadius)) m of these.")
                }
            }

            if let spots = ride.spots, !spots.isEmpty {
                Section("Spots you marked") {
                    ForEach(spots.sorted { $0.createdAt < $1.createdAt }) { spot in
                        NavigationLink(value: spot) {
                            SpotRow(spot: spot)
                        }
                    }
                }
            }

            SoundtrackSection(ride: ride)
        }
        .navigationTitle(ride.name)
        .navigationDestination(for: Spot.self) { SpotDetailView(spot: $0) }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            edge = recorder.edgeCandidates(for: ride)
            let ids = Set(recorder.autoVisitedSpotIDs)
            autoVisited = ((try? recorder.context.fetch(FetchDescriptor<Spot>())) ?? []).filter { ids.contains($0.id) }
        }
    }

    private func add(_ items: [MediaCandidate]) {
        Task {
            await recorder.addToRide(items, ride: ride)
            edge = recorder.edgeCandidates(for: ride)
        }
    }
}

struct RideStatsGrid: View {
    let ride: Ride

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 14) {
            GridRow {
                cell(Format.distance(ride.distanceMeters), "Distance", "road.lanes")
                cell(Format.duration(ride.duration), "Total time", "clock")
            }
            GridRow {
                cell(Format.duration(ride.movingSeconds), "Moving time", "gauge.with.dots.needle.33percent")
                cell("\(Format.speed(ride.avgMovingSpeedMps)) \(Format.speedUnit())", "Avg moving", "speedometer")
            }
            GridRow {
                cell("\(Format.speed(ride.maxSpeedMps)) \(Format.speedUnit())", "Top speed", "bolt.fill")
                cell(Format.elevation(ride.elevationGainMeters), "Climb", "mountain.2.fill")
            }
        }
        .padding(.vertical, 6)
    }

    private func cell(_ value: String, _ label: String, _ image: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: image).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
