import SwiftUI

/// Pick friends for a group. Only friends can be added; that's the whole safety model.
struct FriendPicker: View {
    let friends: [FriendSnapshot]
    @Binding var selected: Set<UUID>

    var body: some View {
        ForEach(friends) { friend in
            if let id = UUID(uuidString: friend.id) {
                Button {
                    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                } label: {
                    HStack {
                        Label(friend.name, systemImage: "person.crop.circle")
                        Spacer()
                        Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(id) ? Brand.accent : .secondary)
                            .font(.title3)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected.contains(id) ? .isSelected : [])
            }
        }
    }
}

/// New group: a name and the friends in it.
struct NewChatView: View {
    var onCreated: (UUID) -> Void
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<UUID> = []
    @State private var creating = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $name, prompt: Text("e.g. Sunday crew"))
                        .onChange(of: name) { _, new in if new.count > 40 { name = String(new.prefix(40)) } }
                }
                Section {
                    FriendPicker(friends: recorder.friends.friends, selected: $selected)
                } header: {
                    Text("Friends")
                } footer: {
                    Text("Everyone in the group sees each other's name and @handle — not each other's rides, unless they're friends too.")
                }
                if let error = recorder.chat.lastError {
                    Section { Text(error).foregroundStyle(Brand.signal) }
                }
            }
            .navigationTitle("New group")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if creating {
                        ProgressView()
                    } else {
                        Button("Create") {
                            creating = true
                            Task {
                                if let id = await recorder.chat.createGroup(name: trimmed, riders: Array(selected)) {
                                    dismiss()
                                    onCreated(id)
                                }
                                creating = false
                            }
                        }
                        .disabled(trimmed.isEmpty || selected.isEmpty)
                    }
                }
            }
            .onAppear { recorder.chat.lastError = nil }
        }
    }
}

/// Group info: name, members, adding friends, removing riders (admins), blocking, leaving.
struct ChatInfoView: View {
    let groupID: UUID
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var adding: Set<UUID> = []
    @State private var showingAdd = false
    @State private var confirmingLeave = false

    private var chat: ChatService { recorder.chat }
    private var group: ChatGroup? { chat.group(groupID) }

    var body: some View {
        NavigationStack {
            Form {
                if let group {
                    Section("Name") {
                        if group.isAdmin {
                            TextField("Group name", text: $name)
                                .onSubmit { Task { await chat.rename(groupID, to: name) } }
                                .submitLabel(.done)
                        } else {
                            Text(group.name)
                        }
                    }

                    Section {
                        ForEach(group.members) { member in
                            memberRow(member, in: group)
                        }
                        if group.isAdmin && !addableFriends(group).isEmpty && group.members.count < 20 {
                            Button("Add friends", systemImage: "person.badge.plus") { showingAdd = true }
                        }
                    } header: {
                        Text("\(group.members.count) riders")
                    }

                    if let error = chat.lastError {
                        Section { Text(error).foregroundStyle(Brand.signal) }
                    }

                    Section {
                        Button("Leave group", role: .destructive) { confirmingLeave = true }
                    }
                } else {
                    ContentUnavailableView("You're no longer in this group", systemImage: "person.2.slash")
                }
            }
            .navigationTitle("Group info")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { name = group?.name ?? "" }
            .confirmationDialog("Leave \(group?.name ?? "this group")?", isPresented: $confirmingLeave,
                                titleVisibility: .visible) {
                Button("Leave group", role: .destructive) {
                    Task {
                        await chat.leave(groupID)
                        dismiss()
                    }
                }
            } message: {
                Text("You'll stop getting its messages. Someone in the group can add you again.")
            }
            .sheet(isPresented: $showingAdd) { addSheet }
        }
    }

    @ViewBuilder
    private func memberRow(_ member: ChatGroup.Member, in group: ChatGroup) -> some View {
        let isMe = member.id == chat.me
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "You" : member.name).font(.headline)
                if !member.username.isEmpty {
                    Text("@\(member.username)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if member.isAdmin { Text("Admin").font(.caption).foregroundStyle(.secondary) }
            if chat.blocked.contains(member.id) {
                Button("Unblock") { Task { await chat.unblock(member.id) } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .swipeActions {
            if group.isAdmin && !isMe {
                Button("Remove", role: .destructive) { Task { await chat.remove(member.id, from: groupID) } }
            }
            if !isMe && !chat.blocked.contains(member.id) {
                Button("Block") { Task { await chat.block(member.id) } }.tint(.gray)
            }
        }
    }

    private func addableFriends(_ group: ChatGroup) -> [FriendSnapshot] {
        let inGroup = Set(group.members.map(\.id))
        return recorder.friends.friends.filter { UUID(uuidString: $0.id).map { !inGroup.contains($0) } ?? false }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                if let group {
                    FriendPicker(friends: addableFriends(group), selected: $adding)
                }
            }
            .navigationTitle("Add friends")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAdd = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let riders = Array(adding)
                        adding = []
                        showingAdd = false
                        Task { await chat.addMembers(riders, to: groupID) }
                    }
                    .disabled(adding.isEmpty)
                }
            }
        }
    }
}
