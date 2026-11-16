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
                StartRideSheet(recentNames: Array(rides.prefix(20).map(\.name)), wishlistNames: wishlist.map(\.displayName))
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

/// Name the ride, then Start. An empty name gets "Ride · 12 Oct 2026".
struct StartRideSheet: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    var recentNames: [String]
    var wishlistNames: [String]

    @State private var name = ""
    @State private var shareWithFriends = AppSettings.shareRidesByDefault
    @State private var shareLive = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ride name", text: $name, prompt: Text("e.g. Rishikesh run"))
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(start)
                        .font(.title3)
                } footer: {
                    Text("Every photo and video you take until you end the ride goes into a Photos album with this name.")
                }

                let suggestions = RideNaming.suggestions(for: name, recentRideNames: recentNames, wishlistSpotNames: wishlistNames)
                if !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) { name = suggestion }
                        }
                    }
                }

                // Decided here, before moving: nothing on the riding screen asks for attention.
                if recorder.friends.availability == .available {
                    Section {
                        Toggle("Share with friends after the ride", isOn: $shareWithFriends)
                        Toggle("Let friends follow live", isOn: $shareLive)
                    } footer: {
                        Text(shareLive
                             ? "Friends see where you are about once a minute until you end the ride. Your start and privacy zones stay hidden."
                             : "Photos are never shared automatically; pick them after the ride.")
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: start)
                        .bold()
                        .disabled(recorder.phase != .idle)
                }
            }
            .onAppear { focused = true }
        }
    }

    private func start() {
        Task {
            do {
                try await recorder.start(name: name, shareWithFriends: shareWithFriends, shareLive: shareLive)
                dismiss()
            } catch {
                self.error = "Couldn't start the ride: \(error.localizedDescription)"
            }
        }
    }
}

