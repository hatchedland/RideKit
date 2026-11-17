import Foundation
import RideKit
import Supabase

/// A group in the Chats list, with its members and newest message.
struct ChatGroup: Identifiable, Sendable, Hashable {
    struct Member: Identifiable, Sendable, Hashable, Decodable {
        var id: UUID
        var name: String
        var username: String
        var isAdmin: Bool
        enum CodingKeys: String, CodingKey { case id, name, username, isAdmin = "is_admin" }
    }

    var id: UUID
    var name: String
    var isAdmin: Bool
    var members: [Member]
    var lastMessage: String?
    var lastSenderID: UUID?
    var lastMessageAt: Date?
    var unread: Int

    func member(_ id: UUID) -> Member? { members.first { $0.id == id } }
}

/// Group chat on Supabase (`supabase/migrations/…_group_chat.sql`). Row-level security decides
/// what a rider can read and post; this only asks.
struct ChatBackend: Sendable {
    let client: SupabaseClient

    static let pageSize = 50

    func me() async throws -> UUID {
        try await client.auth.session.user.id
    }

    // MARK: Groups

    func overview() async throws -> [ChatGroup] {
        struct Row: Decodable {
            var group_id: UUID
            var name: String
            var is_admin: Bool
            var members: [ChatGroup.Member]
            var last_message_body: String?
            var last_message_sender: UUID?
            var last_message_at: Date?
            var unread: Int
        }
        let rows: [Row] = try await client.rpc("chat_overview").execute().value
        return rows.map {
            ChatGroup(id: $0.group_id, name: $0.name, isAdmin: $0.is_admin, members: $0.members,
                      lastMessage: $0.last_message_body, lastSenderID: $0.last_message_sender,
                      lastMessageAt: $0.last_message_at, unread: $0.unread)
        }
    }

    func createGroup(name: String, riders: [UUID]) async throws -> UUID {
        struct Params: Encodable { var group_name: String; var rider_ids: [UUID] }
        return try await client.rpc("create_chat_group", params: Params(group_name: name, rider_ids: riders)).execute().value
    }

    func addMembers(_ riders: [UUID], to group: UUID) async throws {
        struct Params: Encodable { var target_group: UUID; var rider_ids: [UUID] }
        try await client.rpc("add_chat_members", params: Params(target_group: group, rider_ids: riders)).execute()
    }

    /// Removes a rider; passing yourself leaves the group.
    func removeMember(_ rider: UUID, from group: UUID) async throws {
        struct Params: Encodable { var target_group: UUID; var rider: UUID }
        try await client.rpc("remove_chat_member", params: Params(target_group: group, rider: rider)).execute()
    }

    func rename(_ group: UUID, to name: String) async throws {
        try await client.from("chat_groups").update(["name": name]).eq("id", value: group).execute()
    }

    func markRead(_ group: UUID) async throws {
        let me = try await me()
        try await client.from("chat_members").update(["last_read_at": Date.now])
            .eq("group_id", value: group).eq("rider_id", value: me).execute()
    }

    // MARK: Messages

    /// Messages newer than `after` (oldest first), or the newest page when `after` is nil.
    /// Includes deletions, so phones can drop them.
    func messages(in group: UUID, after: Date?) async throws -> [MessageRow] {
        var query = client.from("chat_messages").select("id, group_id, sender_id, body, created_at, deleted_at")
            .eq("group_id", value: group)
        if let after { query = query.gt("created_at", value: after) }
        let rows: [MessageRow] = try await query.order("created_at", ascending: false)
            .limit(Self.pageSize).execute().value
        return rows.reversed()
    }

    /// The page before `before`, oldest first.
    func earlierMessages(in group: UUID, before: Date) async throws -> [MessageRow] {
        let rows: [MessageRow] = try await client.from("chat_messages")
            .select("id, group_id, sender_id, body, created_at, deleted_at")
            .eq("group_id", value: group).lt("created_at", value: before)
            .order("created_at", ascending: false).limit(Self.pageSize).execute().value
        return rows.reversed()
    }

    /// Posts a message with the phone's id; posting the same id again is a no-op.
    func send(_ message: ChatMessage) async throws {
        struct Insert: Encodable { var id: UUID; var group_id: UUID; var body: String }
        try await client.from("chat_messages")
            .upsert(Insert(id: message.id, group_id: message.groupID, body: message.body),
                    onConflict: "id", returning: .minimal, ignoreDuplicates: true)
            .execute()
    }

    func delete(_ message: UUID) async throws {
        try await client.from("chat_messages").update(["deleted_at": Date.now]).eq("id", value: message).execute()
    }

    // MARK: Safety

    func report(_ message: UUID, reason: String) async throws {
        struct Insert: Encodable { var message_id: UUID; var reason: String }
        try await client.from("chat_reports").insert(Insert(message_id: message, reason: String(reason.prefix(500))),
                                                     returning: .minimal).execute()
    }

    func blocked() async throws -> Set<UUID> {
        struct Row: Decodable { var blocked_id: UUID }
        let rows: [Row] = try await client.from("rider_blocks").select("blocked_id").execute().value
        return Set(rows.map(\.blocked_id))
    }

    func block(_ rider: UUID) async throws {
        try await client.from("rider_blocks").upsert(["blocked_id": rider], onConflict: "blocker_id,blocked_id",
                                                     returning: .minimal, ignoreDuplicates: true).execute()
    }

    func unblock(_ rider: UUID) async throws {
        try await client.from("rider_blocks").delete().eq("blocked_id", value: rider).execute()
    }

    // MARK: Realtime

    /// A private channel that fires whenever a message in `group` is posted, changed or deleted.
    /// The payload is ignored: the app reads new rows through row-level security instead.
    func changes(in group: UUID) -> RealtimeChannelV2 {
        client.channel("group:\(group.uuidString.lowercased())") { $0.isPrivate = true }
    }

    func remove(_ channel: RealtimeChannelV2) async {
        await client.removeChannel(channel)
    }
}

struct MessageRow: Decodable, Sendable {
    var id: UUID
    var groupID: UUID
    var senderID: UUID
    var body: String
    var createdAt: Date
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, body
        case groupID = "group_id", senderID = "sender_id", createdAt = "created_at", deletedAt = "deleted_at"
    }

    var message: ChatMessage {
        ChatMessage(id: id, groupID: groupID, senderID: senderID, body: body, sentAt: createdAt)
    }
}
