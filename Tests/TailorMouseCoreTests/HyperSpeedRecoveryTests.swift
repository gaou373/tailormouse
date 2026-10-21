import XCTest
@testable import TailorMouseCore

final class HyperSpeedRecoveryTests: XCTestCase {
    private let hyper = DeviceIdentity(vendorID: 0x1532, productID: 0x00b4, transport: "USB", product: "HyperSpeed")
    private var pro: DeviceIdentity { DeviceIdentity(vendorID: 0x1532, productID: 0x0090, transport: "USB", product: "Pro") }
    private func packet(_ keys: [UInt8]) -> [UInt8] { [6,0] + keys + Array(repeating: 0, count: 6-keys.count) }
    func testLegacyProCalibrationDoesNotAffectHyperSpeedAndRoundTrips() throws {
        var config = ProfileConfiguration(nagaKeyboardLayouts: ["USB": NagaKeyboardLayout(keyOverrides: ["18":109], sequences: [NagaKeySequence(button: 110, keyCodes: [18,19])], doubleClickPrefixes: [18])])
        XCTAssertEqual(config.nagaInputLayout(for: pro).button(for: 18), 109)
        XCTAssertEqual(config.nagaInputLayout(for: hyper), NagaKeyboardLayout())
        let key = ProfileConfiguration.nagaCalibrationKey(family: hyper.canonicalFamily, transport: "USB")
        config.nagaKeyboardLayouts[key] = NagaKeyboardLayout(keyOverrides: ["18":105])
        let decoded = try JSONDecoder().decode(ProfileConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.nagaInputLayout(for: hyper).button(for: 18), 105)
        XCTAssertEqual(decoded.nagaInputLayout(for: pro).button(for: 18), 109)
    }
    func testScopedProCalibrationTakesPrecedenceOverLegacyOnlyForThatConnection() {
        var config = ProfileConfiguration(nagaKeyboardLayouts: ["USB": NagaKeyboardLayout(keyOverrides: ["18":109])])
        let key = ProfileConfiguration.nagaCalibrationKey(family: pro.canonicalFamily, transport: "USB")
        config.nagaKeyboardLayouts[key] = NagaKeyboardLayout(keyOverrides: ["18":110])
        XCTAssertEqual(config.nagaInputLayout(for: pro).button(for: 18), 110)
        XCTAssertEqual(config.nagaInputLayout(for: hyper).button(for: 18), 100)
    }
    func testBaselineOnlyRemovalDoesNotPoisonSurvivingInterface() {
        var raw = NagaBluetoothReportDecoder()
        raw.prime(reportID: 6, bytes: packet([0x1e]), sourceID: 10)
        raw.prime(reportID: 6, bytes: packet([]), sourceID: 11)
        XCTAssertTrue(raw.removeSource(10).isEmpty)
        XCTAssertEqual(raw.route(reportID: 6, bytes: packet([0x1e]), sourceID: 11).map(\.phase), [.down])
        XCTAssertEqual(raw.route(reportID: 6, bytes: packet([]), sourceID: 11).map(\.phase), [.up])
        XCTAssertTrue(raw.removeSource(10).isEmpty)
    }
    func testRemovalKeepsOtherOwnerAndReleasesOnlyDepartingKeys() {
        var raw = NagaBluetoothReportDecoder()
        _ = raw.route(reportID: 6, bytes: packet([0x1e,0x1f]), sourceID: 10)
        _ = raw.route(reportID: 6, bytes: packet([0x1e]), sourceID: 11)
        let released = raw.removeSource(10)
        XCTAssertEqual(released.map(\.keyCode), [19]); XCTAssertEqual(released.map(\.phase), [.up])
        XCTAssertEqual(raw.route(reportID: 6, bytes: packet([]), sourceID: 11).map(\.keyCode), [18])
        XCTAssertTrue(raw.removeSource(11).isEmpty)
    }
    func testBaselineOwnedModifierGetsOneMatchedReleaseOnRemoval() {
        var raw = NagaBluetoothReportDecoder(); var keyboard = NagaKeyboardDecoder(); var router = InputRouter()
        let binding = ActionBinding(action: .modifierKey, modifierKey: .command)
        let profile = MouseProfile(bindings: ["100":binding])
        _ = keyboard.route(NagaKeyboardInput(token: 1, keyCode: 18, phase: .down, modifiers: [], profile: profile), now: 0, layout: NagaKeyboardLayout())
        _ = router.route(button: 100, phase: .down, profile: profile)
        raw.prime(reportID: 6, bytes: packet([0x1e]), alreadyOwned: keyboard.ownedKeys, sourceID: 10)
        raw.prime(reportID: 6, bytes: packet([]), sourceID: 11)
        let edges = raw.removeSource(10)
        XCTAssertEqual(edges.map(\.phase), [.up])
        let result = keyboard.route(NagaKeyboardInput(token: 2, keyCode: 18, phase: .up, modifiers: [], profile: MouseProfile()), now: 1, layout: NagaKeyboardLayout())
        let emissions = result.dispatches.flatMap { router.route(button: $0.button, phase: $0.phase, profile: $0.profile).emissions }
        XCTAssertEqual(emissions.map(\.phase), [.up]); XCTAssertEqual(emissions.map(\.binding), [binding])
        XCTAssertTrue(router.reset().isEmpty); XCTAssertTrue(raw.removeSource(10).isEmpty)
    }
}
