import Photos
import RideKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.openURL) private var openURL

    @AppStorage(AppSettings.Key.autoPause) private var autoPause = AutoPauseDetector.Sensitivity.normal.rawValue
    @AppStorage(AppSettings.Key.includeScreenshots) private var includeScreenshots = false
    @AppStorage(AppSettings.Key.nearbyAlerts) private var nearbyAlerts = true
    @AppStorage(AppSettings.Key.spotRadius) private var spotRadius = MediaPlacer.defaultSpotRadius
    @AppStorage(AppSettings.Key.trackSongs) private var trackSongs = true

    @State private var photoStatus: PHAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                Section("Riding") {
                    Picker("Auto-pause", selection: $autoPause) {
                        Text("Less sensitive").tag(AutoPauseDetector.Sensitivity.low.rawValue)
                        Text("Normal").tag(AutoPauseDetector.Sensitivity.normal.rawValue)
                        Text("More sensitive").tag(AutoPauseDetector.Sensitivity.high.rawValue)
                    }
                    Toggle("Alert near wishlist spots", isOn: $nearbyAlerts)
                }

                Section {
                    Toggle("Include screenshots & screen recordings", isOn: $includeScreenshots)
                    LabeledContent("Spot radius") {
                        Stepper("\(Int(spotRadius)) m", value: $spotRadius, in: 50...500, step: 25)
                    }
                    photoAccessRow
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Each ride gets an album in Photos › Albums › Ride Tracker with everything you shoot between Start and End. Photos within the spot radius are attached to that spot, and a wishlist spot counts as visited if you stop or take a photo within it.")
                }

                Section {
                    Toggle("Log songs from the Music app", isOn: $trackSongs)
                } header: {
                    Text("Music")
                } footer: {
                    Text("Keeps a soundtrack of each ride: songs you play in the Music app for at least 30 seconds. Other apps like Spotify can't be read by iOS apps.")
                }

                FriendsSettingsSection()

                Section("Privacy") {
                    Text("Your rides, spots and photo links stay on your devices and in your own iCloud. Ride Tracker has no servers and no account. Rides you share with friends go to them through iCloud sharing, with private places removed.")
                        .font(.footnote)
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                }
            }
            .navigationTitle("Settings")
            .task {
                photoStatus = recorder.photos.authorizationStatus
            }
        }
    }

    @ViewBuilder
    private var photoAccessRow: some View {
        switch photoStatus {
        case .authorized:
            Label("Full Photos access", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .limited:
            VStack(alignment: .leading, spacing: 4) {
                Label("Limited Photos access", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Ride albums need full access to see photos from any camera app.").font(.footnote)
                Button("Change in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        case .notDetermined:
            Button("Allow Photos access") {
                Task { photoStatus = await recorder.photos.requestAccess() }
            }
        default:
            Button("Photos access is off — open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }
}
