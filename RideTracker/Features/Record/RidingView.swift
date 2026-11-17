import SwiftUI

/// The screen while riding: the map edge to edge, with the bike's instruments floating on it —
/// a compact band of numbers at the top, one row of controls at the bottom (Pause · **Mark spot** ·
/// End), alerts sliding in under the numbers. The tab bar is hidden while riding.
struct RidingView: View {
    @Environment(RideRecorder.self) private var recorder
    @State private var confirmingEnd = false
    /// Heights of the floating bands, so the map keeps the rider's dot and Google logo between them.
    @State private var topHeight: CGFloat = 200
    /// Bottom of the numbers band, for the scrim behind it.
    @State private var headerBottom: CGFloat = 160
    @State private var controlsHeight: CGFloat = 120

    private var usesMetric: Bool { AppSettings.usesMetric }

    var body: some View {
        @Bindable var recorder = recorder

        GoogleMapView(
            lines: lines,
            pins: destinationPin,
            camera: .follow(recorder.track.last?.coordinate, bearing: heading),
            showsUserLocation: true,
            padding: UIEdgeInsets(top: topHeight, left: 0, bottom: controlsHeight, right: 0)
        )
        .ignoresSafeArea()
        // Near-solid asphalt behind the numbers so they read at a glance on any map tile, fading out
        // just below the status chips.
        .overlay(alignment: .top) {
            LinearGradient(stops: [.init(color: Brand.asphalt.opacity(0.94), location: 0),
                                   .init(color: Brand.asphalt.opacity(0.88), location: 0.7),
                                   .init(color: Brand.asphalt.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: headerBottom + 72)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                header
                    .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .local).height }) { headerBottom = $0 }
                // Alerts are about the world around the rider, so they go on the map, never over
                // the numbers.
                statusBadges
                if let banner = recorder.banner { bannerView(banner) }
            }
            .padding(.horizontal)
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }) { topHeight = $0 }
        }
        .overlay(alignment: .bottom) {
            controls
                .background(alignment: .bottom) {
                    fade(towards: .bottom).padding(.top, -40).ignoresSafeArea(edges: .bottom)
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { controlsHeight = $0 + 34 }
        }
        .background(Brand.asphalt)
        // The riding screen is the bike's instrument cluster: always dark, yellow on asphalt.
        .environment(\.colorScheme, .dark)
        // Other tabs are useless at speed and easy to hit by accident.
        .toolbarVisibility(.hidden, for: .tabBar)
        .animation(.spring, value: recorder.banner)
        .sensoryFeedback(.success, trigger: recorder.spotsMarkedThisRide)
        .sensoryFeedback(.impact(weight: .heavy), trigger: recorder.isPaused)
        .persistentSystemOverlays(.hidden)
        .confirmationDialog("End this ride?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End ride", role: .destructive) { Task { await recorder.stop() } }
        } message: {
            Text("The Photos album will be finished with everything you took during the ride.")
        }
    }

    /// Asphalt behind the floating bands, fading into the map so the numbers stay readable on any tile.
    private func fade(towards edge: VerticalEdge) -> some View {
        LinearGradient(colors: [Brand.asphalt, Brand.asphalt.opacity(0.92), Brand.asphalt.opacity(0)],
                       startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top)
    }

    /// The road still ahead (Google's two-wheeler route) in chalk, under the road ridden in yellow.
    private var lines: [MapLine] {
        var lines: [MapLine] = []
        if recorder.routeAhead.count > 1 {
            lines.append(MapLine(id: "ahead", coordinates: recorder.routeAhead, color: Brand.chalk.opacity(0.55), width: 6))
        }
        if recorder.track.count > 1 {
            lines.append(MapLine(id: "ridden", coordinates: recorder.track.map(\.coordinate), color: Brand.highwayYellow, width: 6))
        }
        return lines
    }

    private var destinationPin: [MapPin] {
        guard let destination = recorder.active?.destination else { return [] }
        return [MapPin(id: "destination", coordinate: destination.coordinate, title: destination.name,
                       systemImage: "flag.checkered", tint: Brand.highwayYellow)]
    }

    /// "TO GO · 4:40 PM" once there's a route to estimate from.
    private var toGoLabel: String {
        guard let seconds = recorder.routeRemainingSeconds, !recorder.hasArrived else { return "To go" }
        return "To go · \(Date.now.addingTimeInterval(seconds).formatted(date: .omitted, time: .shortened))"
    }

    /// The map turns with the direction of travel; GPS reports a negative course when it doesn't know.
    private var heading: Double? {
        guard let course = recorder.track.last?.course, course >= 0 else { return nil }
        return course
    }

    /// Stays long enough to catch with a glance between looks at the road.
    private func bannerView(_ banner: RideRecorder.Banner) -> some View {
        VStack(spacing: 2) {
            Label(banner.text, systemImage: banner.systemImage)
                .font(.headline)
            if let detail = banner.detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thickMaterial, in: .rect(cornerRadius: 22))
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: banner.id) {
            try? await Task.sleep(for: .seconds(6))
            recorder.banner = nil
        }
    }

    /// Speed big on the left, the three stats stacked on the right. The ride's name isn't needed
    /// mid-ride (it's on the Lock Screen and the summary).
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.speed(recorder.isPaused ? 0 : recorder.stats.currentSpeedMps, usesMetric: usesMetric))
                    .font(Brand.readout(80))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Format.speedUnit(usesMetric: usesMetric))
                    .font(Brand.label)
                    .foregroundStyle(Brand.highwayYellow)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                stat(Format.distance(recorder.stats.distanceMeters, usesMetric: usesMetric), "Distance")
                if let start = recorder.active?.startedAt {
                    statRow(label: "Time") {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    }
                }
                // With a destination, "to go" matters more mid-ride than top speed.
                if recorder.active?.destination != nil {
                    stat(recorder.hasArrived ? "Here" : recorder.remainingMeters.map { Format.shortDistance($0, usesMetric: usesMetric) } ?? "–",
                         toGoLabel)
                } else {
                    stat(Format.speed(recorder.stats.maxSpeedMps, usesMetric: usesMetric), "Max")
                }
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        statRow(label: label) { Text(value) }
    }

    /// "12.4 km  DISTANCE": value and label on one line, right-aligned into a column.
    private func statRow(label: String, @ViewBuilder value: () -> Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            value()
                .font(Brand.stat)
                .monospacedDigit()
            Text(label.uppercased())
                .font(Brand.label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var statusBadges: some View {
        HStack(spacing: 8) {
            if recorder.isPaused {
                badge(recorder.isManuallyPaused ? "Paused" : "Auto-paused", "pause.fill", .highlight)
            }
            if recorder.isSharingLive {
                badge("Live", "person.2.fill")
                    .accessibilityLabel("Friends can follow this ride")
            }
            badge("\(recorder.albumItemCount)", "photo.on.rectangle")
            if recorder.spotsMarkedThisRide > 0 {
                badge("\(recorder.spotsMarkedThisRide)", "mappin")
            }
            if recorder.songsThisRide > 0 {
                badge("\(recorder.songsThisRide)", "music.note")
            }
            if recorder.locationDenied {
                badge("Location off", "location.slash", .problem)
            } else if recorder.gpsUnavailable {
                badge("Weak GPS", "antenna.radiowaves.left.and.right.slash", .problem)
            }
        }
    }

    private enum BadgeStyle { case info, highlight, problem }

    /// Counters are quiet asphalt chips; only state that needs attention gets colour.
    private func badge(_ text: String, _ image: String, _ style: BadgeStyle = .info) -> some View {
        let (background, foreground): (Color, Color) = switch style {
        case .info: (Brand.asphalt.opacity(0.85), Brand.chalk)
        case .highlight: (Brand.highwayYellow, Brand.asphalt)
        case .problem: (Brand.signal, .white)
        }
        return Label(text, systemImage: image)
            .font(.subheadline.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: .capsule)
            .foregroundStyle(foreground)
    }

    /// One row: Pause and End are used about once a ride, so they're round buttons beside the big
    /// **Mark spot**, which keeps its height and its place under the thumb. End still confirms.
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                recorder.togglePause()
            } label: {
                Image(systemName: recorder.isManuallyPaused ? "play.fill" : "pause.fill")
                    .font(.title2.bold())
                    .foregroundStyle(recorder.isManuallyPaused ? Brand.asphalt : Brand.highwayYellow)
                    .frame(width: 64, height: 64)
                    .background(recorder.isManuallyPaused ? Brand.highwayYellow : Color.white.opacity(0.14), in: .circle)
            }
            .accessibilityLabel(recorder.isManuallyPaused ? "Resume" : "Pause")

            Button {
                recorder.markSpot()
            } label: {
                // Never truncated: drops the icon before the words get cut.
                ViewThatFits(in: .horizontal) {
                    Label("Mark spot", systemImage: "mappin.and.ellipse")
                    Text("Mark spot")
                }
                .font(.title2.bold().width(.expanded))
                .lineLimit(1)
                .foregroundStyle(Brand.asphalt)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 84)
                .background(Brand.highwayYellow, in: .capsule)
            }

            Button {
                confirmingEnd = true
            } label: {
                Image(systemName: "flag.checkered")
                    .font(.title2.bold())
                    .foregroundStyle(Brand.signal)
                    .frame(width: 64, height: 64)
                    .background(Brand.signal.opacity(0.22), in: .circle)
            }
            .disabled(recorder.phase == .finishing)
            .accessibilityLabel("End ride")
        }
        .buttonStyle(PressableStyle())
        .padding(.horizontal)
        .padding(.bottom, 4)
        .overlay {
            if recorder.phase == .finishing {
                ProgressView("Finishing album…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
    }
}

/// Exact sizes (the system bordered styles pad their labels) with a press dip for feedback.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(.rect)
    }
}
