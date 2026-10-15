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
                // Opaque: a see-through card turns highway yellow into olive over busy wallpapers.
                .activityBackgroundTint(Brand.asphalt)
                .activitySystemActionForegroundColor(Brand.chalk)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SpeedReadout(state: context.state, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Stat(label: "DISTANCE", value: Text(context.state.distanceText), alignment: .trailing)
                        Stat(label: "TIME", value: RideTimer(startedAt: context.attributes.startedAt), alignment: .trailing)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RideControls(state: context.state, height: 44)
                        .padding(.top, 6)
                }
            } compactLeading: {
                Text(context.state.isPaused ? "II" : context.state.speedText)
                    .font(.body.weight(.heavy).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(Brand.highwayYellow)
            } compactTrailing: {
                Text(context.state.distanceText).monospacedDigit()
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "road.lanes")
                    .foregroundStyle(Brand.highwayYellow)
            }
            .keylineTint(Brand.highwayYellow)
        }
    }
}

/// The Lock Screen card: an instrument cluster, readable at a glance from a handlebar mount.
/// iOS crops Lock Screen Live Activities at 160 pt, so the rows add up to ~150 pt:
/// 12 + header 18 + 8 + readouts 48 + 8 + buttons 44 + 12.
///
/// ```
/// [km-stone] Ride name ................ [LIVE] [PAUSED] [📷 3]
/// 42 KM/H              │ DISTANCE    TIME
///                      │ 12.4 km     1:13:05
/// [   📍  Mark spot   (yellow, 44 pt)   ] [ ⏸ ]
/// ```
private struct LockScreenRideView: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MilestoneMark().frame(width: 10)
                Text(attributes.rideName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if state.sharingLive == true {
                    Chip(text: "LIVE", style: .quiet)
                        .accessibilityLabel("Friends can follow this ride")
                }
                if state.isPaused {
                    Chip(text: "PAUSED", style: .highlight)
                }
                if state.albumItemCount > 0 {
                    Label("\(state.albumItemCount)", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Brand.chalk.opacity(0.75))
                        .accessibilityLabel("\(state.albumItemCount) photos in the ride album")
                }
            }

            HStack(alignment: .center, spacing: 14) {
                SpeedReadout(state: state, size: 44, unitBeside: true)
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Brand.chalk.opacity(0.18))
                    .frame(width: 1, height: 36)
                Stat(label: "DISTANCE", value: Text(state.distanceText))
                Stat(label: "TIME", value: RideTimer(startedAt: attributes.startedAt))
                    .frame(minWidth: 72, alignment: .leading)
            }
            .frame(height: 48)

            RideControls(state: state, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(Brand.chalk)
    }
}

/// Speed is the glance number; while paused it steps back so "PAUSED" reads first.
private struct SpeedReadout: View {
    let state: RideActivityAttributes.ContentState
    let size: CGFloat
    /// The unit next to the number (Lock Screen, saves height) or under it (Dynamic Island).
    var unitBeside = false

    var body: some View {
        let layout = unitBeside
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        layout {
            Text(state.speedText)
                .font(Brand.readout(size))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(state.isPaused ? Brand.chalk.opacity(0.4) : Brand.chalk)
                .contentTransition(.numericText())
            Text(state.speedUnit.uppercased())
                .font(Brand.label)
                .foregroundStyle(Brand.chalk.opacity(0.6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.isPaused ? "Paused" : "\(state.speedText) \(state.speedUnit)")
    }
}

private struct Stat<Value: View>: View {
    let label: String
    let value: Value
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label)
                .font(Brand.label)
                .foregroundStyle(Brand.chalk.opacity(0.6))
            value
                .font(.headline.weight(.bold).width(.expanded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RideTimer: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .multilineTextAlignment(.leading)
    }
}

/// Mark spot is the one action that matters while riding: full-strength yellow, big, glove-sized.
private struct RideControls: View {
    let state: RideActivityAttributes.ContentState
    var height: CGFloat = 48

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: MarkSpotIntent()) {
                Label(markTitle, systemImage: "mappin.and.ellipse")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(Brand.asphalt)
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                    .background(Brand.highwayYellow, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button(intent: TogglePauseIntent()) {
                Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Brand.chalk)
                    .frame(width: 60, height: height)
                    .background(Brand.chalk.opacity(0.16), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isPaused ? "Resume ride" : "Pause ride")
        }
    }

    /// "Spot saved" for a moment after marking, then back to the action.
    private var markTitle: String {
        guard let last = state.lastSpotName, !last.isEmpty else { return "Mark spot" }
        return last.replacing("📍 ", with: "")
    }
}

private struct Chip: View {
    enum Style { case quiet, highlight }
    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy).width(.expanded))
            .foregroundStyle(style == .highlight ? Brand.asphalt : Brand.chalk)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(style == .highlight ? Brand.highwayYellow : Brand.chalk.opacity(0.18), in: .capsule)
    }
}
