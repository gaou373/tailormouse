import XCTest
@testable import TailorMouseCore

final class ProfileTests: XCTestCase {
    func testMappedPairSurvivesAppSwitchAndSuppressesDrag() {
        var router = ButtonPairRouter()
        let mapped = MouseProfile(button3: .back)
        let plain = MouseProfile()
        XCTAssertEqual(router.route(button: 3, phase: .down, profile: mapped), ButtonDecision(suppress: true, emit: .back))
        XCTAssertEqual(router.route(button: 3, phase: .drag, profile: plain), ButtonDecision(suppress: true, emit: nil))
        XCTAssertEqual(router.route(button: 3, phase: .up, profile: plain), ButtonDecision(suppress: true, emit: nil))
        XCTAssertFalse(router.route(button: 3, phase: .drag, profile: mapped).suppress)
    }
    func testPassthroughPairSurvivesEditAndUnknownUpIsNotSwallowed() {
        var router = ButtonPairRouter()
        _ = router.route(button: 4, phase: .down, profile: MouseProfile())
        XCTAssertFalse(router.route(button: 4, phase: .up, profile: MouseProfile(button4: .paste)).suppress)
        XCTAssertFalse(router.route(button: 3, phase: .up, profile: MouseProfile(button3: .copy)).suppress)
    }
    func testButtonsAreIndependentAndRepeatedDownDoesNotEmit() {
        var router = ButtonPairRouter()
        let profile = MouseProfile(button3: .copy, button4: .paste)
        XCTAssertEqual(router.route(button: 3, phase: .down, profile: profile).emit, .copy)
        XCTAssertEqual(router.route(button: 4, phase: .down, profile: profile).emit, .paste)
        XCTAssertNil(router.route(button: 3, phase: .down, profile: MouseProfile()).emit)
        XCTAssertTrue(router.route(button: 3, phase: .up, profile: profile).suppress)
        XCTAssertTrue(router.route(button: 4, phase: .up, profile: profile).suppress)
    }
    func testWheelFractionsAndInversion() {
        var wheel = WheelTransformer()
        let slow = MouseProfile(wheelSpeed: 0.25)
        XCTAssertEqual((0..<4).map { _ in wheel.transform([1, 0, 0], continuous: false, profile: slow)[0] }, [0, 0, 0, 1])
        XCTAssertEqual(wheel.transform([2, -1, 0], continuous: false, profile: MouseProfile(invertWheel: true, wheelSpeed: 2)), [-4, 2, 0])
    }
    func testContinuousScrollingPassesThrough() {
        var wheel = WheelTransformer()
        XCTAssertEqual(wheel.transform([10, -3], continuous: true, profile: MouseProfile(invertWheel: true, wheelSpeed: 4)), [10, -3])
    }
    func testProfileSelectionAndSpeedValidation() throws {
        let app = MouseProfile(name: "Browser", bundleIdentifier: "org.example.browser", button3: .back)
        let config = ProfileConfiguration(appProfiles: [app])
        XCTAssertEqual(config.profile(for: "org.example.browser"), app)
        XCTAssertEqual(config.profile(for: nil), config.defaultProfile)
        XCTAssertEqual(config.profile(for: "other"), config.defaultProfile)
        XCTAssertEqual(MouseProfile(wheelSpeed: .nan).safeWheelSpeed, 1)
        XCTAssertEqual(MouseProfile(wheelSpeed: 99).safeWheelSpeed, 4)
        XCTAssertEqual(try JSONDecoder().decode(ProfileConfiguration.self, from: JSONEncoder().encode(config)), config)
    }
}
