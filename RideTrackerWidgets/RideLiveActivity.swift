import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct RideTrackerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

/// Lock Screen + Dynamic Island while riding. "Mark spot" works without unlocking the phone.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenRideView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Brand.asphalt.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.state.speedText).font(.title.bold()).monospacedDigit()
                        Text(context.state.speedUnit).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text(context.state.distanceText).font(.title3.bold()).monospacedDigit()
                        Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
                            .font(.caption).monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MarkSpotButton(lastSpot: context.state.lastSpotName)
                }
            } compactLeading: {
                Text(context.state.speedText).monospacedDigit().bold()
            } compactTrailing: {
                Text(context.state.distanceText).monospacedDigit()
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "road.lanes")
            }
            .keylineTint(Brand.highwayYellow)
        }
    }
}

private struct LockScreenRideView: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(attributes.rideName, systemImage: state.isPaused ? "pause.circle.fill" : "road.lanes")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Label("\(state.albumItemCount)", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(state.speedText).font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(state.speedUnit).font(.caption).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(state.distanceText).font(.title2.bold()).monospacedDigit()
                    Text(timerInterval: attributes.startedAt...Date.distantFuture, countsDown: false)
                        .font(.subheadline).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
            HStack(spacing: 10) {
                MarkSpotButton(lastSpot: state.lastSpotName)
                Button(intent: TogglePauseIntent()) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 44, height: 36)
                }
                .tint(.gray)
            }
        }
        .padding()
        .foregroundStyle(.white)
    }
}

private struct MarkSpotButton: View {
    let lastSpot: String?

    var body: some View {
        Button(intent: MarkSpotIntent()) {
            Label(lastSpot ?? "Mark spot", systemImage: "mappin.and.ellipse")
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(Brand.asphalt)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .tint(Brand.highwayYellow)
    }
}
