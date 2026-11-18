import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import OSLog
import RideKit
import Supabase

/// The rider's Ride Tracker account (Supabase Auth). Required: signed out, the app shows only sign-in.
///
/// Sign in with Apple (native sheet → ID token) or Google (Supabase OAuth in an in-app browser sheet,
/// back through `ridetracker://auth-callback`). No email/password and no email links (decided
/// 2026-11-18). An account with the same verified email is the same account whichever way the rider
/// signs in. The session is kept in the Keychain by the SDK.
@MainActor
@Observable
final class AccountService {
    enum State: Equatable {
        /// At launch, until the saved session (if any) has been read.
        case checking
        case signedOut
        /// Apple may hide the address (private relay) — it's for display only.
        case signedIn(email: String)
    }

    private(set) var state: State = .checking
    private(set) var error: String?
    /// A sign-in sheet is open or the token is being exchanged.
    private(set) var isSigningIn = false
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
        applyVersionConfig(UserDefaults.standard.stringArray(forKey: Self.versionConfigKey))
        Task { await watchSession() }
        Task { await checkVersion() }
    }

    // MARK: Minimum version

    /// The server says this build is too old to sync (`app_config.min_version`). The app then asks the
    /// rider to update — never during a ride — and stops syncing until they do.
    struct UpdateRequired: Equatable {
        var minimum: String
        var storeURL: URL?
    }

    private(set) var updateRequired: UpdateRequired?
    private var versionCheckedAt: Date?
    private static let versionConfigKey = "appConfig.ios"
    nonisolated static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Reads the oldest allowed version. Offline, the last answer stands (saved on the phone), so a
    /// rider with no signal is never newly blocked and an old build never syncs after being told not to.
    func checkVersion(ifOlderThan maxAge: TimeInterval = 0) async {
        guard let client else { return }
        if let checked = versionCheckedAt, Date.now.timeIntervalSince(checked) < maxAge { return }
        struct Row: Decodable {
            var minVersion: String
            var storeURL: String?
            enum CodingKeys: String, CodingKey { case minVersion = "min_version", storeURL = "store_url" }
        }
        do {
            let row: Row = try await client.from("app_config").select("min_version, store_url")
                .eq("platform", value: "ios").single().execute().value
            let saved = [row.minVersion, row.storeURL ?? ""]
            UserDefaults.standard.set(saved, forKey: Self.versionConfigKey)
            applyVersionConfig(saved)
            versionCheckedAt = .now
        } catch {
            Self.log.info("Version check skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyVersionConfig(_ saved: [String]?) {
        guard let saved, let minimum = saved.first,
              AppVersion.needsUpdate(current: Self.currentVersion, minimum: minimum) else {
            updateRequired = nil
            return
        }
        let store = saved.count > 1 ? saved[1] : ""
        updateRequired = UpdateRequired(minimum: minimum, storeURL: store.isEmpty ? nil : URL(string: store))
    }

    /// Follows sign-in, sign-out and session refreshes, including a session restored at launch.
    private func watchSession() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            // The SDK refreshes an expired access token itself, so a session means signed in.
            if let email = session?.user.email {
                state = .signedIn(email: email)
                if profile == nil { await loadProfile() }
            } else {
                state = .signedOut
            }
        }
    }

    // MARK: Sign in

    /// Google, through Supabase's OAuth flow in an in-app browser sheet.
    func signInWithGoogle() async {
        guard let client else { error = "Accounts aren't set up in this build."; return }
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        error = nil
        do {
            let session = try await client.auth.signInWithOAuth(provider: .google, redirectTo: Self.redirectURL)
            state = .signedIn(email: session.user.email ?? "")
        } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
            // The rider closed the sheet.
        } catch {
            Self.log.error("Google sign-in failed: \(error.localizedDescription, privacy: .public)")
            self.error = Self.message(for: error)
        }
    }

    /// A fresh nonce for one Sign in with Apple request: Apple gets its SHA-256, Supabase the original.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Finishes Sign in with Apple with the result of the system sheet.
    func completeApple(_ result: Result<ASAuthorization, any Error>) async {
        guard let client else { error = "Accounts aren't set up in this build."; return }
        switch result {
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code != .canceled {
                Self.log.error("Apple sign-in failed: \(failure.localizedDescription, privacy: .public)")
                error = "Sign in with Apple didn't work. Try again."
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
                  let nonce = appleNonce else {
                error = "Sign in with Apple didn't work. Try again."
                return
            }
            isSigningIn = true
            defer { isSigningIn = false; appleNonce = nil }
            error = nil
            do {
                let session = try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: nonce))
                // Apple shares the name only the first time; it fills the name field of the @handle step.
                if let name = credential.fullName.map({ PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }),
                   !name.isEmpty, AppSettings.riderName.isEmpty {
                    AppSettings.riderName = name
                }
                state = .signedIn(email: session.user.email ?? "")
            } catch {
                Self.log.error("Apple token exchange failed: \(error.localizedDescription, privacy: .public)")
                self.error = Self.message(for: error)
            }
        }
    }

    private var appleNonce: String?

    nonisolated static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator)! })
    }

    nonisolated static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Handles `ridetracker://auth-callback…` if the OAuth result arrives as a URL open rather than
    /// inside the browser sheet. Returns whether it was ours.
    @discardableResult
    func handle(_ url: URL) async -> Bool {
        guard let client, url.scheme == Self.redirectURL.scheme, url.host() == Self.redirectURL.host() else { return false }
        do {
            let session = try await client.auth.session(from: url)
            state = .signedIn(email: session.user.email ?? "")
            error = nil
        } catch {
            Self.log.error("Sign-in callback didn't work: \(error.localizedDescription, privacy: .public)")
            self.error = "Sign-in didn't finish. Try again."
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

    /// Deletes the account for good: the rider's files in Storage (tracks, shared rides and their
    /// photo copies), then the account itself, which removes every row of theirs on the server.
    /// Photos in the Photos library are never touched. Returns an error message, or `nil` once
    /// deleted; the caller then clears this phone's copy.
    func deleteAccount() async -> String? {
        guard let client else { return "Accounts aren't set up in this build." }
        do {
            let me = try await client.auth.session.user.id.uuidString.lowercased()
            for bucket in ["tracks", "shared"] {
                let files = try await Self.files(in: client.storage.from(bucket), under: me)
                // The API removes up to 1,000 paths per call.
                for start in stride(from: 0, to: files.count, by: 1000) {
                    _ = try await client.storage.from(bucket).remove(paths: Array(files[start..<min(start + 1000, files.count)]))
                }
            }
            try await client.rpc("delete_my_account").execute()
        } catch {
            return (error as? URLError) != nil ? "No connection. Try again when you have signal." : "Couldn't delete your account. Try again."
        }
        try? await client.auth.signOut()
        profile = nil
        state = .signedOut
        return nil
    }

    /// Every file under `folder`, folders included recursively (a listed item without an id is a folder).
    private static func files(in bucket: StorageFileApi, under folder: String) async throws -> [String] {
        var paths: [String] = []
        var offset = 0
        while true {
            let page = try await bucket.list(path: folder, options: SearchOptions(limit: 1000, offset: offset))
            for item in page {
                let path = "\(folder)/\(item.name)"
                if item.id == nil {
                    paths += try await files(in: bucket, under: path)
                } else {
                    paths.append(path)
                }
            }
            guard page.count == 1000 else { return paths }
            offset += 1000
        }
    }

    private static func message(for error: any Error) -> String {
        if (error as? URLError) != nil {
            return "No connection. Try again when you have signal."
        }
        return "Couldn't sign in. Try again."
    }
}
