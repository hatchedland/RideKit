import SwiftUI

/// The chat rules, agreed to once before the first message or group (App Store guideline 1.2).
struct ChatRulesSheet: View {
    var onAccepted: () -> Void
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Chats are for riders who know each other. To keep them that way:")
                        .font(.body)
                    VStack(alignment: .leading, spacing: 12) {
                        rule("No abuse, threats, hate or harassment.", systemImage: "hand.raised")
                        rule("No sexual content, spam or scams.", systemImage: "nosign")
                        rule("Don't share someone's location or photos without asking.", systemImage: "location.slash")
                    }
                    Text("Messages that break these rules can be reported. We look at every report within 24 hours, remove what breaks the rules, and can remove the rider from Ride Tracker. You can block anyone at any time — they aren't told.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let error = recorder.chat.lastError {
                        Text(error).font(.footnote).foregroundStyle(Brand.signal)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    saving = true
                    Task {
                        if await recorder.chat.acceptRules() {
                            dismiss()
                            onAccepted()
                        }
                        saving = false
                    }
                } label: {
                    Text(saving ? "Saving…" : "I agree")
                        .font(.headline)
                        .foregroundStyle(Brand.asphalt)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.highwayYellow)
                .disabled(saving)
                .padding()
                .background(.bar)
            }
            .navigationTitle("Chat rules")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
            .onAppear { recorder.chat.lastError = nil }
        }
        .presentationDetents([.medium, .large])
    }

    private func rule(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text).font(.body.weight(.semibold))
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Brand.accent)
        }
    }
}
