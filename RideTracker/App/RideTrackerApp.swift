import AppIntents
import SwiftData
import SwiftUI

@main
struct RideTrackerApp: App {
    private let container: ModelContainer
    @State private var recorder: RideRecorder
    @State private var account: AccountService
    @State private var sync: SyncService

    init() {
        let container = Persistence.makeContainer()
        self.container = container
        #if DEBUG
        SampleRide.seedIfRequested(into: container.mainContext)
        #endif
        let recorder = RideRecorder(context: container.mainContext)
        _recorder = State(initialValue: recorder)
        let account = AccountService()
        _account = State(initialValue: account)
        let sync = SyncService(context: container.mainContext, account: account)
        _sync = State(initialValue: sync)
        recorder.friends.configure(account: account, sync: sync)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(recorder)
                .environment(account)
                .environment(sync)
                // Sign-in links from email: ridetracker://auth-callback…
                // Sign-in links (ridetracker://auth-callback…) and friend invites (ridetracker://invite/<code>).
                .onOpenURL { url in
                    Task {
                        if url.host() == "invite" {
                            await recorder.friends.acceptInvite(from: url.absoluteString)
                        } else {
                            await account.handle(url)
                        }
                    }
                }
                .task { RideControl.isSignedIn = { [account] in account.isSignedIn } }
        }
        .modelContainer(container)
    }
}

struct RideTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkSpotIntent(),
            phrases: ["Mark spot in \(.applicationName)", "Save this place in \(.applicationName)"],
            shortTitle: "Mark Spot",
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: StartRideIntent(),
            phrases: ["Start a ride in \(.applicationName)", "Start riding with \(.applicationName)"],
            shortTitle: "Start Ride",
            systemImageName: "road.lanes"
        )
        AppShortcut(
            intent: EndRideIntent(),
            phrases: ["End ride in \(.applicationName)", "Stop ride in \(.applicationName)"],
            shortTitle: "End Ride",
            systemImageName: "flag.checkered"
        )
    }
}
