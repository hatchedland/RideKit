import CloudKit
import MapKit
import RideKit
import SwiftUI

/// Friends: who's riding now, friends' recent rides, and the spots they stopped at.
struct FriendsView: View {
    @Environment(RideRecorder.self) private var recorder
    @State private var manageError: String?
    @State private var confirmingLeave: FriendSnapshot?

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
                                ShareLink(item: FriendsInvite(), preview: SharePreview("Ride with me on Ride Tracker")) {
                                    Label("Invite a friend", systemImage: "person.badge.plus")
                                }
                                Button("Who sees my rides", systemImage: "person.2") {
                                    Task {
                                        do { try await ManageFriends.present() } catch { manageError = FriendsService.message(for: error) }
                                    }
                                }
                            } label: {
                                Label("Friends", systemImage: "person.badge.plus")
                            }
                        }
                    }
                }
                .alert("Couldn't open your friends list", isPresented: Binding(get: { manageError != nil }, set: { if !$0 { manageError = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(manageError ?? "")
                }
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
            // Keep live dots fresh while the tab is open. CloudKit isn't a socket; a minute is plenty.
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
            ProgressView()
        case .unsupportedBuild:
            ContentUnavailableView {
                Label("Friends need iCloud", systemImage: "icloud.slash")
            } description: {
                Text("This is the free Personal build, which can't use iCloud. Friends work in the App Store and TestFlight builds.")
            }
        case .needsICloud:
            ContentUnavailableView {
                Label("Sign in to iCloud", systemImage: "icloud")
            } description: {
                Text("Friends share rides through iCloud. Sign in under Settings › your name, then come back.")
            } actions: {
                Button("Check again") { Task { await friends.start(isRidingLive: recorder.isSharingLive) } }
            }
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
            ShareLink(item: FriendsInvite(), preview: SharePreview("Ride with me on Ride Tracker")) {
                Text("Invite a friend")
                    .font(.headline)
                    .foregroundStyle(Brand.asphalt)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.highwayYellow)
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
                            ShareLink(item: FriendsInvite(), preview: SharePreview("Ride with me on Ride Tracker")) {
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

/// The invitation sent through the share sheet: a CloudKit share of the rider's Friends zone.
struct FriendsInvite: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { _ in
            .prepareShare(container: FriendsCloud.container) {
                try await FriendsService.inviteShare()
            }
        }
    }
}

/// Apple's participant list for the rider's share: see who follows your rides and remove anyone.
/// `UICloudSharingController` must be presented modally, so it goes on top of the current screen.
@MainActor
enum ManageFriends {
    private static let delegate = Delegate()

    static func present() async throws {
        let share = try await FriendsService.inviteShare()
        let controller = UICloudSharingController(share: share, container: FriendsCloud.container)
        controller.delegate = delegate
        controller.availablePermissions = [.allowPrivate, .allowReadOnly]
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(controller, animated: true)
    }

    final class Delegate: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}
        func itemTitle(for csc: UICloudSharingController) -> String? {
            MainActor.assumeIsolated {
                AppSettings.riderName.isEmpty ? "My rides" : "\(AppSettings.riderName)’s rides"
            }
        }
    }
}
