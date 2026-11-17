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

/// Before a ride, a dashboard for the questions a rider has before setting off: can I ride now
/// (weather), how am I doing (ODO/TRIP), where could I go (nearest wishlist spots), and one big
/// Start ride button. No map: it lives in Spots, and fills the screen once riding. Many rides have
/// no destination, so where to go is an optional part of the next step, never a gate.
private struct ReadyView: View {
    @Environment(RideRecorder.self) private var recorder
    @Query(filter: #Predicate<Spot> { $0.statusRaw == "wantToGo" }, sort: \Spot.createdAt, order: .reverse)
    private var wishlist: [Spot]
    @Query(sort: \Ride.startedAt, order: .reverse) private var rides: [Ride]
    @Query(filter: #Predicate<Spot> { $0.nameIsSuggested == true }, sort: \Spot.createdAt, order: .reverse)
    private var unnamed: [Spot]
    @State private var showingStart = false
    /// The next 12 hours here; `nil` while loading, empty when unavailable.
    @State private var forecast: [WeatherHour]?
    /// Set when the ride is started from the display's NEXT row.
    @State private var startDestination: RideDestination?
    @State private var showingToName = false
    @State private var here: Coordinate?
    /// "Ooty, The Nilgiris": where the rider is, shown as the screen's title.
    @State private var placeName: String?

    /// The three nearest wishlist spots (newest first until the location is known).
    private var nearby: [DestinationSuggestions.Suggestion] {
        DestinationSuggestions.suggestions(
            query: "",
            wishlist: wishlist.map { RideDestination(name: $0.displayName, coordinate: $0.coordinate, spotID: $0.id) },
            recent: [], from: here, wishlistLimit: 3
        )
        .filter { $0.source == .wishlist }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PreRideWeatherCard(forecast: forecast)
                    if !rides.isEmpty || !unnamed.isEmpty {
                        RideDisplay(rides: rides, next: nil, toName: unnamed.count,
                                    onNext: { _ in }, onToName: { showingToName = true })
                    }
                    NearbyWishlist(suggestions: nearby,
                                   categories: Dictionary(wishlist.map { ($0.id, $0.category.icon) }, uniquingKeysWith: { a, _ in a }),
                                   onPick: { destination in
                                       startDestination = destination
                                       showingStart = true
                                   })
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            // Start ride stays where the thumb expects it, over the bottom of the dashboard.
            .safeAreaInset(edge: .bottom) {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Brand.page.opacity(0.94))
            }
            .background(Brand.page)
            .navigationTitle("Ride")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                // The tab bar already says "Ride"; the title says where you are, like a place-name board.
                ToolbarItem(placement: .principal) {
                    if let placeName {
                        Label(placeName.uppercased(), image: "category-other")
                            .labelStyle(.titleAndIcon)
                            .font(Brand.label)
                            .tracking(1)
                            .lineLimit(1)
                            .accessibilityLabel("You're in \(placeName)")
                    }
                }
            }
            .sheet(isPresented: $showingStart, onDismiss: { startDestination = nil }) {
                StartRideSheet(
                    wishlist: wishlist.map { RideDestination(name: $0.displayName, coordinate: $0.coordinate, spotID: $0.id) },
                    recent: rides.prefix(30).compactMap(\.destination),
                    initialDestination: startDestination
                )
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingToName) { SpotsToName(spots: unnamed) }
            .task {
                here = await CurrentLocation.once()
                guard let here else { forecast = []; return }
                async let place = SpotService.reverseGeocode(here).locality
                async let hours = GooglePlacesClient.app.forecastHours(at: here, hours: 12)
                forecast = await hours
                placeName = await place
            }
        }
    }
}

/// The Ride tab's instrument display, in the language of a motorcycle dash: ODO (all rides) and
/// TRIP (this month) as lit digits over dim unlit segments, a NEXT prompt for the nearest wishlist
/// spot (like a TFT nav line), and an amber service-light row when something needs doing.
/// Rows without content stay out, like unused segments. Always dark, like the riding screen.
private struct RideDisplay: View {
    let rides: [Ride]
    let next: DestinationSuggestions.Suggestion?
    let toName: Int
    var onNext: (RideDestination) -> Void
    var onToName: () -> Void

    var body: some View {
        let now = Date.now
        let total = rides.reduce(0) { $0 + $1.distanceMeters }
        let month = rides.filter { Calendar.current.isDate($0.startedAt, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.distanceMeters }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                reading("ODO", digits: String(format: "%06d", min(999_999, Int(total / 1_000))), mask: "888888",
                        spoken: "\(Format.distance(total)) in total")
                Spacer(minLength: 16)
                reading("TRIP · \(now.formatted(.dateTime.month(.abbreviated)).uppercased())",
                        digits: String(format: "%05.1f", min(9_999.9, month / 1_000)), mask: "888.8",
                        spoken: "\(Format.distance(month)) this month")
            }

            if next != nil || toName > 0 {
                Rectangle().fill(Brand.chalk.opacity(0.12)).frame(height: 1)
            }

            if let next {
                Button { onNext(next.destination) } label: {
                    HStack(spacing: 8) {
                        Text("NEXT ▸").font(Brand.label).tracking(1).foregroundStyle(Brand.chalk.opacity(0.55))
                        Text(next.destination.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.chalk)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let distance = next.distance {
                            Text(Format.distanceParts(distance).value + " KM")
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Brand.highwayYellow)
                        }
                    }
                    .frame(minHeight: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next: \(next.destination.name)\(next.distance.map { ", \(Format.distance($0)) away" } ?? "")")
                .accessibilityHint("Start a ride there")
            }

            if toName > 0 {
                Button(action: onToName) {
                    HStack(spacing: 8) {
                        // An amber tell-tale, like a bike's service light: lit only when needed.
                        Circle().fill(Brand.highwayYellow).frame(width: 8, height: 8)
                            .shadow(color: Brand.highwayYellow.opacity(0.8), radius: 4)
                        Text("\(toName) \(toName == 1 ? "SPOT" : "SPOTS") TO NAME")
                            .font(Brand.label).tracking(1).foregroundStyle(Brand.chalk.opacity(0.8))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Brand.chalk.opacity(0.4))
                    }
                    .frame(minHeight: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(toName) spots still have suggested names")
                .accessibilityHint("Name them")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Brand.asphalt, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.chalk.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private func reading(_ label: String, digits: String, mask: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Brand.label)
                .tracking(1)
                .foregroundStyle(Brand.chalk.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ZStack(alignment: .trailing) {
                    // Unlit segments behind the lit digits, as on a real LCD.
                    Text(mask).foregroundStyle(Brand.chalk.opacity(0.07))
                    Text(digits).foregroundStyle(Brand.highwayYellow)
                }
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                Text("KM")
                    .font(Brand.label)
                    .foregroundStyle(Brand.chalk.opacity(0.55))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// Spots still carrying a suggested name, from the display's service light. Each opens in the full drawer.
private struct SpotsToName: View {
    let spots: [Spot]
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Spot?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(spots) { spot in
                        Button { selected = spot } label: { SpotCard(spot: spot) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Brand.page)
            .overlay {
                if spots.isEmpty {
                    ContentUnavailableView("All named", systemImage: "checkmark.seal",
                                           description: Text("Every spot has a name you chose."))
                }
            }
            .navigationTitle("Spots to name")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .mapDrawer(item: $selected, startsExpanded: true) { SpotDrawer(spot: $0, showsMap: true) }
        }
    }
}

/// Step 2: optionally say where you're going, then Start. The big button always works: without a
/// destination it starts a plain ride ("Ride · 16 Nov 2026"); with one, "Ride to Zostel Ooty".
/// Re-fetch the route only when the destination or the starting point changes.
private struct RouteKey: Equatable {
    var destination: Coordinate?
    var here: Coordinate?
}

private struct StartRideSheet: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    let wishlist: [RideDestination]
    let recent: [RideDestination]
    /// Pre-picked, e.g. from the display's NEXT row; can still be removed.
    var initialDestination: RideDestination?

    @State private var query = ""
    @State private var destination: RideDestination?
    @State private var results: [RideDestination] = []
    @State private var searching = false
    @State private var here: Coordinate?
    @State private var name = ""
    /// The rider typed a name; picking a destination won't overwrite it.
    @State private var nameEdited = false
    @State private var shareLive = false
    @State private var error: String?
    /// The road to the picked destination, for the arrival estimate.
    @State private var route: RideRoute?

    var body: some View {
        NavigationStack {
            Form {
                whereTo
                Section {
                    TextField("Ride name", text: $name, prompt: Text(defaultName))
                        .onChange(of: name) { _, new in
                            if let destination, new == RideNaming.name(goingTo: destination) { return }
                            nameEdited = !new.isEmpty
                        }
                } header: {
                    Text("Ride name")
                } footer: {
                    Text("Also the name of the Photos album for this ride.")
                }
                if recorder.friends.availability == .available {
                    Section {
                        Toggle("Friends follow live", systemImage: "person.2", isOn: $shareLive)
                    } footer: {
                        Text(shareLive
                             ? "Friends see where you are about once a minute and the ride name. Your destination, start and privacy zones stay hidden."
                             : "Where you're going is never shared with friends.")
                    }
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
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Label(destination.map { "Start ride to \($0.name)" } ?? "Start ride", systemImage: "play.fill")
                        .font(.title3.bold().width(.expanded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Brand.asphalt)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.highwayYellow)
                .disabled(recorder.phase != .idle)
                .padding()
                .background(.bar)
            }
            .task { here = await CurrentLocation.once() }
            .task(id: query) { await search() }
            .task(id: RouteKey(destination: destination?.coordinate, here: here)) {
                route = nil
                guard let destination, let here else { return }
                route = await GooglePlacesClient.app.route(from: here, to: destination.coordinate)
            }
            .onAppear { if let initialDestination, destination == nil { choose(initialDestination) } }
        }
    }

    private var defaultName: String {
        destination.map(RideNaming.name(goingTo:)) ?? "Ride · \(Date.now.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    // MARK: Where to? (optional)

    @ViewBuilder private var whereTo: some View {
        if let destination {
            Section("Where to") {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.name).font(.headline)
                            if let here {
                                Text("\(Format.distance(destination.remainingDistance(from: here))) away")
                                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                    Spacer()
                    Button("Remove destination", systemImage: "xmark.circle.fill") { choose(nil) }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.borderless)
                }
                if let route {
                    ArrivalEstimateView(destination: destination, route: route, prominent: false)
                }
            }
        } else {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Where to?", text: $query, prompt: Text("Where to? (optional)"))
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                }
            } footer: {
                if query.isEmpty {
                    Text("Skip this to just ride.")
                }
            }

            let suggestions = DestinationSuggestions.suggestions(query: query, wishlist: wishlist, recent: recent, from: here)
            let wished = suggestions.filter { $0.source == .wishlist }
            let recents = suggestions.filter { $0.source == .recent }
            if !wished.isEmpty {
                Section("Wishlist") {
                    ForEach(wished, id: \.self) { row($0.destination, distance: $0.distance, icon: "star.fill") }
                }
            }
            if !recents.isEmpty {
                Section("Recent") {
                    ForEach(recents, id: \.self) { row($0.destination, distance: $0.distance, icon: "clock.arrow.circlepath") }
                }
            }
            if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                Section {
                    if searching && results.isEmpty {
                        HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                    } else if results.isEmpty {
                        Text("No places found for “\(query)”. Check your connection, or pick from your wishlist.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results, id: \.self) { row($0, distance: here.map($0.remainingDistance(from:)), icon: "mappin.circle") }
                } header: {
                    Text("Places")
                } footer: {
                    if !results.isEmpty { PoweredByGoogle() }
                }
            }
        }
    }

    private func row(_ place: RideDestination, distance: Double?, icon: String) -> some View {
        Button {
            choose(place)
        } label: {
            HStack {
                Label(place.name, systemImage: icon).foregroundStyle(.primary).lineLimit(1)
                Spacer()
                if let distance {
                    Text(Format.distance(distance)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHint("Ride here")
    }

    private func choose(_ place: RideDestination?) {
        destination = place
        query = ""
        if !nameEdited { name = place.map(RideNaming.name(goingTo:)) ?? "" }
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
        let places = await recorder.spots.search(text, near: here)
        guard !Task.isCancelled else { return }
        results = places.prefix(8).map { RideDestination(name: $0.name, coordinate: $0.coordinate) }
    }

    private func start() {
        let destination = destination
        error = nil
        Task {
            do {
                try await recorder.start(name: name, destination: destination,
                                         shareWithFriends: AppSettings.shareRidesByDefault, shareLive: shareLive)
                dismiss()
            } catch {
                self.error = "Couldn't start the ride: \(error.localizedDescription)"
            }
        }
    }
}

/// One location fix, for distances and to bias search towards where the rider is.
enum CurrentLocation {
    @MainActor
    static func once() async -> Coordinate? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
            }
        } catch {}
        return nil
    }
}
