import ActivityKit
import Foundation

/// Starts, updates and ends the ride's Live Activity (Lock Screen + Dynamic Island).
///
/// `Activity` isn't `Sendable`, so only its ID is kept on the main actor; the async ActivityKit
/// calls run in nonisolated helpers that look the activity up themselves.
@MainActor
final class LiveActivityController {
    private typealias State = RideActivityAttributes.ContentState

    private var activityID: String?
    private var lastPushed: Date = .distantPast
    private var lastState: State?

    /// Updates more often than this are skipped (unless something important changed) to save battery.
    private let minimumInterval: TimeInterval = 4

    func start(rideName: String, startedAt: Date, state: RideActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(state: state)
        let attributes = RideActivityAttributes(rideName: rideName, startedAt: startedAt)
        activityID = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        ).id
        lastState = state
        lastPushed = .now
    }

    /// Re-attaches to an activity left over from before the app was killed.
    func adoptExisting() -> Bool {
        activityID = Activity<RideActivityAttributes>.activities.first?.id
        return activityID != nil
    }

    func update(_ state: RideActivityAttributes.ContentState, force: Bool = false) {
        guard let activityID else { return }
        let important = state.isPaused != lastState?.isPaused
            || state.albumItemCount != lastState?.albumItemCount
            || state.lastSpotName != lastState?.lastSpotName
        guard force || important || Date.now.timeIntervalSince(lastPushed) >= minimumInterval else { return }
        lastState = state
        lastPushed = .now
        Task { await Self.push(state, to: activityID, alert: nil) }
    }

    /// Shows a Lock Screen alert, e.g. "Chandratal Lake (wishlist) is 1.8 km away".
    func alert(title: String, body: String, state: RideActivityAttributes.ContentState) {
        guard let activityID else { return }
        lastState = state
        lastPushed = .now
        Task { await Self.push(state, to: activityID, alert: (title, body)) }
    }

    func end(state: RideActivityAttributes.ContentState? = nil) {
        // Snapshot the IDs now, so an activity requested right after this call isn't ended.
        let ids = Activity<RideActivityAttributes>.activities.map(\.id)
        activityID = nil
        lastState = nil
        Task { await Self.end(ids, state: state) }
    }

    private nonisolated static func push(_ state: State, to id: String, alert: (title: String, body: String)?) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        if let alert {
            let configuration = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: alert.title),
                body: LocalizedStringResource(stringLiteral: alert.body),
                sound: .default
            )
            await activity.update(content, alertConfiguration: configuration)
        } else {
            await activity.update(content)
        }
    }

    private nonisolated static func end(_ ids: [String], state: State?) async {
        for activity in Activity<RideActivityAttributes>.activities where ids.contains(activity.id) {
            await activity.end(state.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: .default)
        }
    }
}
