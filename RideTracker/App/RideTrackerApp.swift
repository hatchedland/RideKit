import AppIntents
import SwiftData
import SwiftUI

@main
struct RideTrackerApp: App {
    private let container: ModelContainer
    @State private var recorder: RideRecorder

    init() {
        let container = Persistence.makeContainer()
        self.container = container
        _recorder = State(initialValue: RideRecorder(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(recorder)
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
