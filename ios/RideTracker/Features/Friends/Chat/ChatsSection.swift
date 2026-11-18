import RideKit
import SwiftUI

struct ChatRoute: Hashable { var groupID: UUID }

/// The Chats section at the top of the Friends list: groups for planning rides together.
struct ChatsSection: View {
    @Environment(RideRecorder.self) private var recorder
    @Binding var creating: Bool
    @State private var showingRules = false

    private var chat: ChatService { recorder.chat }

    var body: some View {
        Section {
            if !chat.hasLoaded {
                ForEach(0..<2, id: \.self) { _ in ChatRowSkeleton() }
            } else if chat.groups.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan your next ride").font(.headline)
                    Text("Start a group with your riding friends to agree on a time and a place to meet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(chat.groups) { group in
                    NavigationLink(value: ChatRoute(groupID: group.id)) {
                        ChatRow(group: group, me: chat.me)
                    }
                }
            }
        } header: {
            HStack {
                Text("Chats")
                Spacer()
                Button("New group", systemImage: "square.and.pencil") {
                    if chat.rulesAccepted == true { creating = true } else { showingRules = true }
                }
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .textCase(nil)
                    .disabled(recorder.friends.friends.isEmpty)
            }
        }
        .sheet(isPresented: $showingRules) {
            ChatRulesSheet { creating = true }
        }
    }
}

/// "Sunday crew · Aman: 6 am at Murthal? · 4:12 pm · ●2"
struct ChatRow: View {
    let group: ChatGroup
    let me: UUID?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.avatar)
                Text(initials).font(.subheadline.weight(.bold)).foregroundStyle(Brand.chalk)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.name).font(.headline).lineLimit(1)
                    Spacer()
                    if let at = group.lastMessageAt {
                        Text(Self.time(at)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if group.unread > 0 {
                        Text("\(group.unread)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Brand.asphalt)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Brand.highwayYellow, in: .capsule)
                            .accessibilityLabel("\(group.unread) unread")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        String(group.name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    private var preview: String {
        guard let body = group.lastMessage else { return "\(group.members.count) riders" }
        let text = ChatText.preview(body)
        guard let sender = group.lastSenderID else { return text }
        if sender == me { return "You: \(text)" }
        return "\(group.member(sender)?.name ?? "Rider"): \(text)"
    }

    static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated))
    }
}

private struct ChatRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonBlock(width: 44, height: 44, cornerRadius: 22)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 140, height: 16)
                SkeletonBlock(width: 200, height: 12)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading chats")
    }
}
