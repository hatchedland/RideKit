import CryptoKit
import Foundation
import Observation
import OSLog
import RideKit
import Supabase
import SwiftData

/// Keeps the rider's Supabase data in step with the phone. The phone (SwiftData) is the working copy,
/// so rides record with no signal; this pushes what changed and pulls what other devices added.
///
/// - **Changes** are found by fingerprint: every row's content is hashed and compared with the hash
///   from the last successful sync, so any edit from anywhere in the app is caught.
/// - **Deletes**: a row that was synced but is no longer on the phone gets `deleted_at` on the server
///   (and its photo links and songs with it), so other devices drop it too.
/// - **Tracks** go to Storage as one file per ride: `tracks/<user>/<ride>.track`.
/// - **Pull**: rows changed on the server since the last pull are added or updated on the phone,
///   unless the phone has its own unsynced change to that row (then the phone wins).
/// - Order matters for the server's foreign keys: rides, spots, media links, songs.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var status: Status = .idle

    private let context: ModelContext
    private let account: AccountService
    private static let log = Logger(subsystem: "com.hatchedland.ridetracker", category: "sync")
    private static let stateURL = URL.applicationSupportDirectory.appending(path: "sync-state.json")

    /// What was last synced, per rider: row hashes and the newest server `updated_at` seen per table.
    private struct State: Codable {
        var userID: UUID?
        var hashes: [String: [UUID: String]] = [:]
        var trackHashes: [UUID: String] = [:]
        var pulledUntil: [String: Date] = [:]
    }
    private var state: State

    init(context: ModelContext, account: AccountService) {
        self.context = context
        self.account = account
        state = (try? JSONDecoder().decode(State.self, from: Data(contentsOf: Self.stateURL))) ?? State()
    }

    /// One full pass. Safe to call often: it does nothing when nothing changed.
    func sync() async {
        guard status != .syncing, let client = account.client,
              let user = try? await client.auth.session.user else { return }
        if state.userID != user.id {
            // Another rider on this phone (or the first sign-in): start the bookkeeping fresh.
            state = State(userID: user.id)
        }
        status = .syncing
        do {
            try await push(client: client, userID: user.id)
            try await pull(client: client, userID: user.id)
            saveState()
            status = .synced(.now)
        } catch {
            Self.log.error("Sync failed: \(error.localizedDescription, privacy: .public)")
            status = .failed((error as? URLError) != nil ? "Waiting for a connection" : "Couldn't sync")
        }
    }

    // MARK: Push

    private func push(client: SupabaseClient, userID: UUID) async throws {
        let rides = fetch(Ride.self), spots = fetch(Spot.self), media = fetch(MediaLink.self), songs = fetch(PlayedSong.self)

        // Track files first, so a ride row never points at a file that isn't there.
        for ride in rides {
            guard let data = ride.trackData else { continue }
            let hash = Self.hash(data)
            guard state.trackHashes[ride.id] != hash else { continue }
            try await client.storage.from("tracks").upload(
                Self.trackPath(userID: userID, rideID: ride.id), data: data,
                options: FileOptions(contentType: "application/octet-stream", upsert: true))
            state.trackHashes[ride.id] = hash
        }

        try await upsert("rides", rides.map { RideSyncRow($0, userID: userID) }, client: client)
        try await upsert("spots", spots.map(SpotSyncRow.init), client: client)
        try await upsert("media_links", media.map(MediaSyncRow.init), client: client)
        try await upsert("played_songs", songs.map(SongSyncRow.init), client: client)

        // Children before parents, so nothing points at a row that's being removed.
        try await markDeleted("played_songs", present: Set(songs.map(\.id)), client: client)
        try await markDeleted("media_links", present: Set(media.map(\.id)), client: client)
        try await markDeleted("spots", present: Set(spots.map(\.id)), client: client)
        try await markDeleted("rides", present: Set(rides.map(\.id)), client: client, children: ["media_links", "played_songs"])
    }

    /// Sends rows whose content changed since the last sync, in batches.
    private func upsert<Row: SyncRow>(_ table: String, _ rows: [Row], client: SupabaseClient) async throws {
        let changed = rows.filter { state.hashes[table]?[$0.id] != $0.fingerprint }
        for batch in stride(from: 0, to: changed.count, by: 200).map({ Array(changed[$0..<min($0 + 200, changed.count)]) }) {
            try await client.from(table).upsert(batch, onConflict: "id", returning: .minimal).execute()
            for row in batch { state.hashes[table, default: [:]][row.id] = row.fingerprint }
        }
    }

    private func markDeleted(_ table: String, present: Set<UUID>, client: SupabaseClient, children: [String] = []) async throws {
        let gone = (state.hashes[table] ?? [:]).keys.filter { !present.contains($0) }
        guard !gone.isEmpty else { return }
        let ids: [any PostgrestFilterValue] = gone.map(\.uuidString)
        let now = Date.now
        try await client.from(table).update(["deleted_at": now]).in("id", values: ids).execute()
        for child in children {
            try await client.from(child).update(["deleted_at": now]).in("ride_id", values: ids).is("deleted_at", value: nil).execute()
        }
        for id in gone {
            state.hashes[table]?[id] = nil
            if table == "rides" { state.trackHashes[id] = nil }
        }
    }

    // MARK: Pull

    private func pull(client: SupabaseClient, userID: UUID) async throws {
        try await pullTable("rides", client: client) { (rows: [RideSyncRow]) in
            for row in rows { try await self.apply(row, client: client, userID: userID) }
        }
        try await pullTable("spots", client: client) { (rows: [SpotSyncRow]) in rows.forEach(self.apply) }
        try await pullTable("media_links", client: client) { (rows: [MediaSyncRow]) in rows.forEach(self.apply) }
        try await pullTable("played_songs", client: client) { (rows: [SongSyncRow]) in rows.forEach(self.apply) }
        try context.save()
    }

    /// Rows changed on the server since the last pull (deleted ones included, to remove them here).
    private func pullTable<Row: SyncRow>(_ table: String, client: SupabaseClient,
                                         apply: ([Row]) async throws -> Void) async throws {
        var query = client.from(table).select()
        if let since = state.pulledUntil[table] {
            query = query.gt("updated_at", value: since.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        let rows: [Row] = try await query.order("updated_at").limit(1_000).execute().value
        guard !rows.isEmpty else { return }
        try await apply(rows)
        if let newest = rows.compactMap(\.updatedAt).max() { state.pulledUntil[table] = newest }
    }

    /// Whether the phone has its own unsynced change to this row (then the phone's version wins).
    private func isDirty<Row: SyncRow>(_ table: String, local: Row?) -> Bool {
        guard let local else { return false }
        return state.hashes[table]?[local.id] != local.fingerprint
    }

    private func apply(_ row: RideSyncRow, client: SupabaseClient, userID: UUID) async throws {
        let existing = fetch(Ride.self, id: row.id)
        if row.deletedAt != nil {
            if let existing { context.delete(existing) }
            state.hashes["rides"]?[row.id] = nil
            return
        }
        if isDirty("rides", local: existing.map { RideSyncRow($0, userID: userID) }) { return }
        let ride = existing ?? {
            let new = Ride(id: row.id, name: row.name, startedAt: row.startedAt)
            context.insert(new)
            return new
        }()
        row.write(to: ride)
        if ride.trackData == nil, row.trackPath != nil {
            let data = try await client.storage.from("tracks").download(path: Self.trackPath(userID: userID, rideID: row.id))
            ride.trackData = data
            state.trackHashes[row.id] = Self.hash(data)
        }
        state.hashes["rides", default: [:]][row.id] = RideSyncRow(ride, userID: userID).fingerprint
    }

    private func apply(_ row: SpotSyncRow) {
        let existing = fetch(Spot.self, id: row.id)
        if row.deletedAt != nil {
            if let existing { context.delete(existing) }
            state.hashes["spots"]?[row.id] = nil
            return
        }
        if isDirty("spots", local: existing.map(SpotSyncRow.init)) { return }
        let spot = existing ?? {
            let new = Spot(coordinate: Coordinate(latitude: row.latitude, longitude: row.longitude), status: .visited)
            new.id = row.id
            context.insert(new)
            return new
        }()
        row.write(to: spot, rides: { self.fetch(Ride.self, id: $0) })
        state.hashes["spots", default: [:]][row.id] = SpotSyncRow(spot).fingerprint
    }

    private func apply(_ row: MediaSyncRow) {
        let existing = fetch(MediaLink.self, id: row.id)
        if row.deletedAt != nil {
            if let existing { context.delete(existing) }
            state.hashes["media_links"]?[row.id] = nil
            return
        }
        if isDirty("media_links", local: existing.map(MediaSyncRow.init)) { return }
        let link = existing ?? {
            let new = MediaLink(candidate: MediaCandidate(id: row.localIdentifier, capturedAt: row.capturedAt, coordinate: nil),
                                cloudIdentifier: row.cloudIdentifier)
            new.id = row.id
            context.insert(new)
            return new
        }()
        row.write(to: link, rides: { self.fetch(Ride.self, id: $0) }, spots: { self.fetch(Spot.self, id: $0) })
        state.hashes["media_links", default: [:]][row.id] = MediaSyncRow(link).fingerprint
    }

    private func apply(_ row: SongSyncRow) {
        let existing = fetch(PlayedSong.self, id: row.id)
        if row.deletedAt != nil {
            if let existing { context.delete(existing) }
            state.hashes["played_songs"]?[row.id] = nil
            return
        }
        if isDirty("played_songs", local: existing.map(SongSyncRow.init)) { return }
        let song = existing ?? {
            let new = PlayedSong(play: SongPlay(song: NowPlayingSong(id: row.storeID, title: row.title, artist: row.artist),
                                                startedAt: row.startedAt, listenedSeconds: row.listenedSeconds), at: nil)
            new.id = row.id
            context.insert(new)
            return new
        }()
        row.write(to: song, rides: { self.fetch(Ride.self, id: $0) })
        state.hashes["played_songs", default: [:]][row.id] = SongSyncRow(song).fingerprint
    }

    // MARK: Helpers

    nonisolated static func trackPath(userID: UUID, rideID: UUID) -> String {
        // Storage policies compare the first folder with auth.uid()::text, which is lowercase.
        "\(userID.uuidString.lowercased())/\(rideID.uuidString.lowercased()).track"
    }

    nonisolated static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fetch<Model: PersistentModel>(_ type: Model.Type) -> [Model] {
        (try? context.fetch(FetchDescriptor<Model>())) ?? []
    }

    private func fetch(_ type: Ride.Type, id: UUID) -> Ride? {
        try? context.fetch(FetchDescriptor<Ride>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetch(_ type: Spot.Type, id: UUID) -> Spot? {
        try? context.fetch(FetchDescriptor<Spot>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetch(_ type: MediaLink.Type, id: UUID) -> MediaLink? {
        try? context.fetch(FetchDescriptor<MediaLink>(predicate: #Predicate { $0.id == id })).first
    }
    private func fetch(_ type: PlayedSong.Type, id: UUID) -> PlayedSong? {
        try? context.fetch(FetchDescriptor<PlayedSong>(predicate: #Predicate { $0.id == id })).first
    }

    private func saveState() {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: Self.stateURL, options: .atomic)
    }
}
