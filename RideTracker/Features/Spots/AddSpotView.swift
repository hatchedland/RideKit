import MapKit
import RideKit
import SwiftUI

/// Add a spot outside a ride: from the current location, a pasted Google Maps link,
/// a search, or a pin dropped on the map. New spots default to the wishlist except "current location".
struct AddSpotView: View {
    enum Mode: Identifiable, Equatable {
        case currentLocation, pasteLink, search
        case pin(CLLocationCoordinate2D)

        var id: String {
            switch self {
            case .currentLocation: "current"
            case .pasteLink: "paste"
            case .search: "search"
            case .pin(let c): "pin-\(c.latitude),\(c.longitude)"
            }
        }

        static func == (lhs: Mode, rhs: Mode) -> Bool { lhs.id == rhs.id }
    }

    let mode: Mode
    var onFinish: (Spot?) -> Void

    @Environment(RideRecorder.self) private var recorder
    @State private var status: SpotStatus = .wantToGo
    @State private var name = ""
    @State private var linkText = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var coordinate: Coordinate?
    @State private var sourceURL: String?
    @State private var message: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                switch mode {
                case .currentLocation:
                    Section {
                        if let coordinate {
                            LabeledContent("Location", value: coordinate.queryString)
                        } else {
                            ProgressView("Finding your location…")
                        }
                    }
                case .pasteLink:
                    pasteSection
                case .search:
                    searchSection
                case .pin:
                    if let coordinate {
                        LabeledContent("Pin", value: coordinate.queryString)
                    }
                }

                if coordinate != nil {
                    Section {
                        TextField("Name (optional — we'll suggest one)", text: $name)
                        Picker("Status", selection: $status) {
                            ForEach(SpotStatus.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onFinish(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(coordinate == nil)
                }
            }
            .task { await prepare() }
        }
    }

    private var title: String {
        switch mode {
        case .currentLocation: "Spot here"
        case .pasteLink: "From Google Maps"
        case .search: "Find a place"
        case .pin: "Dropped pin"
        }
    }

    private var pasteSection: some View {
        Section {
            TextField("https://maps.app.goo.gl/…", text: $linkText, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...4)
            PasteButton(payloadType: String.self) { strings in
                if let first = strings.first {
                    linkText = first
                    Task { await parseLink() }
                }
            }
            Button("Find location") { Task { await parseLink() } }
                .disabled(linkText.isEmpty || working)
            if let coordinate {
                LabeledContent("Found", value: coordinate.queryString)
            }
        } footer: {
            Text("In Google Maps, tap Share on a place and copy the link. Coordinates like “32.47, 77.61” work too.")
        }
    }

    private var searchSection: some View {
        Section {
            TextField("e.g. Chandratal Lake", text: $query)
                .onSubmit { Task { await search() } }
                .submitLabel(.search)
            ForEach(results, id: \.self) { item in
                Button {
                    coordinate = Coordinate(item.location.coordinate)
                    name = item.name ?? ""
                    results = []
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.name ?? "Unnamed place").foregroundStyle(.primary)
                        if let address = item.address?.shortAddress {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let coordinate, results.isEmpty {
                LabeledContent("Selected", value: coordinate.queryString)
            }
        }
    }

    private func prepare() async {
        switch mode {
        case .currentLocation:
            status = .visited
            do {
                coordinate = try await LocationServiceShared.current()
                if coordinate == nil { message = "Location access is off. Turn it on in Settings › Ride Tracker." }
            } catch {
                message = "Couldn't get your location."
            }
        case .pin(let c):
            coordinate = Coordinate(c)
        case .pasteLink, .search:
            // The clipboard is only read through PasteButton, which doesn't trigger iOS's paste prompt.
            break
        }
    }

    private func parseLink() async {
        working = true
        defer { working = false }
        message = nil
        do {
            if let found = try await recorder.spots.coordinate(fromPasted: linkText) {
                coordinate = found
                sourceURL = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                message = "That doesn't look like a Google Maps link."
            }
        } catch {
            message = "This link doesn't include a location. Open it in Google Maps, then share the place itself, or drop a pin instead."
        }
    }

    private func search() async {
        working = true
        defer { working = false }
        results = await recorder.spots.search(query, near: nil)
        if results.isEmpty { message = "No places found." }
    }

    private func save() {
        guard let coordinate else { return }
        let result = recorder.spots.mark(
            at: coordinate,
            status: status,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURL: sourceURL,
            allowRevisit: mode == .currentLocation
        )
        switch result {
        case .created(let spot), .revisited(let spot): onFinish(spot)
        }
    }
}

/// One-shot location lookups outside a ride.
@MainActor
enum LocationServiceShared {
    private static let service = LocationService()
    static func current() async throws -> Coordinate? { try await service.currentLocation() }
}
