import MapKit
import RideKit
import SwiftUI

/// Friends: who's riding now, friends' recent rides, and the spots they stopped at.
struct FriendsView: View {
    @Environment(RideRecorder.self) private var recorder
    @State private var confirmingLeave: FriendSnapshot?
    @State private var inviteText: String?
    @State private var preparingInvite = false
    @State private var showingFollowers = false

    private var friends: FriendsService { recorder.friends }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Friends")
                .navigationDestination(for: FriendRideRoute.self) { route in
                    if let item = friends.feed.first(where: { $0.ride.id == route.rideID }) {
                        FriendRideDetailView(friend: item.friend, item: item.ride)
                    } else {
                        ContentUnavailableView("Ride no longer shared", systemImage: "eye.slash")
                    }
                }
                .navigationDestination(for: FriendLiveRoute.self) { route in
                    LiveRideView(friendID: route.friendID)
                }
                .navigationDestination(for: FriendSpotsRoute.self) { _ in
                    FriendsSpotsMapView()
                }
                .toolbar {
                    if friends.availability == .available {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button("Invite a friend", systemImage: "person.badge.plus", action: invite)
                                Button("Paste invite", systemImage: "doc.on.clipboard", action: pasteInvite)
                                Button("Who sees my rides", systemImage: "person.2") { showingFollowers = true }
                            } label: {
                                Label("Friends", systemImage: "person.badge.plus")
                            }
                        }
                    }
                }
                .sheet(isPresented: Binding(get: { inviteText != nil }, set: { if !$0 { inviteText = nil } })) {
                    if let inviteText { ShareSheet(items: [inviteText]).presentationDetents([.medium, .large]) }
                }
                .sheet(isPresented: $showingFollowers) { FollowersView() }
                .confirmationDialog(
                    "Stop seeing \(confirmingLeave?.name ?? "")’s rides?",
                    isPresented: Binding(get: { confirmingLeave != nil }, set: { if !$0 { confirmingLeave = nil } }),
                    titleVisibility: .visible,
                    presenting: confirmingLeave
                ) { friend in
                    Button("Stop seeing their rides", role: .destructive) {
                        Task { await friends.leave(friend) }
                    }
                } message: { _ in
                    Text("They can still see your rides until you remove them under “Who sees my rides”.")
                }
        }
        .task { await friends.refresh() }
        .task(id: friends.availability) {
            // Keep live dots fresh while the tab is open; live positions change about once a minute.
            while !Task.isCancelled, friends.availability == .available {
                try? await Task.sleep(for: .seconds(30))
                await friends.refresh()
            }
        }
    }

    /// Makes a fresh invite and opens the share sheet with it.
    private func invite() {
        guard !preparingInvite else { return }
        preparingInvite = true
        Task {
            defer { preparingInvite = false }
            do { inviteText = try await friends.inviteMessage() } catch { friends.lastErrorFromInvite() }
        }
    }

    /// Accepts an invite copied from WhatsApp, Messages or anywhere else.
    private func pasteInvite() {
        let text = UIPasteboard.general.string ?? ""
        Task { await friends.acceptInvite(from: text) }
    }

    @ViewBuilder
    private var content: some View {
        switch friends.availability {
        case .checking:
            ProgressView()
        case .signedOut:
            ContentUnavailableView("Signing in…", systemImage: "person.crop.circle")
        case .available:
            if friends.friends.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ride with friends", systemImage: "person.2")
        } description: {
            Text("Invite your riding group. You'll see the rides they share — where they stopped, what they shot — and can follow them live when they choose. Only people you invite see your rides.")
        } actions: {
            Button(action: invite) {
                HStack {
                    if preparingInvite { ProgressView().tint(Brand.asphalt) }
                    Text("Invite a friend")
                }
                .font(.headline)
                .foregroundStyle(Brand.asphalt)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.highwayYellow)
            .disabled(preparingInvite)
            Button("Got an invite? Paste it", action: pasteInvite)
            if let error = friends.lastError {
                Text(error).font(.footnote).foregroundStyle(Brand.signal)
            }
            if friends.isRefreshing { ProgressView() }
        }
        .refreshable { await friends.refresh() }
    }

    private var list: some View {
        List {
            if let name = friends.justAccepted {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("You can now see \(name)’s rides.").font(.headline)
                        Text("Sharing is one-way. Invite \(name) back so they can see yours.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button(action: invite) {
                                Text("Invite \(name)").foregroundStyle(Brand.asphalt)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.highwayYellow)
                            Button("Not now") { friends.justAccepted = nil }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            let riding = friends.ridingNow()
            if !riding.isEmpty {
                Section("Riding now") {
                    ForEach(riding, id: \.friend.id) { item in
                        NavigationLink(value: FriendLiveRoute(friendID: item.friend.id)) {
                            LiveRideRow(name: item.friend.name, live: item.live)
                        }
                    }
                }
            }

            Section {
                NavigationLink(value: FriendSpotsRoute()) {
                    Label("Friends’ spots", systemImage: "map")
                }
            }

            Section("Recent rides") {
                let feed = friends.feed
                if feed.isEmpty {
                    Text("No shared rides yet.").foregroundStyle(.secondary)
                }
                ForEach(feed, id: \.ride.id) { item in
                    NavigationLink(value: FriendRideRoute(rideID: item.ride.id)) {
                        FriendRideRow(friend: item.friend.name, item: item.ride)
                    }
                }
            }

            Section("Friends") {
                ForEach(friends.friends) { friend in
                    HStack {
                        Label(friend.name, systemImage: "person.crop.circle")
                        Spacer()
                        Text(friend.rides.count == 1 ? "1 ride" : "\(friend.rides.count) rides")
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Stop seeing", role: .destructive) { confirmingLeave = friend }
                    }
                }
            }

            if let error = friends.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Brand.signal) }
            }
        }
        .refreshable { await friends.refresh() }
    }
}

struct FriendRideRoute: Hashable { var rideID: UUID }
struct FriendLiveRoute: Hashable { var friendID: String }
struct FriendSpotsRoute: Hashable {}

/// "Aman · Murthal run · 42 km · updated 1 min ago"
struct LiveRideRow: View {
    let name: String
    let live: LiveRide

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 12) {
                LiveBadge(status: live.status(at: context.date))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) is riding").font(.headline)
                    Text("\(live.rideName) · \(Format.distance(live.distanceMeters))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(LiveStatusText.describe(live.status(at: context.date), updatedAt: live.updatedAt, now: context.date))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The small status chip: yellow "LIVE" while fresh, quiet otherwise.
struct LiveBadge: View {
    let status: LiveRide.Status

    var body: some View {
        switch status {
        case .live:
            Text("LIVE")
                .font(.caption2.weight(.heavy).width(.expanded))
                .foregroundStyle(Brand.asphalt)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Brand.highwayYellow, in: .capsule)
        case .paused:
            Image(systemName: "pause.circle.fill").foregroundStyle(.secondary).font(.title3)
        case .delayed, .noSignal, .expired:
            Image(systemName: "antenna.radiowaves.left.and.right.slash").foregroundStyle(.secondary).font(.title3)
        }
    }
}

enum LiveStatusText {
    /// Calm wording: no signal in the hills is normal, not an emergency.
    static func describe(_ status: LiveRide.Status, updatedAt: Date, now: Date) -> String {
        switch status {
        case .live: "Updated \(updatedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
        case .paused: "Stopped · updated \(updatedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
        case .delayed(let minutes): "Last update \(minutes) min ago"
        case .noSignal(let since): "No signal since \(since.formatted(date: .omitted, time: .shortened)) — common on remote roads"
        case .expired: "Live sharing ended"
        }
    }
}

struct FriendRideRow: View {
    let friend: String
    let item: FriendSnapshot.Ride

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let first = item.ride.photos.first, let url = item.photoFiles[first.id] {
                    FilePhoto(url: url)
                } else {
                    ZStack {
                        Brand.asphalt
                        MilestoneMark().frame(width: 18)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.ride.name).font(.headline).lineLimit(1)
                Text("\(friend) · \(item.ride.endedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(summary).font(.caption.weight(.semibold).width(.expanded)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var parts = [Format.distance(item.ride.distanceMeters)]
        let named = item.ride.stops.filter { !$0.name.isEmpty }.count
        if named > 0 { parts.append(named == 1 ? "1 stop" : "\(named) stops") }
        if !item.ride.photos.isEmpty { parts.append("\(item.ride.photos.count) 📷") }
        return parts.joined(separator: " · ")
    }
}

/// A photo from a friend's ride, loaded from the local cache.
struct FilePhoto: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.15)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .task(id: url) {
                image = await Task.detached(priority: .utility) { [url] in
                    UIImage(contentsOfFile: url.path())?.preparingThumbnail(of: CGSize(width: 400, height: 400))
                }.value
            }
    }
}

/// The system share sheet for an invite message.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// "Who sees my rides": the people you invited. Removing someone stops them seeing your rides.
struct FollowersView: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var removing: Follower?

    var body: some View {
        NavigationStack {
            List {
                if recorder.friends.followers.isEmpty {
                    ContentUnavailableView("Nobody yet", systemImage: "person.2",
                                           description: Text("People you invite show up here. Only they see the rides you share."))
                }
                ForEach(recorder.friends.followers) { follower in
                    Label(follower.name, systemImage: "person.crop.circle")
                        .swipeActions {
                            Button("Remove", role: .destructive) { removing = follower }
                        }
                }
            }
            .navigationTitle("Who sees my rides")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await recorder.friends.refresh() }
            .confirmationDialog("Stop \(removing?.name ?? "") seeing your rides?",
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible, presenting: removing) { follower in
                Button("Remove \(follower.name)", role: .destructive) { Task { await recorder.friends.removeFollower(follower) } }
            } message: { _ in
                Text("Rides you've already shared disappear for them. Invite them again any time.")
            }
        }
    }
}
