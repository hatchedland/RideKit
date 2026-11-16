import Foundation
import Observation
import OSLog
import Supabase

/// The rider's Ride Tracker account (Supabase Auth). Required: signed out, the app shows only sign-in.
///
/// Sign-in is passwordless by email link: Supabase emails a link that opens
/// `ridetracker://auth-callback` in this app, which finishes the sign-in. (A 6-digit code needs a
/// custom email template, which free projects only get with their own SMTP sender; planned before
/// the App Store release.) The session is kept in the Keychain by the SDK.
@MainActor
@Observable
final class AccountService {
    enum State: Equatable {
        /// At launch, until the saved session (if any) has been read.
        case checking
        case signedOut
        /// The link is on its way to this address.
        case linkSent(email: String, at: Date)
        case signedIn(email: String)
    }

    private(set) var state: State = .checking
    private(set) var error: String?
    /// The rider's name and @handle, once loaded after sign-in.
    private(set) var profile: Profile?

    struct Profile: Equatable, Decodable {
        var username: String?
        var displayName: String
        enum CodingKeys: String, CodingKey { case username, displayName = "display_name" }
    }

    /// Signed in but no @handle yet: the app asks for one before anything else.
    var needsHandle: Bool { isSignedIn && profile != nil && (profile?.username ?? "").isEmpty }

    /// `nil` when the app was built without a Supabase project (see Config/Secrets.example.xcconfig).
    let client: SupabaseClient?
    static let redirectURL = URL(string: "ridetracker://auth-callback")!
    private static let log = Logger(subsystem: "com.hatchedland.ridetracker", category: "account")

    var isSignedIn: Bool { if case .signedIn = state { true } else { false } }
    var isConfigured: Bool { client != nil }

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let host = (info["SupabaseHost"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (info["SupabaseKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if !host.isEmpty, !host.contains("YOUR_"), !key.isEmpty, let url = URL(string: "https://\(host)") {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else {
            client = nil
            state = .signedOut
        }
        Task { await watchSession() }
    }

    /// Follows sign-in, sign-out and session refreshes, including a session restored at launch.
    private func watchSession() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            // The SDK refreshes an expired access token itself, so a session means signed in.
            if let email = session?.user.email {
                state = .signedIn(email: email)
                if profile == nil { await loadProfile() }
            } else if case .linkSent = state {
                // Still waiting for the rider to tap the link.
            } else {
                state = .signedOut
            }
        }
    }

    /// Emails a sign-in link. New riders get an account the first time they use it.
    func sendLink(to input: String) async {
        let email = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let client else { error = "Accounts aren't set up in this build."; return }
        guard Self.looksLikeEmail(email) else { error = "That doesn't look like an email address."; return }
        error = nil
        do {
            try await client.auth.signInWithOTP(email: email, redirectTo: Self.redirectURL, shouldCreateUser: true)
            state = .linkSent(email: email, at: .now)
        } catch {
            Self.log.error("Sign-in link failed: \(error.localizedDescription, privacy: .public)")
            self.error = Self.message(for: error)
        }
    }

    /// Handles `ridetracker://auth-callback…` from the email link. Returns whether it was ours.
    @discardableResult
    func handle(_ url: URL) async -> Bool {
        guard let client, url.scheme == Self.redirectURL.scheme, url.host() == Self.redirectURL.host() else { return false }
        do {
            let session = try await client.auth.session(from: url)
            state = .signedIn(email: session.user.email ?? "")
            error = nil
        } catch {
            Self.log.error("Sign-in link didn't work: \(error.localizedDescription, privacy: .public)")
            self.error = "That sign-in link has expired or was already used. Send a new one."
        }
        return true
    }

    func loadProfile() async {
        guard let client, let id = try? await client.auth.session.user.id else { return }
        profile = try? await client.from("profiles").select("username, display_name").eq("id", value: id).single().execute().value
        if let name = profile?.displayName, !name.isEmpty { AppSettings.riderName = name }
    }

    /// Saves name and @handle. Returns a message for the rider if it didn't work.
    func saveProfile(name: String, handle input: String) async -> String? {
        let handle = Self.normalisedHandle(input)
        guard Self.isValidHandle(handle) else { return "Use 3–20 letters, numbers, _ or ." }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Add your name, so friends know it's you." }
        guard let client, let id = try? await client.auth.session.user.id else { return "You're signed out." }
        do {
            try await client.from("profiles").update(["username": handle, "display_name": String(name.prefix(60))])
                .eq("id", value: id).execute()
            profile = Profile(username: handle, displayName: name)
            AppSettings.riderName = name
            return nil
        } catch {
            let text = String(describing: error).lowercased()
            if text.contains("duplicate") || text.contains("unique") || text.contains("23505") { return "@\(handle) is taken. Try another." }
            return (error as? URLError) != nil ? "No connection. Try again when you have signal." : "Couldn't save. Try again."
        }
    }

    nonisolated static func normalisedHandle(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
    }

    nonisolated static func isValidHandle(_ handle: String) -> Bool {
        (3...20).contains(handle.count) && handle.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
            && handle == handle.lowercased()
    }

    func signOut() async {
        try? await client?.auth.signOut()
        profile = nil
        state = .signedOut
    }

    /// Back to the email field, e.g. to fix a typo.
    func startOver() {
        state = .signedOut
        error = nil
    }

    static func looksLikeEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !text.contains(" ") else { return false }
        return true
    }

    private static func message(for error: any Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("rate") || text.contains("security purposes") {
            return "Too many sign-in emails just now. Wait a minute and try again."
        }
        if (error as? URLError) != nil {
            return "No connection. Try again when you have signal."
        }
        return "Couldn't send the sign-in email. Try again."
    }
}
