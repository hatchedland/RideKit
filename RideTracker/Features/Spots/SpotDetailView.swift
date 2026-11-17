import MapKit
import RideKit
import SwiftData
import SwiftUI

struct SpotDetailView: View {
    @Bindable var spot: Spot
    /// Shown in a map drawer: the map is already above it, and nothing opens a new page.
    var inDrawer = false
    /// In a drawer the name field is the drawer's header; this is its focus.
    var drawerNameFocus: FocusState<Bool>.Binding?
    /// A drawer opened from the list has no map above it, so it shows the spot's own.
    var showsMap = false
    @FocusState private var nameFocused: Bool

    /// Renaming is occasional, so nearby names only appear while the name is being edited.
    private var editingName: Bool { drawerNameFocus?.wrappedValue ?? nameFocused }
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var landmarkSuggestions: [String] = []
    @State private var shareRequest: MediaShareRequest?

    var body: some View {
        List {
            if !inDrawer || showsMap {
            Section {
                GoogleMapView(
                    pins: [MapPin(id: spot.id.uuidString, coordinate: spot.coordinate, title: spot.displayName,
                                  systemImage: spot.category.icon, tint: spot.status.tint)],
                    camera: .center(spot.coordinate, zoom: 15),
                    isInteractive: false
                )
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
                .allowsHitTesting(false)
            }
            }

            Section {
                // In a drawer the header is the name field.
                if !inDrawer {
                    HStack(spacing: 6) {
                        TextField("Name", text: $spot.name)
                            .font(.title3.bold())
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onChange(of: spot.name) { spot.nameIsSuggested = false }
                        if spot.nameIsSuggested && !nameFocused {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Suggested name")
                        }
                    }
                }
                if editingName && !landmarkSuggestions.isEmpty {
                    NearbyNames(names: landmarkSuggestions) { name in
                        spot.name = name
                        spot.nameIsSuggested = false
                        if let drawerNameFocus { drawerNameFocus.wrappedValue = false } else { nameFocused = false }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let address = spot.address {
                    Text(address).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            // No pop-up menus here: they open wherever the control happens to be in a moving drawer.
            // Every choice is an inline control that stays put.
            Section("Details") {
                Picker("Status", selection: $spot.status) {
                    ForEach(SpotStatus.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                CategoryGrid(selection: $spot.category)

                if spot.status == .wantToGo {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Priority").font(.subheadline).foregroundStyle(.secondary)
                        Picker("Priority", selection: $spot.priority) {
                            Text("None").tag(Int?.none)
                            Text("Someday").tag(Int?.some(1))
                            Text("Soon").tag(Int?.some(2))
                            Text("Must").tag(Int?.some(3))
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField("Best season (e.g. May – June)", text: Binding($spot.bestSeason, default: ""))
                } else {
                    StarRating(rating: $spot.rating)
                }
                TextField("Notes", text: $spot.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            if let media = spot.media, !media.isEmpty {
                let sorted = media.sorted { $0.capturedAt < $1.capturedAt }
                Section {
                    MediaGrid(links: sorted)
                        .listRowInsets(EdgeInsets())
                } header: {
                    HStack {
                        Text("Photos & videos (\(media.count))")
                        Spacer()
                        Button("Share all", systemImage: "square.and.arrow.up") {
                            shareRequest = MediaShareRequest(localIdentifiers: sorted.map(\.localIdentifier))
                        }
                        .font(.footnote)
                        .textCase(nil)
                    }
                }
            }

            if !spot.visits.isEmpty || spot.ride != nil {
                Section("Visits") {
                    ForEach(spot.visits.sorted(by: >), id: \.self) { date in
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let ride = spot.ride {
                        if inDrawer {
                            Label("Marked on “\(ride.name)”", systemImage: "road.lanes")
                        } else {
                            NavigationLink(value: ride) {
                                Label("Marked on “\(ride.name)”", systemImage: "road.lanes")
                            }
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
        .mediaSharing($shareRequest)
        .confirmationDialog("Delete this spot?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                recorder.spots.delete(spot)
                dismiss()
            }
        }
        .task {
            let items = await recorder.spots.landmarks(near: spot.coordinate)
            landmarkSuggestions = items.map(\.name).filter { $0 != spot.name }.prefix(5).map { $0 }
        }
        .onDisappear { try? recorder.context.save() }
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

/// A spot in a map drawer: header (tap to expand or collapse) and the spot's details below.
struct SpotDrawer: View {
    @Bindable var spot: Spot
    /// Opened from a list rather than a map: include the spot's small map.
    var showsMap = false
    @Environment(RideRecorder.self) private var recorder
    @FocusState private var nameFocused: Bool
    @State private var showingRoute = false

    var body: some View {
        VStack(spacing: 0) {
            MapDrawerHeader(
                title: spot.displayName,
                editableTitle: Binding(get: { spot.name }, set: { spot.name = $0; spot.nameIsSuggested = false }),
                titleFocus: $nameFocused,
                subtitle: [spot.category.title, spot.status.title, spot.locality].compactMap { $0 }.joined(separator: " · "),
                systemImage: spot.category.icon
            ) {
                Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                    showingRoute = true
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(recorder.isRiding)
                .accessibilityLabel("Directions")
                .accessibilityHint("Shows the route and starts a ride here")
            }
            SpotDetailView(spot: spot, inDrawer: true, drawerNameFocus: $nameFocused, showsMap: showsMap)
        }
        .animation(.snappy, value: nameFocused)
        .sheet(isPresented: $showingRoute) {
            RoutePreviewSheet(destination: RideDestination(name: spot.displayName, coordinate: spot.coordinate, spotID: spot.id))
        }
    }
}

/// "NEARBY [Ambedkar circle] [Mari Amma Temple] →": names of places around a spot, shown while
/// its name is being edited.
struct NearbyNames: View {
    let names: [String]
    var onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("NEARBY").font(Brand.label).tracking(0.6).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        Button(name) { onPick(name) }
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(.quaternary, in: .capsule)
                            .buttonStyle(.plain)
                            .accessibilityHint("Use this name")
                    }
                }
            }
        }
    }
}

/// The eight categories as a 4 × 2 grid of icon tiles: all visible at once, always in the same place.
struct CategoryGrid: View {
    @Binding var selection: SpotCategory

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(SpotCategory.allCases) { category in
                let selected = category == selection
                Button {
                    selection = category
                } label: {
                    VStack(spacing: 4) {
                        Image(icon: category.icon).font(.title3)
                        Text(category.shortTitle).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    // Highway yellow is a fill with asphalt on it, never yellow text.
                    .foregroundStyle(selected ? Brand.asphalt : .primary)
                    .background(selected ? AnyShapeStyle(Brand.highwayYellow) : AnyShapeStyle(.quaternary),
                                in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Five stars; tapping the current rating again clears it.
struct StarRating: View {
    @Binding var rating: Int?

    var body: some View {
        HStack {
            Text("Rating")
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        rating = rating == value ? nil : value
                    } label: {
                        Image(systemName: value <= (rating ?? 0) ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(value <= (rating ?? 0) ? Brand.accent : .secondary)
                            .frame(width: 36, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                    .accessibilityAddTraits(value == rating ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }
}
