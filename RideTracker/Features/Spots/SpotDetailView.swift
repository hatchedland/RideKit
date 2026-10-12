import MapKit
import RideKit
import SwiftData
import SwiftUI

struct SpotDetailView: View {
    @Bindable var spot: Spot
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var confirmingDelete = false
    @State private var landmarkSuggestions: [String] = []

    var body: some View {
        List {
            Section {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: spot.coordinate.clCoordinate, distance: 1_500))) {
                    Marker(spot.displayName, systemImage: spot.category.systemImage, coordinate: spot.coordinate.clCoordinate)
                        .tint(spot.status == .wantToGo ? .yellow : .red)
                }
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
                .allowsHitTesting(false)
            }

            Section {
                TextField("Name", text: $spot.name)
                    .font(.title3.bold())
                    .onChange(of: spot.name) { spot.nameIsSuggested = false }
                if spot.nameIsSuggested {
                    Label("Suggested from Apple Maps. Edit to rename.", systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !landmarkSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(landmarkSuggestions, id: \.self) { name in
                                Button(name) {
                                    spot.name = name
                                    spot.nameIsSuggested = false
                                }
                                .buttonStyle(.bordered)
                                .font(.footnote)
                            }
                        }
                    }
                }
                if let address = spot.address {
                    Text(address).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section("Google Maps") {
                Button {
                    UIPasteboard.general.url = URL(string: spot.googleMapsURL)
                    copied = true
                } label: {
                    Label(copied ? "Copied!" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                if let url = URL(string: spot.googleMapsURL) {
                    ShareLink(item: url, subject: Text(spot.displayName), message: Text(spot.displayName)) {
                        Label("Share link", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    openInGoogleMaps()
                } label: {
                    Label("Open in Google Maps", systemImage: "map")
                }
                Button {
                    let item = MKMapItem(location: spot.coordinate.clLocation, address: nil)
                    item.name = spot.displayName
                    item.openInMaps()
                } label: {
                    Label("Open in Apple Maps", systemImage: "applelogo")
                }
                Text(spot.googleMapsURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Details") {
                Picker("Status", selection: $spot.status) {
                    ForEach(SpotStatus.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                Picker("Category", selection: $spot.category) {
                    ForEach(SpotCategory.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                if spot.status == .wantToGo {
                    Picker("Priority", selection: $spot.priority) {
                        Text("None").tag(Int?.none)
                        Text("Someday").tag(Int?.some(1))
                        Text("Soon").tag(Int?.some(2))
                        Text("Must go").tag(Int?.some(3))
                    }
                    TextField("Best season (e.g. May – June)", text: Binding($spot.bestSeason, default: ""))
                } else {
                    Picker("Rating", selection: $spot.rating) {
                        Text("None").tag(Int?.none)
                        ForEach(1...5, id: \.self) { Text(String(repeating: "★", count: $0)).tag(Int?.some($0)) }
                    }
                }
                TextField("Notes", text: $spot.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            if let media = spot.media, !media.isEmpty {
                Section("Photos & videos (\(media.count))") {
                    MediaGrid(links: media.sorted { $0.capturedAt < $1.capturedAt })
                        .listRowInsets(EdgeInsets())
                }
            }

            if !spot.visits.isEmpty || spot.ride != nil {
                Section("Visits") {
                    ForEach(spot.visits.sorted(by: >), id: \.self) { date in
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let ride = spot.ride {
                        NavigationLink(value: ride) {
                            Label("Marked on “\(ride.name)”", systemImage: "road.lanes")
                        }
                    }
                }
            }

            Section {
                Button("Delete spot", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Deleting a spot never deletes your photos.")
            }
        }
        .navigationTitle(spot.displayName)
        .toolbarTitleDisplayMode(.inline)
        .navigationDestination(for: Ride.self) { RideDetailView(ride: $0) }
        .confirmationDialog("Delete this spot?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                recorder.spots.delete(spot)
                dismiss()
            }
        }
        .task {
            let items = await recorder.spots.landmarks(near: spot.coordinate)
            landmarkSuggestions = items.compactMap(\.name).filter { $0 != spot.name }.prefix(5).map { $0 }
        }
        .onDisappear { try? recorder.context.save() }
    }

    private func openInGoogleMaps() {
        let appURL = GoogleMapsLink.appURL(for: spot.coordinate)
        if UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
        } else if let web = URL(string: spot.googleMapsURL) {
            openURL(web)
        }
    }
}

extension Binding where Value: Equatable & Sendable {
    /// Edits an optional value through a non-optional control; the default maps back to `nil`.
    init(_ source: Binding<Value?>, default defaultValue: Value) {
        self.init(
            get: { source.wrappedValue ?? defaultValue },
            set: { source.wrappedValue = $0 == defaultValue ? nil : $0 }
        )
    }
}
