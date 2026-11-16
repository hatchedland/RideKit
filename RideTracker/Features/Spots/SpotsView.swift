import MapKit
import SwiftData
import SwiftUI

struct SpotsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case map = "Map", list = "List"
        var id: Self { self }
    }

    /// How the list is arranged. Grouping by area used to be its own "Places" tab.
    enum Sort: String, CaseIterable, Identifiable {
        case newest = "Newest", byArea = "By area"
        var id: Self { self }
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All", wishlist = "Want to go", visited = "Visited"
        var id: Self { self }
    }

    @Query(sort: \Spot.createdAt, order: .reverse) private var spots: [Spot]
    @AppStorage("spots.mode") private var mode: Mode = .map
    @AppStorage("spots.sort") private var sort: Sort = .newest
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
                case .map: SpotsMap(spots: filtered) { addMode = .pin($0) }
                case .list: SpotsList(spots: filtered, sort: sort)
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
                                ForEach(SpotCategory.allCases) { category in Label { Text(category.title) } icon: { Image(icon: category.icon) }.tag(Optional(category)) }
                            }
                            .pickerStyle(.menu)
                            if mode == .list {
                                Picker("Sort", selection: $sort) {
                                    ForEach(Sort.allCases) { Label($0.rawValue, systemImage: $0 == .newest ? "clock" : "building.2").tag($0) }
                                }
                                .pickerStyle(.menu)
                            }
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
    var onLongPress: (CLLocationCoordinate2D) -> Void
    @State private var selected: Spot?

    var body: some View {
        GoogleMapView(
            pins: spots.map {
                MapPin(id: $0.id.uuidString, coordinate: $0.coordinate, title: $0.displayName,
                       systemImage: $0.category.icon, tint: $0.status.tint)
            },
            camera: .fitContent,
            showsUserLocation: true,
            showsLocationButton: true,
            showsCompass: true,
            onTapPin: { id in
                selected = spots.first { $0.id.uuidString == id }
            },
            onLongPress: { onLongPress($0.clCoordinate) },
            onTapMap: { selected = nil }
        )
        .mapDrawer(item: $selected) { SpotDrawer(spot: $0) }
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

/// Every spot as a stone card, newest first or grouped by town / area.
private struct SpotsList: View {
    let spots: [Spot]
    let sort: SpotsView.Sort
    @Environment(RideRecorder.self) private var recorder
    @State private var deleting: Spot?
    @State private var selected: Spot?

    private var groups: [(place: String, spots: [Spot])] {
        Dictionary(grouping: spots) { $0.locality ?? "Unknown area" }
            .map { ($0.key, $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.place.localizedStandardCompare($1.place) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                switch sort {
                case .newest:
                    cards(spots)
                case .byArea:
                    ForEach(groups, id: \.place) { group in
                        let photos = group.spots.reduce(0) { $0 + ($1.media?.count ?? 0) }
                        RoadHeader(title: group.place,
                                   trailing: "\(group.spots.count) \(group.spots.count == 1 ? "spot" : "spots")",
                                   accessibilityText: "\(group.place), \(group.spots.count) spots, \(photos) photos")
                        cards(group.spots)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, sort == .newest ? 12 : 0)
            .padding(.bottom, 24)
        }
        .background(Brand.page)
        .overlay {
            if spots.isEmpty {
                ContentUnavailableView("No spots yet", systemImage: "mappin.slash",
                                       description: Text("Mark spots while riding, or add places you want to go."))
            }
        }
        // Same as tapping a pin on the map: a drawer, never a new page.
        // No map behind a list, so no reason to peek: open full screen.
        .mapDrawer(item: $selected, startsExpanded: true) { SpotDrawer(spot: $0, showsMap: true) }
        .confirmationDialog("Delete this spot?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { spot in
            Button("Delete “\(spot.displayName)”", role: .destructive) { recorder.spots.delete(spot) }
        } message: { _ in
            Text("Its photos stay in your Photos library.")
        }
    }

    private func cards(_ spots: [Spot]) -> some View {
        ForEach(spots) { spot in
            Button { selected = spot } label: { SpotCard(spot: spot) }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete spot", systemImage: "trash", role: .destructive) { deleting = spot }
                }
        }
    }
}

/// A spot as a card: your photo of it (or its category), the name, a signboard line, where it is.
struct SpotCard: View {
    let spot: Spot

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SpotThumb(spot: spot)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    // The ✨ flows with the text, so it stays at the end of a name that wraps.
                    (Text(spot.displayName)
                        + Text(spot.nameIsSuggested ? "  \(Image(systemName: "sparkles"))" : "")
                            .font(.caption).foregroundStyle(.secondary))
                        .font(.headline)
                        .lineLimit(2)
                        .accessibilityLabel(spot.nameIsSuggested ? "\(spot.displayName), suggested name" : spot.displayName)
                    Text(signLine)
                        .font(Brand.label)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Brand.card, in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    /// "FOOD · VISITED", "VIEWPOINT · WANT TO GO · MUST"
    private var signLine: String {
        var parts = [spot.category.shortTitle, spot.status.title]
        if spot.status == .wantToGo, let priority = spot.priority {
            parts.append(["", "Someday", "Soon", "Must"][min(3, max(1, priority))])
        }
        return parts.joined(separator: " · ").uppercased()
    }

    /// "Mandya, Karnataka · 3 photos"
    private var detailLine: String {
        var parts: [String] = []
        if let locality = spot.locality { parts.append(locality) }
        if let count = spot.media?.count, count > 0 { parts.append("\(count) \(count == 1 ? "photo" : "photos")") }
        return parts.joined(separator: " · ")
    }
}

/// What a spot looks like in a list: your own photo of the place (with a small category badge),
/// or, without photos, a category tile. Wishlist tiles are highway yellow, visited ones quiet.
/// The km-stone is kept for distances (rides); a place is recognised by what it looks like.
struct SpotThumb: View {
    let spot: Spot
    var size: CGFloat = 56

    private var photo: MediaLink? {
        (spot.media ?? []).filter { !$0.isVideo }.min { $0.capturedAt < $1.capturedAt }
    }

    var body: some View {
        let corner = size * 0.25
        ZStack(alignment: .bottomTrailing) {
            if let photo {
                AssetThumbnail(localIdentifier: photo.localIdentifier, isVideo: false)
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: corner))
                Image(icon: spot.category.icon)
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(Brand.asphalt)
                    .frame(width: size * 0.4, height: size * 0.4)
                    .background(spot.status == .wantToGo ? Brand.highwayYellow : Brand.chalk, in: .circle)
                    .overlay(Circle().stroke(Brand.card, lineWidth: 2))
                    .offset(x: size * 0.1, y: size * 0.1)
            } else {
                let wish = spot.status == .wantToGo
                Image(icon: spot.category.icon)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(wish ? Brand.asphalt : Color.primary)
                    .frame(width: size, height: size)
                    .background(wish ? AnyShapeStyle(Brand.highwayYellow) : AnyShapeStyle(.quaternary),
                                in: .rect(cornerRadius: corner))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SpotRow: View {
    let spot: Spot

    var body: some View {
        HStack(spacing: 12) {
            SpotThumb(spot: spot, size: 40)
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
