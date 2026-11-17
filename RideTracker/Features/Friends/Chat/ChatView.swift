import RideKit
import SwiftUI

/// One group chat: messages, oldest at the top, and a composer at the bottom.
struct ChatView: View {
    let groupID: UUID
    @Environment(RideRecorder.self) private var recorder
    @State private var draft = ""
    @State private var loaded = false
    @State private var showingInfo = false
    @State private var reporting: ChatMessage?
    @State private var blocking: ChatGroup.Member?
    @State private var reported = false
    @FocusState private var composing: Bool

    private var chat: ChatService { recorder.chat }
    private var group: ChatGroup? { chat.group(groupID) }

    var body: some View {
        let messages = chat.messages(in: groupID)
        ScrollView {
            LazyVStack(spacing: 2) {
                if !messages.isEmpty && !chat.reachedStart.contains(groupID) {
                    Button("Earlier messages") { Task { await chat.loadEarlier(groupID) } }
                        .font(.subheadline)
                        .disabled(chat.isLoadingEarlier)
                        .padding(.vertical, 8)
                }
                if messages.isEmpty {
                    if loaded { emptyState } else { skeleton }
                }
                ForEach(ChatLayout.rows(messages)) { row in
                    switch row {
                    case .day(let day):
                        Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(Brand.label).foregroundStyle(.secondary)
                            .padding(.top, 16).padding(.bottom, 6)
                    case .message(let message, let startsRun):
                        bubble(message, startsRun: startsRun)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { composer }
        .background(Brand.page)
        .navigationTitle(group?.name ?? "Chat")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Group info", systemImage: "info.circle") { showingInfo = true }
            }
        }
        .sheet(isPresented: $showingInfo) { ChatInfoView(groupID: groupID) }
        .confirmationDialog("Report this message?", isPresented: isPresent($reporting), titleVisibility: .visible,
                            presenting: reporting) { message in
            ForEach(["Spam", "Abusive or harassing", "Something else"], id: \.self) { reason in
                Button(reason) {
                    Task { reported = await chat.report(message, reason: reason) }
                }
            }
        } message: { _ in
            Text("The Ride Tracker team will review it. The sender isn't told who reported it.")
        }
        .confirmationDialog("Block \(blocking?.name ?? "")?", isPresented: isPresent($blocking), titleVisibility: .visible,
                            presenting: blocking) { member in
            Button("Block", role: .destructive) { Task { await chat.block(member.id) } }
        } message: { _ in
            Text("You won't see their messages in any group, and they can't add you to new groups. They aren't told.")
        }
        .overlay(alignment: .top) {
            if reported {
                Label("Thanks — we'll take a look.", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.top, 8)
                    .task { try? await Task.sleep(for: .seconds(3)); reported = false }
            }
        }
        .task(id: groupID) {
            await chat.open(groupID)
            loaded = true
        }
        .onDisappear { Task { await chat.close(groupID) } }
        .refreshable { await chat.loadNewest(groupID) }
    }

    // MARK: Bubbles

    @ViewBuilder
    private func bubble(_ message: ChatMessage, startsRun: Bool) -> some View {
        let mine = message.senderID == chat.me
        let sender = group?.member(message.senderID)
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            if startsRun && !mine {
                Text(sender?.name ?? "Former member")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 12).padding(.top, 8)
            }
            HStack(alignment: .bottom, spacing: 6) {
                if mine { Spacer(minLength: 48) }
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(mine ? Brand.asphalt : Color.primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(mine ? Brand.highwayYellow : Brand.card, in: .rect(cornerRadius: 18))
                    .opacity(message.delivery == .sending ? 0.6 : 1)
                    .textSelection(.enabled)
                    .contextMenu { menu(for: message, sender: sender, mine: mine) }
                if !mine { Spacer(minLength: 48) }
            }
            .padding(.top, startsRun && mine ? 8 : 0)
            status(message, mine: mine)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? "You" : sender?.name ?? "Rider"): \(message.body)")
    }

    @ViewBuilder
    private func status(_ message: ChatMessage, mine: Bool) -> some View {
        switch message.delivery {
        case .sent:
            EmptyView()
        case .sending:
            Label("Sending", systemImage: "clock")
                .font(.caption2).foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        case .failed:
            Menu {
                Button("Try again", systemImage: "arrow.clockwise") { Task { await chat.retry(message) } }
                Button("Delete", systemImage: "trash", role: .destructive) { chat.discard(message) }
            } label: {
                Label("Not sent — tap to retry", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Brand.signal)
            }
        }
    }

    @ViewBuilder
    private func menu(for message: ChatMessage, sender: ChatGroup.Member?, mine: Bool) -> some View {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.body }
        if mine, !message.isPending {
            Button("Delete for everyone", systemImage: "trash", role: .destructive) {
                Task { await chat.delete(message) }
            }
        } else if !mine {
            Button("Report", systemImage: "exclamationmark.bubble") { reporting = message }
            if let sender {
                Button("Block \(sender.name)", systemImage: "hand.raised", role: .destructive) { blocking = sender }
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($composing)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Brand.card, in: .rect(cornerRadius: 20))
            Button {
                let text = draft
                draft = ""
                Task { await chat.send(text, to: groupID) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Brand.asphalt)
                    .frame(width: 40, height: 40)
                    .background(Brand.highwayYellow, in: .circle)
            }
            .disabled(ChatText.prepare(draft) == nil)
            .opacity(ChatText.prepare(draft) == nil ? 0.4 : 1)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: States

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Plan your next ride").font(.headline)
            Text("Say where and when — everyone in the group sees it.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 80)
    }

    private var skeleton: some View {
        VStack(spacing: 10) {
            ForEach([(false, 180.0), (false, 120.0), (true, 160.0), (false, 220.0), (true, 100.0)], id: \.1) { mine, width in
                HStack {
                    if mine { Spacer() }
                    SkeletonBlock(width: width, height: 36, cornerRadius: 18)
                    if !mine { Spacer() }
                }
            }
        }
        .padding(.top, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading messages")
    }

    private func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}
