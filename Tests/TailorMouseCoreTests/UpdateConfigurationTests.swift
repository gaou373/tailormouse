import XCTest
@testable import TailorMouseCore

final class UpdateConfigurationTests: XCTestCase {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()
    func testAcceptsPublicHTTPSFeedAnd32ByteKey() {
        let feed = "https://github.com/gaou373/tailormouse/releases/latest/download/appcast.xml"
        let config = UpdateConfiguration(feedURL: feed, publicKey: key)
        XCTAssertEqual(config?.feedURL.absoluteString, feed)
        XCTAssertEqual(config?.publicKey, key)
    }
    func testRejectsLocalInsecureOrCredentialBearingFeeds() {
        for feed in ["http://example.com/feed.xml", "file:///tmp/feed.xml", "https:///", "https://user:password@example.com/feed.xml", "https://example.com/feed.xml#fragment", "not a URL"] {
            XCTAssertNil(UpdateConfiguration(feedURL: feed, publicKey: key), feed)
        }
    }
    func testRejectsInvalidSigningKeys() {
        for key in ["", "not base64", Data(repeating: 1, count: 31).base64EncodedString(), Data(repeating: 1, count: 64).base64EncodedString()] {
            XCTAssertNil(UpdateConfiguration(feedURL: "https://example.com/feed.xml", publicKey: key))
        }
    }
    func testRejectsUpdatingFromDiskImageTranslocationOrLooseExecutable() {
        for path in ["/Volumes/TailorMouse/TailorMouse.app", "/private/var/folders/a/AppTranslocation/b/d/TailorMouse.app", "/tmp/TailorMouse"] {
            XCTAssertNotNil(UpdateConfiguration.installationBlocker(bundleURL: URL(fileURLWithPath: path), hasOpenEditor: false))
        }
        for path in ["/Applications/TailorMouse.app", "/Users/example/Applications/TailorMouse.app"] {
            XCTAssertNil(UpdateConfiguration.installationBlocker(bundleURL: URL(fileURLWithPath: path), hasOpenEditor: false))
        }
    }
    func testOpenEditorMustFinishBeforeUpdateCheck() {
        let app = URL(fileURLWithPath: "/Applications/TailorMouse.app")
        XCTAssertNotNil(UpdateConfiguration.installationBlocker(bundleURL: app, hasOpenEditor: true))
        XCTAssertNil(UpdateConfiguration.installationBlocker(bundleURL: app, hasOpenEditor: false))
    }
}
