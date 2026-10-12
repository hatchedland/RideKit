import AppIntents
import Foundation

/// Connects intents to the running app without the widget extension having to compile the app's
/// recording code. The app installs the handlers at launch; inside the widget process they stay nil.
/// `LiveActivityIntent`s always perform in the app process, so the handlers are present there.
@MainActor
enum RideControl {
    static var markSpot: (() async -> String?)?
    static var startRide: ((String) async throws -> Void)?
    static var endRide: (() async -> Void)?
    static var togglePause: (() async -> Void)?
}

enum RideIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case noRideInProgress

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: "Ride Tracker isn't ready yet. Open the app and try again."
        case .noRideInProgress: "No ride in progress. Start a ride first."
        }
    }
}

/// "Mark spot": from the Lock Screen Live Activity, the Action button, Siri or Shortcuts.
/// Saves the current location instantly; the rider names it later.
struct MarkSpotIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Spot"
    static let description = IntentDescription("Saves your current location as a spot with a Google Maps link.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let markSpot = RideControl.markSpot else { throw RideIntentError.appNotReady }
        guard let name = await markSpot() else { throw RideIntentError.noRideInProgress }
        return .result(dialog: "Saved \(name).")
    }
}

struct TogglePauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Ride"

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let togglePause = RideControl.togglePause else { throw RideIntentError.appNotReady }
        await togglePause()
        return .result()
    }
}

struct StartRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Ride"
    static let description = IntentDescription("Starts recording a ride and creates its Photos album.")
    static let openAppWhenRun = true

    @Parameter(title: "Ride name", default: "")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let startRide = RideControl.startRide else { throw RideIntentError.appNotReady }
        try await startRide(name)
        return .result(dialog: "Ride started. Ride safe!")
    }
}

struct EndRideIntent: AppIntent {
    static let title: LocalizedStringResource = "End Ride"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let endRide = RideControl.endRide else { throw RideIntentError.appNotReady }
        await endRide()
        return .result()
    }
}
