import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.Key.hasSeenSafetyNotice) private var hasSeenSafetyNotice = false

    enum TabID: Hashable { case ride, spots, rides, settings }
    @State private var selection: TabID = .ride

    var body: some View {
        @Bindable var recorder = recorder

        TabView(selection: $selection) {
            Tab("Ride", systemImage: "road.lanes", value: .ride) {
                RecordView()
            }
            Tab("Spots", systemImage: "mappin.and.ellipse", value: .spots) {
                SpotsView()
            }
            Tab("Rides", systemImage: "list.bullet.rectangle", value: .rides) {
                RidesListView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .sheet(item: finishedRide) { ride in
            NavigationStack {
                RideSummaryView(ride: ride)
            }
        }
        .sheet(isPresented: .constant(!hasSeenSafetyNotice)) {
            SafetyNoticeView { hasSeenSafetyNotice = true }
                .interactiveDismissDisabled()
        }
        .alert(
            "Your last ride was interrupted",
            isPresented: Binding(get: { recorder.interruptedRide != nil }, set: { _ in }),
            presenting: recorder.interruptedRide
        ) { _ in
            Button("Resume ride") { recorder.resumeInterrupted() }
            Button("Finish and save") { Task { await recorder.finishInterrupted() } }
        } message: { ride in
            Text("“\(ride.name)” stopped recording unexpectedly. Everything up to that point is safe.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await recorder.runLateSweeps() } }
        }
        .onChange(of: recorder.isRiding) { _, riding in
            if riding { selection = .ride }
        }
    }

    /// Looks up the just-finished ride for the summary sheet.
    private var finishedRide: Binding<Ride?> {
        Binding(
            get: {
                guard let id = recorder.finishedRideID else { return nil }
                return try? recorder.context.fetch(FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })).first
            },
            set: { if $0 == nil { recorder.finishedRideID = nil } }
        )
    }
}

/// Shown once at first launch.
struct SafetyNoticeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Eyes on the road")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                Label("Mount your phone before you start. Don't handle it while moving.", systemImage: "iphone.gen3")
                Label("Mark spots from the Lock Screen, the Action button or Siri — one tap, no looking.", systemImage: "hand.tap")
                Label("Name spots and sort photos after you've stopped.", systemImage: "pause.circle")
            }
            .font(.body)
            Spacer()
            Button(action: onContinue) {
                Text("I'll ride safe").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
    }
}
