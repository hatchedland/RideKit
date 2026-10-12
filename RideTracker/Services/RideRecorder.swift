import Foundation
import Observation
import RideKit
import SwiftData

/// Runs a ride from **Start** to **End**: GPS tracking, live stats, the Photos album, spots marked
/// on the way, nearby wishlist alerts, the Live Activity and crash recovery.
@MainActor
@Observable
final class RideRecorder {
    enum Phase: Equatable {
        case idle, starting, recording, finishing
    }

    /// A short confirmation shown on the riding screen (and announced via haptics).
    struct Banner: Equatable, Identifiable {
        let id = UUID()
        var text: String
        var systemImage: String
    }

    private(set) var phase: Phase = .idle
    private(set) var active: ActiveRide?
    private(set) var stats = LiveRideStats()
    private(set) var track: [TrackPoint] = []
    private(set) var isManuallyPaused = false
    private(set) var isAutoPaused = false
    private(set) var albumItemCount = 0
    private(set) var spotsMarkedThisRide = 0
    private(set) var locationDenied = false
    private(set) var gpsUnavailable = false
    var banner: Banner?

    /// Set after a ride ends; the UI shows its summary.
    var finishedRideID: UUID?
    /// Wishlist spots the last ride visited automatically (for "Undo" on the summary).
    private(set) var autoVisitedSpotIDs: [UUID] = []
    /// A ride interrupted by the app being killed; the UI offers Resume / Finish.
    var interruptedRide: ActiveRide?

    var isRiding: Bool { phase == .recording }
    var isPaused: Bool { isManuallyPaused || isAutoPaused }

    // Dependencies
    let context: ModelContext
    let photos: PhotoLibraryService
    let spots: SpotService
    let organizer: MediaOrganizer
    private let location = LocationService()
    private let liveActivity = LiveActivityController()
    private let buffer: TrackBuffer

    private var autoPause = AutoPauseDetector()
    private var alertedWishlist: Set<UUID> = []
    private var wishlist: [(reference: SpotReference, name: String)] = []
    private var lastNearbyCheck: Date = .distantPast
    private var sweepTask: Task<Void, Never>?
    private var recoveredPoints: [TrackPoint] = []

    init(context: ModelContext, photos: PhotoLibraryService = PhotoLibraryService()) {
        self.context = context
        self.photos = photos
        self.spots = SpotService(context: context)
        self.organizer = MediaOrganizer(context: context, photos: photos)
        let directory = URL.applicationSupportDirectory.appending(path: "ActiveRide", directoryHint: .isDirectory)
        self.buffer = TrackBuffer(directory: directory)

        if let recovered = buffer.recover() {
            interruptedRide = recovered.ride
            recoveredPoints = recovered.points
        }
        installIntentHandlers()
    }

    // MARK: - Start

    func start(name input: String) async throws {
        guard phase == .idle else { return }
        phase = .starting
        defer { if phase == .starting { phase = .idle } }

        if photos.authorizationStatus == .notDetermined {
            await photos.requestAccess()
        }

        let startedAt = Date.now
        let existingNames = ((try? context.fetch(FetchDescriptor<Ride>())) ?? []).map(\.name)
        let name = RideNaming.resolve(input, startedAt: startedAt, existingNames: existingNames)

        var ride = ActiveRide(name: name, startedAt: startedAt)
        let model = Ride(id: ride.id, name: name, startedAt: startedAt)
        model.includeScreenshots = AppSettings.includeScreenshots
        context.insert(model)

        if photos.hasFullAccess, let albumID = try? await photos.createAlbum(named: name) {
            ride.albumIdentifier = albumID
            model.albumLocalIdentifier = albumID
        }
        try? context.save()
        try buffer.begin(ride)

        resetLiveState()
        active = ride
        begin(rideName: name, startedAt: startedAt, resuming: false)
    }

    /// Shared by a fresh start and resuming an interrupted ride.
    private func begin(rideName: String, startedAt: Date, resuming: Bool) {
        autoPause = AutoPauseDetector(sensitivity: AppSettings.autoPauseSensitivity)
        loadWishlist()
        startLocation()
        photos.observeChanges { [weak self] in
            Task { @MainActor in self?.scheduleSweep() }
        }
        // A resumed ride keeps its Live Activity if iOS kept it; a fresh ride replaces any leftover.
        if !(resuming && liveActivity.adoptExisting()) {
            liveActivity.start(rideName: rideName, startedAt: startedAt, state: activityState())
        }
        phase = .recording
        scheduleSweep(after: .zero)
    }

    private func startLocation() {
        location.start { [weak self] event in
            self?.handle(event)
        }
    }

    // MARK: - During the ride

    private func handle(_ event: LocationService.Event) {
        switch event {
        case .denied:
            locationDenied = true
        case .unavailable:
            gpsUnavailable = true
        case .fix(let point):
            locationDenied = false
            gpsUnavailable = false
            guard phase == .recording, !isManuallyPaused else { return }
            track.append(point)
            try? buffer.append(point)
            stats.add(point)
            if autoPause.update(speed: stats.currentSpeedMps, at: point.timestamp) {
                isAutoPaused = autoPause.isPaused
            }
            liveActivity.update(activityState())
            checkNearbyWishlist(from: point)
        }
    }

    /// Saves the current location as a spot. Returns the name shown in the confirmation,
    /// or `nil` if there's no ride or no location yet.
    @discardableResult
    func markSpot() -> String? {
        guard phase == .recording, var ride = active,
              let coordinate = location.lastFix?.coordinate ?? track.last?.coordinate
        else { return nil }

        let message: String
        switch spots.mark(at: coordinate, status: .visited, rideID: ride.id) {
        case .created(let spot):
            ride.spotIDs.append(spot.id)
            message = "Spot saved"
        case .revisited(let spot):
            if spot.ride == nil, let model = rideModel(ride.id) { spot.ride = model }
            message = "Visit added: \(spot.displayName)"
        }
        active = ride
        try? buffer.updateMetadata(ride)
        spotsMarkedThisRide += 1
        banner = Banner(text: message, systemImage: "mappin.and.ellipse")

        var state = activityState()
        state.lastSpotName = "📍 \(message)"
        liveActivity.update(state, force: true)
        return message
    }

    func togglePause() {
        guard phase == .recording else { return }
        isManuallyPaused.toggle()
        if isManuallyPaused {
            location.suspendUpdates()
            stats.breakSegment()
        } else {
            startLocation()
        }
        liveActivity.update(activityState(), force: true)
    }

    private func checkNearbyWishlist(from point: TrackPoint) {
        guard AppSettings.nearbyAlerts, !wishlist.isEmpty,
              point.timestamp.timeIntervalSince(lastNearbyCheck) >= 15 else { return }
        lastNearbyCheck = point.timestamp

        let alerts = WishlistMatcher.nearbyAlerts(
            position: point.coordinate,
            wishlist: wishlist.map(\.reference),
            alreadyAlerted: alertedWishlist
        )
        guard let nearest = alerts.first,
              let name = wishlist.first(where: { $0.reference.id == nearest.spot.id })?.name else { return }
        alerts.forEach { alertedWishlist.insert($0.spot.id) }
        let distance = Format.distance(nearest.distance)
        banner = Banner(text: "\(name) is \(distance) away", systemImage: "star.fill")
        liveActivity.alert(title: "Wishlist spot nearby", body: "\(name) is \(distance) away", state: activityState())
    }

    private func loadWishlist() {
        let wanted = SpotStatus.wantToGo.rawValue
        let descriptor = FetchDescriptor<Spot>(predicate: #Predicate { $0.statusRaw == wanted })
        wishlist = ((try? context.fetch(descriptor)) ?? []).map { ($0.reference, $0.displayName) }
    }

    // MARK: - Photos album

    /// Debounced: a burst of photos triggers one sweep.
    private func scheduleSweep(after delay: Duration = .seconds(2)) {
        guard let ride = active, let albumID = ride.albumIdentifier else { return }
        sweepTask?.cancel()
        sweepTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            let window = RideMediaWindow(start: ride.startedAt, end: .now, includeScreenshots: AppSettings.includeScreenshots)
            _ = try? await self.photos.sweep(albumID: albumID, window: window)
            let count = self.photos.albumItemCount(albumID)
            if count != self.albumItemCount {
                self.albumItemCount = count
                self.liveActivity.update(self.activityState(), force: true)
            }
        }
    }

    // MARK: - End

    func stop() async {
        guard phase == .recording, let ride = active else { return }
        await finish(ride, points: track, endedAt: .now)
    }

    private func finish(_ ride: ActiveRide, points: [TrackPoint], endedAt: Date) async {
        phase = .finishing
        location.stop()
        photos.stopObserving()
        sweepTask?.cancel()

        let model = rideModel(ride.id) ?? {
            let created = Ride(id: ride.id, name: ride.name, startedAt: ride.startedAt)
            created.albumLocalIdentifier = ride.albumIdentifier
            context.insert(created)
            return created
        }()
        model.endedAt = max(endedAt, ride.startedAt)
        model.apply(RideStats.summarize(points))
        model.trackData = try? TrackCodec.encode(points)
        model.albumSweepUntil = model.endedAt.addingTimeInterval(RideMediaWindow.lateArrivalPeriod)
        for id in ride.spotIDs {
            if let spot = try? context.fetch(FetchDescriptor<Spot>(predicate: #Predicate { $0.id == id })).first {
                spot.ride = model
            }
        }

        // Final album pass over the whole ride window, then link everything in-app.
        let radius = AppSettings.spotRadius
        if let albumID = model.albumLocalIdentifier {
            _ = try? await photos.sweep(albumID: albumID, window: model.mediaWindow)
        }
        let items = photos.candidates(in: model.mediaWindow).filter { model.mediaWindow.contains($0) }
        organizer.link(items, to: model, radius: radius)
        autoVisitedSpotIDs = organizer.applyWishlistVisits(for: model, track: points, radius: radius).map(\.id)
        try? context.save()

        liveActivity.end(state: activityState())
        buffer.clear()
        resetLiveState()
        active = nil
        phase = .idle
        finishedRideID = model.id
    }

    // MARK: - Recovery

    /// Continues a ride the system interrupted, keeping its points and album.
    func resumeInterrupted() {
        guard phase == .idle, let ride = interruptedRide else { return }
        interruptedRide = nil
        resetLiveState()
        active = ride
        track = recoveredPoints
        recoveredPoints.forEach { stats.add($0) }
        stats.breakSegment()
        recoveredPoints = []
        begin(rideName: ride.name, startedAt: ride.startedAt, resuming: true)
    }

    /// Saves an interrupted ride as ended at its last recorded point.
    func finishInterrupted() async {
        guard phase == .idle, let ride = interruptedRide else { return }
        interruptedRide = nil
        let points = recoveredPoints
        recoveredPoints = []
        phase = .recording
        await finish(ride, points: points, endedAt: points.last?.timestamp ?? ride.startedAt)
    }

    // MARK: - After the ride

    /// Adds photos that reached the library late (iCloud, AirDrop) to recent rides' albums.
    func runLateSweeps() async {
        guard phase == .idle, photos.hasFullAccess else { return }
        let now = Date.now
        let descriptor = FetchDescriptor<Ride>(predicate: #Predicate { $0.albumSweepUntil != nil })
        let recent = ((try? context.fetch(descriptor)) ?? []).filter { ($0.albumSweepUntil ?? .distantPast) > now }
        for ride in recent {
            if let albumID = ride.albumLocalIdentifier {
                _ = try? await photos.sweep(albumID: albumID, window: ride.mediaWindow)
            }
            let items = photos.candidates(in: ride.mediaWindow).filter { ride.mediaWindow.contains($0) }
            organizer.link(items, to: ride, radius: AppSettings.spotRadius)
        }
    }

    /// Items taken up to 30 min before Start / after End ("forgot to tap Start?").
    func edgeCandidates(for ride: Ride) -> (before: [MediaCandidate], after: [MediaCandidate]) {
        let window = ride.mediaWindow
        let all = photos.candidates(
            from: window.start.addingTimeInterval(-RideMediaWindow.edgeOfferPeriod),
            to: window.end.addingTimeInterval(RideMediaWindow.edgeOfferPeriod)
        )
        let linked = Set((ride.media ?? []).map(\.localIdentifier))
        let edge = window.edgeCandidates(from: all)
        return (edge.before.filter { !linked.contains($0.id) }, edge.after.filter { !linked.contains($0.id) })
    }

    /// Adds edge items to the ride: into its album and its in-app gallery.
    func addToRide(_ items: [MediaCandidate], ride: Ride) async {
        if let albumID = ride.albumLocalIdentifier {
            try? await photos.addToAlbum(albumID, assetIDs: items.map(\.id))
        }
        organizer.link(items, to: ride, radius: AppSettings.spotRadius)
    }

    /// Renames the ride and its Photos album.
    func rename(_ ride: Ride, to input: String) async {
        let others = ((try? context.fetch(FetchDescriptor<Ride>())) ?? []).filter { $0.id != ride.id }.map(\.name)
        let name = RideNaming.resolve(input, startedAt: ride.startedAt, existingNames: others)
        guard name != ride.name else { return }
        ride.name = name
        try? context.save()
        if let albumID = ride.albumLocalIdentifier {
            try? await photos.renameAlbum(albumID, to: name)
        }
        if active?.id == ride.id {
            active?.name = name
            if let active { try? buffer.updateMetadata(active) }
        }
    }

    /// Deletes the ride. The Photos album is deleted only if asked; photos are never deleted.
    func delete(_ ride: Ride, deleteAlbum: Bool) async {
        if deleteAlbum, let albumID = ride.albumLocalIdentifier {
            try? await photos.deleteAlbum(albumID)
        }
        // Wishlist spots this ride auto-visited go back to the wishlist.
        let rideID: UUID? = ride.id
        let autoVisited = (try? context.fetch(FetchDescriptor<Spot>(predicate: #Predicate { $0.autoVisitedByRideID == rideID }))) ?? []
        autoVisited.forEach { undoAutoVisit($0, ride: ride) }
        context.delete(ride)
        try? context.save()
    }

    func undoAutoVisit(_ spot: Spot, ride: Ride) {
        if let date = spot.visits.first(where: { $0 >= ride.startedAt && $0 <= ride.endedAt }) {
            spot.undoAutoVisit(fromRide: ride.id, on: date)
        }
        autoVisitedSpotIDs.removeAll { $0 == spot.id }
        try? context.save()
    }

    // MARK: - Helpers

    private func rideModel(_ id: UUID) -> Ride? {
        try? context.fetch(FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })).first
    }

    private func resetLiveState() {
        stats = LiveRideStats()
        track = []
        isManuallyPaused = false
        isAutoPaused = false
        albumItemCount = 0
        spotsMarkedThisRide = 0
        alertedWishlist = []
        lastNearbyCheck = .distantPast
        banner = nil
    }

    private func activityState() -> RideActivityAttributes.ContentState {
        RideActivityAttributes.ContentState(
            speedMps: isPaused ? 0 : stats.currentSpeedMps,
            distanceMeters: stats.distanceMeters,
            isPaused: isPaused,
            albumItemCount: albumItemCount,
            lastSpotName: nil,
            usesMetric: AppSettings.usesMetric
        )
    }

    private func installIntentHandlers() {
        RideControl.markSpot = { [weak self] in self?.markSpot() }
        RideControl.togglePause = { [weak self] in self?.togglePause() }
        RideControl.startRide = { [weak self] name in try await self?.start(name: name) }
        RideControl.endRide = { [weak self] in await self?.stop() }
    }
}
