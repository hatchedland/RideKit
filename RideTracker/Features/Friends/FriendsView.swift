import MapKit
import RideKit
import SwiftUI

/// Friends: who's riding now, friends' recent rides, and the spots they stopped at.
struct FriendsView: View {
    @Environment(RideRecorder.self) private var recorder
    @State private var confirmingLeave: FriendSnapshot?
    @State private var showingFind = false

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
                            Button("Find riders", systemImage: "person.badge.plus") { showingFind = true }
                        }
                    }
                }
                .sheet(isPresented: $showingFind) { FindRidersView() }
                .confirmationDialog(
                    "Remove \(confirmingLeave?.name ?? "") as a friend?",
                    isPresented: Binding(get: { confirmingLeave != nil }, set: { if !$0 { confirmingLeave = nil } }),
                    titleVisibility: .visible,
                    presenting: confirmingLeave
                ) { friend in
                    Button("Remove friend", role: .destructive) {
                        Task { await friends.unfriend(friend) }
                    }
                } message: { _ in
                    Text("Neither of you will see the other's rides any more. You can send a new request any time.")
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

    @ViewBuilder
    private var content: some View {
        switch friends.availability {
        case .checking:
            FriendsSkeletonList()
        case .signedOut:
            ContentUnavailableView("Signing in…", systemImage: "person.crop.circle")
        case .available:
            if friends.lastRefresh == nil && friends.lastError == nil {
                // First load: show the shape of the feed instead of a bare spinner or a false "no friends".
                FriendsSkeletonList()
            } else if friends.friends.isEmpty && friends.requests.isEmpty {
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
            Text("Find your riding group by their @handle and send a friend request. Friends see each other's shared rides — where you stopped, what you shot — and can follow each other live.")
        } actions: {
            Button { showingFind = true } label: {
                Text("Find riders")
                    .font(.headline)
                    .foregroundStyle(Brand.asphalt)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.highwayYellow)
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
                    HStack {
                        Label("You and \(name) are now friends.", systemImage: "checkmark.seal.fill")
                        Spacer()
                        Button("OK") { friends.justAccepted = nil }.buttonStyle(.borderless)
                    }
                }
            }

            if !friends.requests.isEmpty {
                Section("Requests") {
                    ForEach(friends.requests) { request in
                        RequestRow(request: request)
                    }
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
                        Button("Remove", role: .destructive) { confirmingLeave = friend }
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
    @State private var loading = true

    var body: some View {
        Color.secondary.opacity(0.15)
            .shimmering(loading)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .task(id: url) {
                loading = true
                image = await Task.detached(priority: .utility) { [url] in
                    UIImage(contentsOfFile: url.path())?.preparingThumbnail(of: CGSize(width: 400, height: 400))
                }.value
                loading = false
            }
    }
}

/// An incoming request (Accept / Decline) or one you sent (Cancel).
struct RequestRow: View {
    @Environment(RideRecorder.self) private var recorder
    let request: FriendRequest

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name).font(.headline)
                Text(request.incoming ? "@\(request.username) wants to be friends" : "@\(request.username) · request sent")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if request.incoming {
                Button("Decline") { Task { await recorder.friends.dismiss(request) } }
                    .buttonStyle(.bordered)
                Button {
                    Task { await recorder.friends.accept(request) }
                } label: {
                    Text("Accept").foregroundStyle(Brand.asphalt)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.highwayYellow)
            } else {
                Button("Cancel") { Task { await recorder.friends.dismiss(request) } }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
    }
}

/// Search riders by @handle and send friend requests, all inside the app.
struct FindRidersView: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [RiderResult] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                if AccountService.normalisedHandle(query).count < 2 {
                    Text("Type at least two letters of their @handle.").foregroundStyle(.secondary)
                } else if results.isEmpty && !searching {
                    Text("No rider with a handle starting “@\(AccountService.normalisedHandle(query))”.").foregroundStyle(.secondary)
                }
                ForEach(results) { rider in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rider.displayName.isEmpty ? "Rider" : rider.displayName).font(.headline)
                            Text("@\(rider.username)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        action(for: rider)
                    }
                }
                if let error = recorder.friends.lastError {
                    Text(error).font(.footnote).foregroundStyle(Brand.signal)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "@handle")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Find riders")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                searching = true
                results = await recorder.friends.search(query)
                searching = false
            }
        }
    }

    @ViewBuilder
    private func action(for rider: RiderResult) -> some View {
        switch recorder.friends.relationship(with: rider.id) {
        case .friend:
            Label("Friends", systemImage: "checkmark").foregroundStyle(.secondary).font(.subheadline)
        case .requested:
            Text("Requested").foregroundStyle(.secondary).font(.subheadline)
        case .wantsToBeFriends:
            if let request = recorder.friends.requests.first(where: { $0.riderID == rider.id && $0.incoming }) {
                Button {
                    Task { await recorder.friends.accept(request) }
                } label: { Text("Accept").foregroundStyle(Brand.asphalt) }
                .buttonStyle(.borderedProminent).tint(Brand.highwayYellow).controlSize(.small)
            }
        case .none:
            Button {
                Task { await recorder.friends.sendRequest(to: rider) }
            } label: { Text("Add friend").foregroundStyle(Brand.asphalt) }
            .buttonStyle(.borderedProminent).tint(Brand.highwayYellow).controlSize(.small)
        }
    }
}
