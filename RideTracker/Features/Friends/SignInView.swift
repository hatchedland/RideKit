import SwiftUI

/// The app's front door: every feature needs an account. Passwordless: an email link that opens the app.
struct SignInView: View {
    @Environment(AccountService.self) private var account
    @State private var email = ""
    @State private var sending = false
    @FocusState private var emailFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MilestoneMark()
                    .frame(width: 56)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ride Tracker").font(.largeTitle.bold().width(.expanded))
                    Text("Record your rides, save the spots you stop at, and ride with friends. Sign in with your email to start; no password.")
                        .foregroundStyle(.secondary)
                }

                switch account.state {
                case .linkSent(let sentTo, let at):
                    linkSent(to: sentTo, at: at)
                default:
                    emailForm
                }

                if let error = account.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Brand.signal)
                }

                Text("Your rides, spots and photo details are kept in your account so they're safe on a new phone. Friends only see what you share. Photos stay in your Photos library.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(Brand.page)
        .scrollDismissesKeyboard(.interactively)
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email, prompt: Text("Your email address"))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($emailFocused)
                .onSubmit(send)
                .font(.title3)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Brand.card, in: .rect(cornerRadius: 16))

            Button(action: send) {
                HStack {
                    if sending { ProgressView().tint(Brand.asphalt) }
                    Text("Email me a sign-in link")
                }
                .font(.headline)
                .foregroundStyle(Brand.asphalt)
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.highwayYellow)
            .disabled(sending || !account.isConfigured || !AccountService.looksLikeEmail(email.trimmingCharacters(in: .whitespaces)))
        }
    }

    private func linkSent(to address: String, at sentAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check your email").font(.headline)
                    Text("We sent a sign-in link to \(address). Open it on this iPhone and tap the link.")
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "envelope.badge").font(.title2).foregroundStyle(Brand.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.card, in: .rect(cornerRadius: 16))

            // Supabase allows one email a minute; the button says so instead of failing.
            TimelineView(.periodic(from: sentAt, by: 1)) { context in
                let wait = max(0, 60 - Int(context.date.timeIntervalSince(sentAt)))
                HStack {
                    Button(wait > 0 ? "Send again in \(wait)s" : "Send again") {
                        email = address
                        send()
                    }
                    .disabled(wait > 0 || sending)
                    Spacer()
                    Button("Use a different email") {
                        account.startOver()
                        emailFocused = true
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private func send() {
        guard !sending else { return }
        sending = true
        Task {
            await account.sendLink(to: email)
            sending = false
        }
    }
}
