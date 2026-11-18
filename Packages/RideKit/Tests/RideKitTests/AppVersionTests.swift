import Testing
@testable import RideKit

@Suite("App version")
struct AppVersionTests {
    @Test func comparesPartByPart() throws {
        #expect(try #require(AppVersion("1.9.0")) < #require(AppVersion("1.10.0")))
        #expect(try #require(AppVersion("1.2")) == #require(AppVersion("1.2.0")))
        #expect(try #require(AppVersion("2.0 (45)")).description == "2.0")
        #expect(try #require(AppVersion("1.3.0-beta")).description == "1.3.0")
        #expect(AppVersion("") == nil)
        #expect(AppVersion("beta") == nil)
    }

    @Test func needsUpdate() {
        #expect(AppVersion.needsUpdate(current: "1.1.0", minimum: "1.2.0"))
        #expect(!AppVersion.needsUpdate(current: "1.2.0", minimum: "1.2.0"))
        #expect(!AppVersion.needsUpdate(current: "1.10.0", minimum: "1.9.5"))
        #expect(!AppVersion.needsUpdate(current: "1.0.0", minimum: nil))
        #expect(!AppVersion.needsUpdate(current: "1.0.0", minimum: "oops"))
    }
}
