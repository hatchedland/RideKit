import RideKit
import SwiftUI

/// Directions inside the app: the road to a spot on the map, how far and how long, and one button
/// that starts a ride with the spot as the destination. The riding screen then shows the road
/// ahead and what's left (decided 2026-11-17; replaces handing off to the Google Maps app).
struct RoutePreviewSheet: View {
    let destination: RideDestination
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var here: Coordinate?
    @State private var route: RideRoute?
    @State private var loading = true
    @State private var starting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GoogleMapView(
                    lines: route.map { [MapLine(id: "route", coordinates: $0.coordinates, color: Brand.highwayYellow, width: 6)] } ?? [],
                    pins: pins,
                    camera: .fitContent,
                    look: .muted,
                    padding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
                )
                .id(route?.coordinates.count ?? 0) // Refit once the route arrives.

                VStack(alignment: .leading, spacing: 16) {
                    summary
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Brand.signal)
                    }
                    Button {
                        start()
                    } label: {
                        Label("Start ride", systemImage: "play.fill")
                            .font(.title2.bold().width(.expanded))
                            .foregroundStyle(Brand.asphalt)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.highwayYellow)
                    .disabled(starting || recorder.phase != .idle)
                }
                .padding(16)
                .background(Brand.page)
            }
            .navigationTitle(destination.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task {
            here = await CurrentLocation.once()
            if let here {
                route = await GooglePlacesClient.app.route(from: here, to: destination.coordinate)
            }
            loading = false
        }
    }

    private var pins: [MapPin] {
        var pins = [MapPin(id: "destination", coordinate: destination.coordinate, title: destination.name,
                           systemImage: "flag.checkered", tint: Brand.highwayYellow)]
        if let here {
            pins.append(MapPin(id: "here", coordinate: here, title: "You", systemImage: "location.fill",
                               tint: Brand.chalk, style: .rider, showsLabel: false))
        }
        return pins
    }

    @ViewBuilder
    private var summary: some View {
        if loading {
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 160, height: 28)
                SkeletonBlock(width: 220, height: 14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Finding the route")
        } else if let route {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(Format.distance(route.distanceMeters)).font(Brand.stat)
                    Text(Format.roadTime(route.durationSeconds)).font(Brand.stat).foregroundStyle(.secondary)
                }
                Text("By road from where you are. The ride shows the way and what's left.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if let here {
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.distance(destination.remainingDistance(from: here))).font(Brand.stat)
                Text("In a straight line — no road route right now (offline?). You can still ride there.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Turn on location to see the route. You can still start the ride.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func start() {
        starting = true
        error = nil
        Task {
            do {
                try await recorder.start(name: RideNaming.name(goingTo: destination), destination: destination)
                dismiss() // The app switches to the riding screen on its own.
            } catch {
                self.error = "Couldn't start the ride. \(error.localizedDescription)"
            }
            starting = false
        }
    }
}
