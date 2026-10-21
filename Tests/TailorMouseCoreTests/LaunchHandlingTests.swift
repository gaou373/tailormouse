import XCTest
@testable import TailorMouseCore

final class LaunchHandlingTests: XCTestCase {
    func testStartsOnceAndWindowReopenCannotUndoStop() {
        var policy = LaunchHandling()
        XCTAssertTrue(policy.shouldStart(enabled: true, preview: false))
        XCTAssertFalse(policy.shouldStart(enabled: true, preview: false))
        var nextLaunch = LaunchHandling()
        XCTAssertTrue(nextLaunch.shouldStart(enabled: true, preview: false))
    }
    func testPreviewNeverConsumesOrStartsTheRealLaunch() {
        var policy = LaunchHandling()
        XCTAssertFalse(policy.shouldStart(enabled: true, preview: true))
        XCTAssertFalse(policy.shouldStart(enabled: true, preview: true))
        XCTAssertTrue(policy.shouldStart(enabled: true, preview: false))
    }
    func testDisabledAtLaunchDoesNotStartWhenAWindowReappears() {
        var policy = LaunchHandling()
        XCTAssertFalse(policy.shouldStart(enabled: false, preview: false))
        XCTAssertFalse(policy.shouldStart(enabled: true, preview: false))
    }
    func testLegacySettingsStartAutomaticallyAndExplicitOptOutRoundTrips() throws {
        var config = ProfileConfiguration()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String: Any]
        object.removeValue(forKey: "autoStartOnOpen")
        XCTAssertTrue(try JSONDecoder().decode(ProfileConfiguration.self, from: JSONSerialization.data(withJSONObject: object)).autoStartOnOpen)
        config.autoStartOnOpen = false
        XCTAssertEqual(try JSONDecoder().decode(ProfileConfiguration.self, from: JSONEncoder().encode(config)), config)
    }
}
