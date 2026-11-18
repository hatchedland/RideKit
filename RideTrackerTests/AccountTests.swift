import Testing
@testable import RideTracker

@MainActor
@Suite("Account")
struct AccountTests {
    @Test func appleNonceIsHashedForApple() {
        let nonce = AccountService.randomNonce()
        #expect(nonce.count == 32)
        #expect(AccountService.randomNonce() != nonce)
        // SHA-256 of "abc", as Apple expects it: lowercase hex.
        #expect(AccountService.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func signInComesBackToTheApp() {
        #expect(AccountService.redirectURL.absoluteString == "ridetracker://auth-callback")
    }
}
