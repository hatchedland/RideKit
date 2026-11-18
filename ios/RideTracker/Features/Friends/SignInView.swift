import AuthenticationServices
import SwiftUI

/// The app's front door: every feature needs an account. Sign in with Apple or Google; no email or
/// password (decided 2026-11-18). Free Personal builds can't use Sign in with Apple, so they show Google only.
struct SignInView: View {
    @Environment(AccountService.self) private var account
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MilestoneMark()
                    .frame(width: 56)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ride Tracker").font(.largeTitle.bold().width(.expanded))
                    Text("Record your rides, save the spots you stop at, and ride with friends.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    #if !PERSONAL_TEAM
                    SignInWithAppleButton(.continue) { request in
                        account.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task { await account.completeApple(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: Self.buttonHeight)
                    .clipShape(.rect(cornerRadius: 16))
                    #endif

                    Button {
                        Task { await account.signInWithGoogle() }
                    } label: {
                        Text("Continue with Google")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Color(hex: 0x1F1F1F))
                            .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                            .background(.white, in: .rect(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x747775), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(account.isSigningIn || !account.isConfigured)
                .overlay {
                    if account.isSigningIn { ProgressView().controlSize(.large) }
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
    }

    private static let buttonHeight: CGFloat = 56
}
