import ActivityKit
import Foundation

/// Starts, updates and ends the ride's Live Activity (Lock Screen + Dynamic Island).
@MainActor
final class LiveActivityController {
    private var activity: Activity<RideActivityAttributes>?
    private var lastPushed: Date = .distantPast
    private var lastState: RideActivityAttributes.ContentState?

    /// Updates more often than this are skipped (unless something important changed) to save battery.
    private let minimumInterval: TimeInterval = 4

    func start(rideName: String, startedAt: Date, state: RideActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(state: state)
        let attributes = RideActivityAttributes(rideName: rideName, startedAt: startedAt)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        lastState = state
        lastPushed = .now
    }

    /// Re-attaches to an activity left over from before the app was killed.
    func adoptExisting() -> Bool {
        activity = Activity<RideActivityAttributes>.activities.first
        return activity != nil
    }

    func update(_ state: RideActivityAttributes.ContentState, force: Bool = false) {
        guard let activity else { return }
        let important = state.isPaused != lastState?.isPaused
            || state.albumItemCount != lastState?.albumItemCount
            || state.lastSpotName != lastState?.lastSpotName
        guard force || important || Date.now.timeIntervalSince(lastPushed) >= minimumInterval else { return }
        lastState = state
        lastPushed = .now
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Shows a Lock Screen alert, e.g. "Chandratal Lake (wishlist) is 1.8 km away".
    func alert(title: String, body: String, state: RideActivityAttributes.ContentState) {
        guard let activity else { return }
        lastState = state
        lastPushed = .now
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil),
                alertConfiguration: AlertConfiguration(title: "\(title)", body: "\(body)", sound: .default)
            )
        }
    }

    func end(state: RideActivityAttributes.ContentState? = nil) {
        let activities = Activity<RideActivityAttributes>.activities
        activity = nil
        lastState = nil
        Task {
            for activity in activities {
                let final = state.map { ActivityContent(state: $0, staleDate: nil) }
                await activity.end(final, dismissalPolicy: .default)
            }
        }
    }
}
