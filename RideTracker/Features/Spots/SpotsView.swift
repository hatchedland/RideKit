import MapKit
import SwiftData
import SwiftUI

struct SpotsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case map = "Map", list = "List", places = "Places"
        var id: Self { self }
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All", wishlist = "Want to go", visited = "Visited"
        var id: Self { self }
    }

    @Query(sort: \Spot.createdAt, order: .reverse) private var spots: [Spot]
    @State private var mode: Mode = .map
    @State private var statusFilter: StatusFilter = .all
    @State private var categoryFilter: SpotCategory?
    @State private var searchText = ""
    @State private var addMode: AddSpotView.Mode?
    @State private var path: [Spot] = []

    private var filtered: [Spot] {
        spots.filter { spot in
            switch statusFilter {
            case .all: break
            case .wishlist: if spot.status != .wantToGo { return false }
            case .visited: if spot.status != .visited { return false }
            }
            if let categoryFilter, spot.category != categoryFilter { return false }
            if !searchText.isEmpty {
                let haystack = [spot.name, spot.notes, spot.address ?? "", spot.locality ?? ""].joined(separator: " ")
                if !haystack.localizedStandardContains(searchText) { return false }
            }
            return true
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .map: SpotsMap(spots: filtered) { path.append($0) } onLongPress: { addMode = .pin($0) }
                case .list: SpotsList(spots: filtered)
                case .places: PlacesView(spots: filtered)
                }
            }
            .navigationTitle("Spots")
            .toolbarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search your spots")
            .navigationDestination(for: Spot.self) { SpotDetailView(spot: $0) }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Picker("Status", selection: $statusFilter) {
                                ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.menu)
                            Picker("Category", selection: $categoryFilter) {
                                Text("All categories").tag(SpotCategory?.none)
                                ForEach(SpotCategory.allCases) { Label($0.title, systemImage: $0.systemImage).tag(Optional($0)) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Current location", systemImage: "location.fill") { addMode = .currentLocation }
                        Button("Paste Google Maps link", systemImage: "link") { addMode = .pasteLink }
                        Button("Search for a place", systemImage: "magnifyingglass") { addMode = .search }
                        Button("Long-press the map", systemImage: "hand.point.up.left") { mode = .map }
                    } label: {
                        Label("Add spot", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $addMode) { mode in
                AddSpotView(mode: mode) { spot in
                    addMode = nil
                    if let spot { path.append(spot) }
                }
            }
        }
    }
}

private struct SpotsMap: View {
    let spots: [Spot]
    var onSelect: (Spot) -> Void
    var onLongPress: (CLLocationCoordinate2D) -> Void

    var body: some View {
        GoogleMapView(
            pins: spots.map {
                MapPin(id: $0.id.uuidString, coordinate: $0.coordinate, title: $0.displayName,
                       systemImage: $0.category.systemImage, tint: $0.status.tint)
            },
            camera: .fitContent,
            showsUserLocation: true,
            showsLocationButton: true,
            showsCompass: true,
            onTapPin: { id in
                if let spot = spots.first(where: { $0.id.uuidString == id }) { onSelect(spot) }
            },
            onLongPress: { onLongPress($0.clCoordinate) }
        )
        .overlay(alignment: .bottom) {
            if spots.isEmpty {
                Text("Long-press the map to drop a spot, or tap + to add one.")
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: .capsule)
                    .padding()
            }
        }
    }
}

private struct SpotsList: View {
    let spots: [Spot]
    @Environment(RideRecorder.self) private var recorder

    var body: some View {
        List {
            ForEach(spots) { spot in
                NavigationLink(value: spot) { SpotRow(spot: spot) }
            }
            .onDelete { offsets in
                offsets.map { spots[$0] }.forEach(recorder.spots.delete)
            }
        }
        .overlay {
            if spots.isEmpty {
                ContentUnavailableView("No spots yet", systemImage: "mappin.slash",
                                       description: Text("Mark spots while riding, or add places you want to go."))
            }
        }
    }
}

/// Spots grouped by city / area.
private struct PlacesView: View {
    let spots: [Spot]

    private var groups: [(place: String, spots: [Spot])] {
        Dictionary(grouping: spots) { $0.locality ?? "Unknown area" }
            .map { ($0.key, $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.place.localizedStandardCompare($1.place) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.place) { group in
                Section {
                    ForEach(group.spots) { spot in
                        NavigationLink(value: spot) { SpotRow(spot: spot) }
                    }
                } header: {
                    let mediaCount = group.spots.reduce(0) { $0 + ($1.media?.count ?? 0) }
                    Text("\(group.place) · \(group.spots.count) spots · \(mediaCount) photos")
                }
            }
        }
    }
}

struct SpotRow: View {
    let spot: Spot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: spot.category.systemImage)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(spot.status.tint.opacity(0.2), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(spot.displayName).font(.headline).lineLimit(1)
                    if spot.nameIsSuggested {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Label(spot.status.title, systemImage: spot.status.systemImage)
                    if let count = spot.media?.count, count > 0 {
                        Label("\(count)", systemImage: "photo")
                    }
                    if let locality = spot.locality {
                        Text(locality).lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

extension SpotStatus {
    /// Wishlist = highway yellow (the road ahead); visited = asphalt (ridden).
    var tint: Color {
        switch self {
        case .wantToGo: Brand.highwayYellow
        case .visited: Brand.asphalt
        }
    }
}
