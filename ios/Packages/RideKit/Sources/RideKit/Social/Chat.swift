import Foundation

/// One message in a friends' group chat.
public struct ChatMessage: Identifiable, Sendable, Hashable, Codable {
    public enum Delivery: String, Sendable, Codable {
        /// On the server; `sentAt` is the server's clock.
        case sent
        /// Waiting to go (offline, or on its way); `sentAt` is when it was written.
        case sending
        /// The server refused it or the send gave up; the rider can retry.
        case failed
    }

    /// Made on the phone, so a retried send can't post twice.
    public var id: UUID
    public var groupID: UUID
    public var senderID: UUID
    public var body: String
    public var sentAt: Date
    public var delivery: Delivery

    public init(id: UUID = UUID(), groupID: UUID, senderID: UUID, body: String, sentAt: Date,
                delivery: Delivery = .sent) {
        self.id = id
        self.groupID = groupID
        self.senderID = senderID
        self.body = body
        self.sentAt = sentAt
        self.delivery = delivery
    }

    public var isPending: Bool { delivery != .sent }
}

/// What the rider typed, made ready to send.
public enum ChatText {
    public static let maxLength = 2000

    /// Trimmed text, or `nil` when there's nothing to send. Longer text is cut at `maxLength`.
    public static func prepare(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    /// A one-line preview for the Chats list.
    public static func preview(_ body: String, limit: Int = 80) -> String {
        let line = body.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }
}

/// A group's messages as the phone knows them: what the server sent, plus the rider's own messages
/// that haven't gone yet. Sent messages are in server order; unsent ones stay at the bottom, where
/// the rider can see and retry them.
public struct ChatTimeline: Sendable, Equatable, Codable {
    public private(set) var messages: [ChatMessage]

    public init(messages: [ChatMessage] = []) {
        self.messages = []
        merge(messages)
    }

    public var sent: [ChatMessage] { messages.filter { !$0.isPending } }
    public var pending: [ChatMessage] { messages.filter(\.isPending) }

    /// The newest server time seen: the cursor for "anything newer?".
    public var newestSentAt: Date? { sent.last?.sentAt }
    /// The oldest server time seen: the cursor for loading earlier messages.
    public var oldestSentAt: Date? { sent.first?.sentAt }

    /// Adds or replaces messages by id. A server copy always replaces a pending one with the same id.
    public mutating func merge(_ incoming: [ChatMessage]) {
        var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for message in incoming {
            if let existing = byID[message.id], !existing.isPending, message.isPending {
                continue // Never let a stale local copy undo a delivered one.
            }
            byID[message.id] = message
        }
        messages = Self.ordered(Array(byID.values))
    }

    /// Drops messages, e.g. ones their sender deleted.
    public mutating func remove(_ ids: Set<UUID>) {
        messages.removeAll { ids.contains($0.id) }
    }

    public mutating func setDelivery(_ delivery: ChatMessage.Delivery, for id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].delivery = delivery
        messages = Self.ordered(messages)
    }

    /// What's worth keeping on the phone: the newest `limit` sent messages and every unsent one.
    public func trimmed(to limit: Int) -> ChatTimeline {
        var copy = self
        let sent = self.sent
        if sent.count > limit {
            let dropped = Set(sent.prefix(sent.count - limit).map(\.id))
            copy.messages.removeAll { dropped.contains($0.id) }
        }
        return copy
    }

    static func ordered(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.sorted { a, b in
            if a.isPending != b.isPending { return !a.isPending }
            if a.sentAt != b.sentAt { return a.sentAt < b.sentAt }
            return a.id.uuidString < b.id.uuidString
        }
    }
}

/// Rows for the chat screen: a date header when the day changes, and the sender's name only on
/// the first of their messages in a run.
public enum ChatLayout {
    public enum Row: Sendable, Hashable, Identifiable {
        case day(Date)
        case message(ChatMessage, startsRun: Bool)

        public var id: String {
            switch self {
            case .day(let date): "day-\(date.timeIntervalSinceReferenceDate)"
            case .message(let message, _): message.id.uuidString
            }
        }
    }

    /// A pause longer than this starts a new run even from the same sender.
    public static let runGap: TimeInterval = 5 * 60

    public static func rows(_ messages: [ChatMessage], calendar: Calendar = .current) -> [Row] {
        var rows: [Row] = []
        var previous: ChatMessage?
        for message in messages {
            let day = calendar.startOfDay(for: message.sentAt)
            let newDay = previous.map { calendar.startOfDay(for: $0.sentAt) != day } ?? true
            if newDay { rows.append(.day(day)) }
            let startsRun = newDay
                || previous?.senderID != message.senderID
                || message.sentAt.timeIntervalSince(previous?.sentAt ?? message.sentAt) > runGap
            rows.append(.message(message, startsRun: startsRun))
            previous = message
        }
        return rows
    }
}
