import Foundation
import Observation
import RideKit
import Supabase

/// Group chat between friends: the Chats list, each group's messages (the newest kept on the
/// phone, plus messages written offline), live updates while a chat is open, and the safety tools
/// (report, block, leave). Nothing here ever reaches the riding screen.
@MainActor
@Observable
final class ChatService {
    private(set) var groups: [ChatGroup] = []
    private(set) var timelines: [UUID: ChatTimeline] = [:]
    private(set) var blocked: Set<UUID> = []
    private(set) var me: UUID?
    /// Whether the rider agreed to the chat rules; `nil` until known. Posting and making groups
    /// wait for it (the server refuses both without it).
    private(set) var rulesAccepted: Bool?
    /// Set after the first successful load, so the list can show skeletons until then.
    private(set) var hasLoaded = false
    private(set) var isLoadingEarlier = false
    private(set) var reachedStart: Set<UUID> = []
    var lastError: String?

    private var backend: ChatBackend?
    private var listening: (group: UUID, channel: RealtimeChannelV2, task: Task<Void, Never>)?

    private static let folder = URL.cachesDirectory.appending(path: "chat", directoryHint: .isDirectory)
    private static let keptPerGroup = 200

    var unreadTotal: Int { groups.reduce(0) { $0 + $1.unread } }

    func configure(account: AccountService) {
        backend = account.client.map(ChatBackend.init)
    }

    func group(_ id: UUID) -> ChatGroup? { groups.first { $0.id == id } }

    /// Messages to show: blocked riders' are hidden on the phone too, in case they were cached
    /// before the block.
    func messages(in group: UUID) -> [ChatMessage] {
        (timelines[group] ?? loadCached(group)).messages.filter { !blocked.contains($0.senderID) }
    }

    // MARK: Chats list

    func refresh() async {
        guard let backend else { return }
        do {
            me = try await backend.me()
            async let overview = backend.overview()
            async let blocks = backend.blocked()
            async let rules = backend.hasAcceptedRules()
            groups = try await overview
            blocked = try await blocks
            rulesAccepted = try await rules
            hasLoaded = true
            lastError = nil
            await flushOutbox()
        } catch where FriendsService.isCancellation(error) {
        } catch {
            hasLoaded = true
            lastError = FriendsService.message(for: error)
        }
    }

    func createGroup(name: String, riders: [UUID]) async -> UUID? {
        guard let backend else { return nil }
        do {
            let id = try await backend.createGroup(name: name, riders: riders)
            await refresh()
            return id
        } catch {
            lastError = Self.message(for: error)
            return nil
        }
    }

    func addMembers(_ riders: [UUID], to group: UUID) async {
        await perform { try await $0.addMembers(riders, to: group) }
    }

    func remove(_ rider: UUID, from group: UUID) async {
        await perform { try await $0.removeMember(rider, from: group) }
    }

    func leave(_ group: UUID) async {
        guard let me else { return }
        await perform { try await $0.removeMember(me, from: group) }
        timelines[group] = nil
        try? FileManager.default.removeItem(at: Self.file(for: group))
    }

    func rename(_ group: UUID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await perform { try await $0.rename(group, to: String(trimmed.prefix(40))) }
    }

    // MARK: One chat

    /// Loads the newest messages and listens for new ones until `close` (or another chat opens).
    func open(_ group: UUID) async {
        if timelines[group] == nil { timelines[group] = loadCached(group) }
        await listen(to: group)
        await loadNewest(group)
        await markRead(group)
    }

    func close(_ group: UUID) async {
        guard let listening, listening.group == group else { return }
        self.listening = nil
        listening.task.cancel()
        await backend?.remove(listening.channel)
    }

    func loadEarlier(_ group: UUID) async {
        guard let backend, !isLoadingEarlier, !reachedStart.contains(group),
              let before = timelines[group]?.oldestSentAt else { return }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            let rows = try await backend.earlierMessages(in: group, before: before)
            if rows.count < ChatBackend.pageSize { reachedStart.insert(group) }
            apply(rows, to: group)
        } catch {
            lastError = FriendsService.message(for: error)
        }
    }

    func send(_ text: String, to group: UUID) async {
        guard let body = ChatText.prepare(text), let me else { return }
        let message = ChatMessage(groupID: group, senderID: me, body: body, sentAt: .now, delivery: .sending)
        update(group) { $0.merge([message]) }
        await deliver(message)
    }

    func retry(_ message: ChatMessage) async {
        update(message.groupID) { $0.setDelivery(.sending, for: message.id) }
        await deliver(message)
    }

    /// Takes back a message that never went.
    func discard(_ message: ChatMessage) {
        update(message.groupID) { $0.remove([message.id]) }
    }

    func delete(_ message: ChatMessage) async {
        guard let backend else { return }
        do {
            try await backend.delete(message.id)
            update(message.groupID) { $0.remove([message.id]) }
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: Safety

    func acceptRules() async -> Bool {
        guard let backend else { return false }
        do {
            try await backend.acceptRules()
            rulesAccepted = true
            return true
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    func report(_ message: ChatMessage, reason: String) async -> Bool {
        guard let backend else { return false }
        do {
            try await backend.report(message.id, reason: reason)
            return true
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    func block(_ rider: UUID) async {
        await perform { try await $0.block(rider) }
    }

    func unblock(_ rider: UUID) async {
        await perform { try await $0.unblock(rider) }
    }

    // MARK: Private

    private func perform(_ work: (ChatBackend) async throws -> Void) async {
        guard let backend else { return }
        do {
            try await work(backend)
            await refresh()
        } catch {
            lastError = Self.message(for: error)
        }
    }

    private func listen(to group: UUID) async {
        guard let backend, listening?.group != group else { return }
        if let current = listening { await close(current.group) }
        let channel = backend.changes(in: group)
        let stream = channel.broadcastStream(event: "*")
        let task = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                await self.loadNewest(group)
                await self.markRead(group)
            }
        }
        listening = (group, channel, task)
        do {
            try await channel.subscribeWithError()
        } catch {
            // Live updates are a nicety: the chat still loads on open and on pull to refresh.
        }
    }

    /// Re-reads the newest page: it catches new messages and recent deletions in one call.
    func loadNewest(_ group: UUID) async {
        guard let backend else { return }
        do {
            let rows = try await backend.messages(in: group, after: nil)
            if rows.count < ChatBackend.pageSize, timelines[group]?.sent.count ?? 0 <= rows.count {
                reachedStart.insert(group)
            }
            apply(rows, to: group)
        } catch where FriendsService.isCancellation(error) {
        } catch {
            lastError = FriendsService.message(for: error)
        }
    }

    private func apply(_ rows: [MessageRow], to group: UUID) {
        let deleted = Set(rows.filter { $0.deletedAt != nil }.map(\.id))
        update(group) { timeline in
            timeline.merge(rows.filter { $0.deletedAt == nil }.map(\.message))
            timeline.remove(deleted)
        }
    }

    private func markRead(_ group: UUID) async {
        try? await backend?.markRead(group)
        if let index = groups.firstIndex(where: { $0.id == group }) { groups[index].unread = 0 }
    }

    private func deliver(_ message: ChatMessage) async {
        guard let backend else { return }
        do {
            try await backend.send(message)
            await loadNewest(message.groupID)
        } catch let error as URLError where error.code != .cancelled {
            // Offline: it stays "sending" and goes with the next refresh.
        } catch {
            update(message.groupID) { $0.setDelivery(.failed, for: message.id) }
        }
    }

    /// Sends messages written while offline.
    private func flushOutbox() async {
        for group in groups.map(\.id) {
            for message in messages(in: group) where message.delivery == .sending {
                await deliver(message)
            }
        }
    }

    private func update(_ group: UUID, _ change: (inout ChatTimeline) -> Void) {
        var timeline = timelines[group] ?? loadCached(group)
        change(&timeline)
        timelines[group] = timeline
        save(timeline.trimmed(to: Self.keptPerGroup), for: group)
    }

    private func loadCached(_ group: UUID) -> ChatTimeline {
        guard let data = try? Data(contentsOf: Self.file(for: group)),
              let timeline = try? JSONDecoder().decode(ChatTimeline.self, from: data) else { return ChatTimeline() }
        return timeline
    }

    private func save(_ timeline: ChatTimeline, for group: UUID) {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(timeline).write(to: Self.file(for: group), options: [.atomic, .completeFileProtection])
    }

    private static func file(for group: UUID) -> URL {
        folder.appending(path: "\(group.uuidString).json")
    }

    static func message(for error: Error) -> String {
        if let error = error as? PostgrestError, let text = error.message.split(separator: "\n").first,
           ["only", "at most", "can only"].contains(where: { text.lowercased().contains($0) }) {
            return String(text) // Our own messages from the database functions.
        }
        return FriendsService.message(for: error)
    }
}
