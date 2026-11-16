import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.Key.hasSeenSafetyNotice) private var hasSeenSafetyNotice = false

    enum TabID: String, Hashable { case ride, spots, rides, friends, settings }
    #if DEBUG
    /// Debug: `-openTab rides` (or spots, friends, settings) opens that tab, for checking screens.
    @State private var selection: TabID = TabID(rawValue: UserDefaults.standard.string(forKey: "openTab") ?? "")
        ?? (SampleRide.requested ? .rides : .ride)
    #else
    @State private var selection: TabID = .ride
    #endif

    @Environment(AccountService.self) private var account
    @Environment(SyncService.self) private var sync

    var body: some View {
        switch account.state {
        case .checking:
            // Reading the saved session; a blank asphalt screen, not a sign-in flash.
            Brand.page.ignoresSafeArea()
        case .signedOut, .linkSent:
            SignInView()
        case .signedIn where account.needsHandle:
            HandleSetupView()
        case .signedIn:
            app
        }
    }

    @ViewBuilder private var app: some View {
        @Bindable var recorder = recorder

        TabView(selection: $selection) {
            Tab("Ride", image: "tab-ride", value: .ride) {
                RecordView()
            }
            Tab("Spots", image: "tab-spots", value: .spots) {
                SpotsView()
            }
            Tab("Rides", image: "tab-rides", value: .rides) {
                RidesListView()
            }
            Tab("Friends", image: "tab-friends", value: .friends) {
                FriendsView()
            }
            Tab("Settings", image: "tab-settings", value: .settings) {
                SettingsView()
            }
        }
        .sheet(item: finishedRide) { ride in
            NavigationStack {
                RideSummaryView(ride: ride)
            }
        }
        .sheet(isPresented: .constant(!hasSeenSafetyNotice)) {
            SafetyNoticeView { hasSeenSafetyNotice = true }
                .interactiveDismissDisabled()
        }
        .alert(
            "Your last ride was interrupted",
            isPresented: Binding(get: { recorder.interruptedRide != nil }, set: { _ in }),
            presenting: recorder.interruptedRide
        ) { _ in
            Button("Resume ride") { recorder.resumeInterrupted() }
            Button("Finish and save") { Task { await recorder.finishInterrupted() } }
        } message: { ride in
            Text("“\(ride.name)” stopped recording unexpectedly. Everything up to that point is safe.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await recorder.runLateSweeps(); await syncIfIdle() } }
        }
        // Everything lives in the rider's account: sync on sign-in, after each ride, and every
        // minute while the app is open. Not during a ride (battery, data); the ride syncs at End.
        .task {
            await syncIfIdle()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await syncIfIdle()
            }
        }
        .onChange(of: recorder.finishedRideID) { _, id in
            if id != nil { Task { await syncIfIdle() } }
        }
        .task {
            await recorder.friends.start(isRidingLive: recorder.isSharingLive)
        }
        .onChange(of: recorder.isRiding) { _, riding in
            if riding { selection = .ride }
        }
    }

    /// Looks up the just-finished ride for the summary sheet.
    private var finishedRide: Binding<Ride?> {
        Binding(
            get: {
                guard let id = recorder.finishedRideID else { return nil }
                return try? recorder.context.fetch(FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })).first
            },
            set: { if $0 == nil { recorder.finishedRideID = nil } }
        )
    }
}

/// Shown once at first launch.
struct SafetyNoticeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Eyes on the road")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                Label("Mount your phone before you start. Don't handle it while moving.", systemImage: "iphone.gen3")
                Label("Mark spots from the Lock Screen, the Action button or Siri — one tap, no looking.", systemImage: "hand.tap")
                Label("Name spots and sort photos after you've stopped.", systemImage: "pause.circle")
            }
            .font(.body)
            Spacer()
            Button(action: onContinue) {
                Text("I'll ride safe").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
    }
}

extension RootView {
    func syncIfIdle() async {
        guard recorder.phase == .idle, account.isSignedIn else { return }
        await sync.sync()
    }
}
