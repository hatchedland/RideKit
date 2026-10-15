import RideKit
import SwiftUI

/// Ride detail section: whether friends can see this ride, and which photos go with it.
struct RideFriendsSection: View {
    let ride: Ride
    @Environment(RideRecorder.self) private var recorder
    @State private var choosing = false
    @State private var working = false

    private var friends: FriendsService { recorder.friends }

    var body: some View {
        if friends.availability == .available {
            Section {
                if ride.sharedWithFriends {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Friends can see this ride", systemImage: "person.2.fill")
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Choose photos to share", systemImage: "photo.on.rectangle") { choosing = true }
                        .disabled((ride.media ?? []).isEmpty)
                    Button("Stop sharing", systemImage: "eye.slash", role: .destructive) {
                        run { await friends.unpublish(ride) }
                    }
                } else {
                    Button("Share with friends", systemImage: "person.2") { choosing = true }
                }
                if working { ProgressView() }
            } header: {
                Text("Friends")
            } footer: {
                Text("Friends you invited see the route, stops and soundtrack. The start, the end and your privacy zones are hidden. Photos are shared only if you pick them.")
            }
            .sheet(isPresented: $choosing) {
                ShareRideSheet(ride: ride)
            }
        }
    }

    private var detail: String {
        let photos = (ride.media ?? []).filter(\.sharedWithFriends).count
        let photoText = photos == 0 ? "no photos" : photos == 1 ? "1 photo" : "\(photos) photos"
        if let sharedAt = ride.sharedAt {
            return "With \(photoText) · updated \(sharedAt.formatted(.relative(presentation: .named)))"
        }
        return "Waiting to upload · \(photoText)"
    }

    private func run(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            try? recorder.context.save()
            working = false
        }
    }
}

/// Pick the photos friends get with the ride. Nothing is picked until you pick it.
struct ShareRideSheet: View {
    let ride: Ride
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var sharing = false

    private var media: [MediaLink] { (ride.media ?? []).sorted { $0.capturedAt < $1.capturedAt } }
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(media.isEmpty
                         ? "This ride has no photos. Friends will see the route, stops and soundtrack."
                         : "Tap the photos friends should see. Copies are stored in your iCloud and shared only with friends you invited.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(media) { link in
                            Button { toggle(link) } label: {
                                AssetThumbnail(localIdentifier: link.localIdentifier, isVideo: link.isVideo)
                                    .aspectRatio(1, contentMode: .fill)
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: selected.contains(link.localIdentifier) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Brand.asphalt, Brand.highwayYellow)
                                            .padding(6)
                                            .shadow(radius: 2)
                                    }
                                    .opacity(selected.contains(link.localIdentifier) ? 1 : 0.75)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(link.isVideo ? "Video" : "Photo")
                            .accessibilityAddTraits(selected.contains(link.localIdentifier) ? .isSelected : [])
                        }
                    }
                    if media.contains(where: \.isVideo) {
                        Text("Videos are shared as a still frame.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(selected.isEmpty ? "Share with friends" : "\(selected.count) selected")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sharing {
                        ProgressView()
                    } else {
                        Button("Share", action: share).bold()
                    }
                }
                if !media.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button(selected.count == media.count ? "Select none" : "Select all") {
                            selected = selected.count == media.count ? [] : Set(media.map(\.localIdentifier))
                        }
                    }
                }
            }
            .onAppear { selected = Set(media.filter(\.sharedWithFriends).map(\.localIdentifier)) }
        }
    }

    private func toggle(_ link: MediaLink) {
        if selected.contains(link.localIdentifier) {
            selected.remove(link.localIdentifier)
        } else {
            selected.insert(link.localIdentifier)
        }
    }

    private func share() {
        sharing = true
        for link in media { link.sharedWithFriends = selected.contains(link.localIdentifier) }
        Task {
            await recorder.friends.publish(ride)
            try? recorder.context.save()
            sharing = false
            dismiss()
        }
    }
}
