import CoreLocation
import MapKit
import RideKit
import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(RideRecorder.self) private var recorder

    var body: some View {
        if recorder.phase == .recording || recorder.phase == .finishing {
            RidingView()
        } else {
            ReadyView()
        }
    }
}

/// Before a ride: big Start button and the wishlist at a glance.
private struct ReadyView: View {
    @Environment(RideRecorder.self) private var recorder
    @Query(filter: #Predicate<Spot> { $0.statusRaw == "wantToGo" }, sort: \Spot.createdAt, order: .reverse)
    private var wishlist: [Spot]
    @Query(sort: \Ride.startedAt, order: .reverse) private var rides: [Ride]
    @State private var showingStart = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Muted so the wishlist and the Start button carry the colour.
                GoogleMapView(
                    pins: wishlist.map {
                        MapPin(id: $0.id.uuidString, coordinate: $0.coordinate, title: $0.displayName,
                               systemImage: $0.category.systemImage, tint: Brand.highwayYellow)
                    },
                    camera: .userLocation,
                    look: .muted,
                    showsUserLocation: true,
                    showsLocationButton: true,
                    showsCompass: true,
                    // Keeps the location button and Google logo above the Start button.
                    padding: UIEdgeInsets(top: 0, left: 0, bottom: 150, right: 0)
                )
                .ignoresSafeArea(edges: .horizontal)

                VStack(spacing: 12) {
                    if let last = rides.first {
                        HStack(spacing: 8) {
                            MilestoneMark().frame(width: 12)
                            Text("Last ride: \(last.name) · \(Format.distance(last.distanceMeters))")
                        }
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: .capsule)
                    }
                    Button {
                        showingStart = true
                    } label: {
                        Label("Start ride", systemImage: "play.fill")
                            .font(.title2.bold().width(.expanded))
                            .foregroundStyle(Brand.asphalt)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.highwayYellow)
                    .disabled(recorder.phase != .idle)
                }
                .padding()
            }
            .navigationTitle("Ride")
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingStart) {
                StartRideSheet(wishlist: wishlist, recentRides: Array(rides.prefix(30)))
                    .presentationDetents([.large])
            }
        }
    }
}

/// "Where to?" first, then Start. Picking a destination names the ride ("Ride to Zostel Ooty");
/// "Just ride" skips it. The Action button, Siri and the Lock Screen still start instantly
/// without this sheet.
struct StartRideSheet: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var wishlist: [Spot]
    var recentRides: [Ride]

    @State private var query = ""
    @State private var destination: RideDestination?
    @State private var justRide = false
    @State private var name = ""
    /// The rider typed their own name; picking another destination won't overwrite it.
    @State private var nameEdited = false
    @State private var here: Coordinate?
    @State private var results: [RideDestination] = []
    @State private var searching = false
    @State private var shareWithFriends = AppSettings.shareRidesByDefault
    @State private var shareLive = false
    @AppStorage(AppSettings.Key.openDirectionsOnStart) private var openDirections = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case search, name }

    private var choosing: Bool { destination == nil && !justRide }

    var body: some View {
        NavigationStack {
            Form {
                if choosing {
                    whereTo
                } else {
                    chosen
                    nameSection
                    if destination != nil {
                        Section {
                            Toggle(isOn: $openDirections) {
                                Label("Directions in Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                            }
                        } footer: {
                            Text("Opens Google Maps with the route when the ride starts. Ride Tracker keeps recording in the background.")
                        }
                    }
                    sharing
                }
                if let error {
                    Section { Text(error).foregroundStyle(Brand.signal) }
                }
            }
            .navigationTitle("New ride")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: start)
                        .bold()
                        .disabled(recorder.phase != .idle)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !choosing {
                    Button(action: start) {
                        Label("Start ride", systemImage: "play.fill")
                            .font(.title3.bold().width(.expanded))
                            .foregroundStyle(Brand.asphalt)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.highwayYellow)
                    .disabled(recorder.phase != .idle)
                    .padding()
                    .background(.bar)
                }
            }
            .onAppear { focus = .search }
            .task { await locate() }
            .task(id: query) { await search() }
        }
    }

    // MARK: Where to?

    private var suggestions: [DestinationSuggestions.Suggestion] {
        DestinationSuggestions.suggestions(
            query: query,
            wishlist: wishlist.map { RideDestination(name: $0.displayName, coordinate: $0.coordinate, spotID: $0.id) },
            recent: recentRides.compactMap(\.destination),
            from: here
        )
    }

    @ViewBuilder private var whereTo: some View {
        Section {
            TextField("Where to?", text: $query, prompt: Text("Search a place, or pick one below"))
                .font(.title3)
                .focused($focus, equals: .search)
                .submitLabel(.search)
                .autocorrectionDisabled()
        }

        let suggestions = suggestions
        let wished = suggestions.filter { $0.source == .wishlist }
        let recent = suggestions.filter { $0.source == .recent }
        if !wished.isEmpty {
            Section("Wishlist") {
                ForEach(wished, id: \.self) { row($0.destination, distance: $0.distance, icon: "star.fill") }
            }
        }
        if !recent.isEmpty {
            Section("Recent") {
                ForEach(recent, id: \.self) { row($0.destination, distance: $0.distance, icon: "clock.arrow.circlepath") }
            }
        }
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            Section("Places") {
                if searching && results.isEmpty {
                    HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                } else if results.isEmpty {
                    Text("No places found for “\(query)”. Check your connection, or pick from your wishlist.")
                        .foregroundStyle(.secondary)
                }
                ForEach(results, id: \.self) { row($0, distance: here.map($0.remainingDistance(from:)), icon: "mappin.circle") }
            }
        }

        Section {
            Button {
                justRide = true
                focus = .name
            } label: {
                Label("Just ride (no destination)", systemImage: "road.lanes")
            }
        } footer: {
            Text("Where you're going is never shared with friends.")
        }
    }

    private func row(_ place: RideDestination, distance: Double?, icon: String) -> some View {
        Button {
            choose(place)
        } label: {
            HStack {
                Label(place.name, systemImage: icon)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if let distance {
                    Text(Format.distance(distance))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHint("Ride here")
    }

    private func choose(_ place: RideDestination) {
        destination = place
        if !nameEdited { name = RideNaming.name(goingTo: place) }
        focus = nil
    }

    // MARK: After choosing

    private var chosen: some View {
        Section {
            HStack {
                if let destination {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.name).font(.headline)
                            if let here {
                                Text("\(Format.distance(destination.remainingDistance(from: here))) away")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                } else {
                    Label("Just ride", systemImage: "road.lanes").font(.headline)
                }
                Spacer()
                Button("Change") {
                    destination = nil
                    justRide = false
                    focus = .search
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Where to")
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Ride name", text: $name, prompt: Text(destination == nil ? "e.g. Sunday ghat run" : "Ride name"))
                .focused($focus, equals: .name)
                .submitLabel(.go)
                .onSubmit(start)
                .onChange(of: name) { _, newValue in
                    if let destination, newValue == RideNaming.name(goingTo: destination) { return }
                    nameEdited = true
                }
        } header: {
            Text("Ride name")
        } footer: {
            Text("Every photo and video you take until you end the ride goes into a Photos album with this name.")
        }
    }

    // Decided here, before moving: nothing on the riding screen asks for attention.
    @ViewBuilder private var sharing: some View {
        if recorder.friends.availability == .available {
            Section {
                Toggle("Share with friends after the ride", isOn: $shareWithFriends)
                Toggle("Let friends follow live", isOn: $shareLive)
            } footer: {
                if shareLive {
                    Text("Friends see where you are about once a minute until you end the ride, and the ride name. Your destination, start and privacy zones stay hidden.")
                } else {
                    Text("Photos are never shared automatically; pick them after the ride.")
                }
            }
        }
    }

    // MARK: Work

    /// One fix for distances and to bias search towards where the rider is.
    private func locate() async {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    here = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    return
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally { return }
            }
        } catch {}
    }

    /// Apple place search, debounced by `.task(id:)` cancelling the previous query.
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        let region = here.map { MKCoordinateRegion(center: $0.clCoordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000) }
        let items = await recorder.spots.search(text, near: region)
        guard !Task.isCancelled else { return }
        results = items.prefix(8).map { item in
            let coordinate = item.location.coordinate
            return RideDestination(name: item.name ?? text,
                                   coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
    }

    private func start() {
        let destination = destination
        Task {
            do {
                try await recorder.start(name: name, destination: destination, shareWithFriends: shareWithFriends, shareLive: shareLive)
                dismiss()
                if let destination, openDirections {
                    openURL(GoogleMapsLink.directionsURL(to: destination.coordinate))
                }
            } catch {
                self.error = "Couldn't start the ride: \(error.localizedDescription)"
            }
        }
    }
}
