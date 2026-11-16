import Testing
@testable import RideTracker

@MainActor
@Suite("Account")
struct AccountTests {
    @Test(arguments: ["rider@example.com", "a.b+rides@mail.co.in"])
    func acceptsEmails(_ email: String) {
        #expect(AccountService.looksLikeEmail(email))
    }

    @Test(arguments: ["", "rider", "rider@", "@example.com", "rider@example", "rider@.com", "rider@example.", "a b@example.com", "a@b@c.com"])
    func rejectsNonEmails(_ text: String) {
        #expect(!AccountService.looksLikeEmail(text))
    }

    @Test func signInLinksComeBackToTheApp() {
        #expect(AccountService.redirectURL.absoluteString == "ridetracker://auth-callback")
    }
}
