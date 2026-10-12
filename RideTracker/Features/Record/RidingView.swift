import MapKit
import SwiftUI

/// The screen while riding: huge glanceable numbers, a big **Mark spot** button, nothing fiddly.
struct RidingView: View {
    @Environment(RideRecorder.self) private var recorder
    @AppStorage(AppSettings.Key.units) private var unitsRaw = AppSettings.Units.system.rawValue
    @State private var confirmingEnd = false
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    private var usesMetric: Bool { _ = unitsRaw; return AppSettings.usesMetric }

    var body: some View {
        @Bindable var recorder = recorder

        VStack(spacing: 0) {
            header
            Map(position: $position) {
                UserAnnotation()
                if recorder.track.count > 1 {
                    MapPolyline(coordinates: recorder.track.map(\.coordinate.clCoordinate))
                        .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) { statusBadges.padding(.top, 8) }

            controls
        }
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

    private var header: some View {
        VStack(spacing: 4) {
            Text(recorder.active?.name ?? "Ride")
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.speed(recorder.isPaused ? 0 : recorder.stats.currentSpeedMps, usesMetric: usesMetric))
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(Format.speedUnit(usesMetric: usesMetric))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack {
                stat(Format.distance(recorder.stats.distanceMeters, usesMetric: usesMetric), "Distance")
                if let start = recorder.active?.startedAt {
                    VStack(spacing: 2) {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                            .font(.title2.bold()).monospacedDigit()
                        Text("Time").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                stat(Format.speed(recorder.stats.maxSpeedMps, usesMetric: usesMetric), "Max")
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusBadges: some View {
        HStack(spacing: 8) {
            if recorder.isPaused {
                badge(recorder.isManuallyPaused ? "Paused" : "Auto-paused", "pause.fill", .orange)
            }
            badge("\(recorder.albumItemCount)", "photo.on.rectangle", .purple)
            if recorder.spotsMarkedThisRide > 0 {
                badge("\(recorder.spotsMarkedThisRide)", "mappin", .red)
            }
            if recorder.songsThisRide > 0 {
                badge("\(recorder.songsThisRide)", "music.note", .pink)
            }
            if recorder.locationDenied {
                badge("Location off", "location.slash", .red)
            } else if recorder.gpsUnavailable {
                badge("Weak GPS", "antenna.radiowaves.left.and.right.slash", .gray)
            }
        }
    }

    private func badge(_ text: String, _ image: String, _ color: Color) -> some View {
        Label(text, systemImage: image)
            .font(.subheadline.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.85), in: .capsule)
            .foregroundStyle(.white)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                recorder.markSpot()
            } label: {
                Label("Mark spot", systemImage: "mappin.and.ellipse")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, minHeight: 84)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

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
                .tint(.primary)
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
