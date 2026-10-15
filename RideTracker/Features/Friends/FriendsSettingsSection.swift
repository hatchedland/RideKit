import CoreLocation
import RideKit
import SwiftUI

/// Settings › Friends: your name for friends, the sharing default, and privacy.
struct FriendsSettingsSection: View {
    @Environment(RideRecorder.self) private var recorder
    @AppStorage(AppSettings.Key.riderName) private var riderName = ""
    @AppStorage(AppSettings.Key.shareRidesByDefault) private var shareByDefault = false
    @AppStorage(AppSettings.Key.hideRideEnds) private var hideRideEnds = true

    var body: some View {
        if recorder.friends.availability == .available {
            Section {
                TextField("Your name for friends", text: $riderName, prompt: Text("e.g. Rajan"))
                    .textContentType(.givenName)
                Toggle("Share new rides with friends", isOn: $shareByDefault)
                Toggle("Hide the start and end", isOn: $hideRideEnds)
                NavigationLink {
                    PrivacyZonesView()
                } label: {
                    LabeledContent("Privacy zones", value: "\(AppSettings.privacyZones.count)")
                }
            } header: {
                Text("Friends")
            } footer: {
                Text("Only friends you invite see rides you share. “Hide the start and end” cuts the first and last 500 m of every shared ride; privacy zones hide everything around places like home and work, also when riding live.")
            }
        }
    }
}

/// Places friends never see: the route, stops and photos inside are left out of everything shared.
struct PrivacyZonesView: View {
    @State private var zones = AppSettings.privacyZones
    @State private var adding = false
    @State private var name = "Home"
    @State private var locating = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(zones) { zone in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(zone.name).font(.headline)
                        Text("\(Int(zone.radius)) m around \(zone.center.queryString)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    zones.remove(atOffsets: offsets)
                    AppSettings.privacyZones = zones
                }
                Button("Add current location", systemImage: "location") {
                    name = zones.isEmpty ? "Home" : zones.count == 1 ? "Work" : ""
                    adding = true
                }
                .disabled(locating)
                if locating { ProgressView("Finding you…") }
                if let error { Text(error).foregroundStyle(Brand.signal) }
            } footer: {
                Text("Add one while you're at home, and one at work. Anything within 500 m is never shared with friends, including your live position.")
            }
        }
        .navigationTitle("Privacy zones")
        .alert("Name this zone", isPresented: $adding) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Add") { Task { await addCurrentLocation() } }
        }
    }

    private func addCurrentLocation() async {
        locating = true
        error = nil
        defer { locating = false }
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied {
                    error = "Location is off for Ride Tracker. Turn it on in Settings."
                    return
                }
                guard let location = update.location, location.horizontalAccuracy <= 100 else { continue }
                let zone = PrivacyZone(name: name.isEmpty ? "Private place" : name,
                                       center: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
                zones.append(zone)
                AppSettings.privacyZones = zones
                return
            }
        } catch {
            self.error = "Couldn't find your location."
        }
    }
}
