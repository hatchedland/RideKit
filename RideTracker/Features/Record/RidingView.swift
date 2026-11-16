import SwiftUI

/// The screen while riding: huge glanceable numbers, a big **Mark spot** button, nothing fiddly.
struct RidingView: View {
    @Environment(RideRecorder.self) private var recorder
    @AppStorage(AppSettings.Key.units) private var unitsRaw = AppSettings.Units.system.rawValue
    @State private var confirmingEnd = false

    private var usesMetric: Bool { _ = unitsRaw; return AppSettings.usesMetric }

    var body: some View {
        @Bindable var recorder = recorder

        VStack(spacing: 0) {
            header
            GoogleMapView(
                lines: recorder.track.count > 1
                    ? [MapLine(id: "route", coordinates: recorder.track.map(\.coordinate), color: Brand.highwayYellow, width: 6)]
                    : [],
                camera: .follow(recorder.track.last?.coordinate, bearing: heading),
                showsUserLocation: true,
                padding: UIEdgeInsets(top: 48, left: 0, bottom: 0, right: 0)
            )
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) { statusBadges.padding(.top, 8) }

            controls
        }
        .background(Brand.asphalt)
        // The riding screen is the bike's instrument cluster: always dark, yellow on asphalt.
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) {
            if let banner = recorder.banner {
                Label(banner.text, systemImage: banner.systemImage)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thickMaterial, in: .capsule)
                    .padding(.top, 140)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: banner.id) {
                        try? await Task.sleep(for: .seconds(3))
                        recorder.banner = nil
                    }
            }
        }
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

    /// The map turns with the direction of travel; GPS reports a negative course when it doesn't know.
    private var heading: Double? {
        guard let course = recorder.track.last?.course, course >= 0 else { return nil }
        return course
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(recorder.active?.name ?? "Ride")
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.speed(recorder.isPaused ? 0 : recorder.stats.currentSpeedMps, usesMetric: usesMetric))
                    .font(Brand.readout(88))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(Format.speedUnit(usesMetric: usesMetric))
                    .font(Brand.label)
                    .foregroundStyle(Brand.highwayYellow)
            }
            HStack {
                stat(Format.distance(recorder.stats.distanceMeters, usesMetric: usesMetric), "Distance")
                if let start = recorder.active?.startedAt {
                    VStack(spacing: 2) {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                            .font(Brand.stat).monospacedDigit()
                        Text("TIME").font(Brand.label).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                // With a destination, "to go" matters more mid-ride than top speed.
                if recorder.active?.destination != nil {
                    stat(recorder.hasArrived ? "Here" : recorder.remainingMeters.map { Format.distance($0, usesMetric: usesMetric) } ?? "–",
                         "To go")
                } else {
                    stat(Format.speed(recorder.stats.maxSpeedMps, usesMetric: usesMetric), "Max")
                }
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Brand.stat).monospacedDigit()
            Text(label.uppercased()).font(Brand.label).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                recorder.markSpot()
            } label: {
                Label("Mark spot", systemImage: "mappin.and.ellipse")
                    .font(.title.bold().width(.expanded))
                    .foregroundStyle(Brand.asphalt)
                    .frame(maxWidth: .infinity, minHeight: 84)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.highwayYellow)

            HStack(spacing: 12) {
                Button {
                    recorder.togglePause()
                } label: {
                    Label(recorder.isManuallyPaused ? "Resume" : "Pause",
                          systemImage: recorder.isManuallyPaused ? "play.fill" : "pause.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)

                Button {
                    confirmingEnd = true
                } label: {
                    Label("End", systemImage: "flag.checkered")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .tint(Brand.signal)
                .disabled(recorder.phase == .finishing)
            }
        }
        .padding()
        .overlay {
            if recorder.phase == .finishing {
                ProgressView("Finishing album…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
    }
}
