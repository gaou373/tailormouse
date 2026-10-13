import XCTest
@testable import TailorMouseCore

final class FixRequestControlsTests: XCTestCase {
    private let baseline = NativePointerValues(resolution: 90112000, acceleration: 52429)
    func testNeutralBluetoothTrackingDoesNotWriteNativeProperties() throws {
        let bluetooth = NativePointerValues(resolution: 26214400, acceleration: 32768)
        let target = try bluetooth.target(profile: MouseProfile())
        var writes = 0
        try NativePointerTransaction.apply(before: bluetooth, target: target, write: { _, _ in writes += 1 }, read: { bluetooth })
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(target, bluetooth)
    }
    func testSensitivityDirectionAndAccelerationAreIndependentOnBluetooth() throws {
        let bluetooth = NativePointerValues(resolution: 26214400, acceleration: 32768)
        let slower = try bluetooth.target(profile: MouseProfile(pointerSensitivity: 0.8))
        let faster = try bluetooth.target(profile: MouseProfile(pointerSensitivity: 1.2))
        XCTAssertGreaterThan(slower.resolution, bluetooth.resolution)
        XCTAssertLessThan(faster.resolution, bluetooth.resolution)
        XCTAssertEqual(slower.acceleration, bluetooth.acceleration)
        XCTAssertEqual(faster.acceleration, bluetooth.acceleration)
    }
    func testRequestedCategoryOrderAndEveryExistingActionIsRepresented() {
        XCTAssertEqual(ActionCategory.allCases.map(\.rawValue), ["Click", "Scroll", "Keyboard Shortcut", "System Control", "Zoom", "Mission Control", "Music Control", "Application Switcher", "Cursor Snapping", "Open", "No Action"])
        for action in ButtonAction.allCases { XCTAssertTrue(ActionCategory.category(for: action).actions.contains(action)) }
        XCTAssertEqual(ActionCategory.category(for: .passthrough, wheel: true), .scroll)
    }
    func testNewControlsAndActionsRoundTrip() throws {
        var profile = MouseProfile(pointerAcceleration: 0.8, pointerSensitivity: 1.5)
        profile.wheelBindings["up:1"] = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 8, modifiers: .command))
        profile.bindings["100"] = ActionBinding(action: .open, openTarget: "https://example.com")
        profile.bindings["101"] = ActionBinding(action: .cursorSnap, snapDestination: "window")
        XCTAssertEqual(try JSONDecoder().decode(MouseProfile.self, from: JSONEncoder().encode(profile)), profile)
    }
    func testMissingNewFieldsPreserveLegacyProfiles() throws {
        let data = try JSONEncoder().encode(MouseProfile(wheelSpeed: 2, button3: .copy))
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["pointerAcceleration", "pointerSensitivity", "wheelBindings"] { json.removeValue(forKey: key) }
        let profile = try JSONDecoder().decode(MouseProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(profile.pointerAcceleration); XCTAssertNil(profile.pointerSensitivity); XCTAssertTrue(profile.wheelBindings.isEmpty)
        XCTAssertEqual(profile.wheelSpeed, 2); XCTAssertEqual(profile.button3, .copy)
    }
    func testWheelDirectionMappingPreservesUnmappedAxis() {
        var profile = MouseProfile(); profile.wheelBindings["up"] = ActionBinding(action: .copy)
        let actions = WheelActionRouter.route(deltas: [1, -1, 3], continuous: false, profile: profile, modifiers: [])
        XCTAssertEqual(actions.map(\.axis), [0]); XCTAssertEqual(actions.map { $0.binding.action }, [.copy])
        XCTAssertTrue(WheelActionRouter.route(deltas: [-1, 1], continuous: false, profile: profile, modifiers: []).isEmpty)
    }
    func testContinuousAndZeroDeltaInputRemainNative() {
        var profile = MouseProfile(); profile.wheelBindings["up"] = ActionBinding(action: .disabled)
        XCTAssertTrue(WheelActionRouter.route(deltas: [1, 1], continuous: true, profile: profile, modifiers: []).isEmpty)
        XCTAssertTrue(WheelActionRouter.route(deltas: [0, 0], continuous: false, profile: profile, modifiers: []).isEmpty)
        XCTAssertTrue(WheelActionRouter.route(deltas: [1, 1], continuous: false, profile: MouseProfile(), modifiers: []).isEmpty)
    }
    func testWheelModifierOverrideAndInheritedFallback() {
        var profile = MouseProfile(); profile.wheelBindings["down"] = ActionBinding(action: .copy)
        profile.wheelBindings["down:1"] = ActionBinding(action: .paste)
        XCTAssertEqual(profile.wheelBinding(direction: .down, modifiers: .command).action, .paste)
        XCTAssertEqual(profile.wheelBinding(direction: .down, modifiers: .shift).action, .copy)
        XCTAssertEqual(MouseProfile().wheelBinding(direction: .down).scrollY, -3)
        XCTAssertEqual(MouseProfile().wheelBinding(direction: .left).scrollX, 3)
    }
    func testNativeSensitivityAndAccelerationHaveIndependentTargets() throws {
        let target = try baseline.target(profile: MouseProfile(pointerAcceleration: 0.75, pointerSensitivity: 2))
        XCTAssertEqual(target.resolution, 45056000); XCTAssertEqual(target.acceleration, 49152)
        XCTAssertEqual(try baseline.target(profile: MouseProfile()), baseline)
        XCTAssertThrowsError(try baseline.target(profile: MouseProfile(pointerSensitivity: .infinity)))
        XCTAssertThrowsError(try baseline.target(profile: MouseProfile(pointerAcceleration: -0.5)))
    }
    func testResolutionChangeReappliesAccelerationToCommitCurve() throws {
        let target = NativePointerValues(resolution: baseline.resolution / 2, acceleration: baseline.acceleration)
        var writes: [NativePointerProperty] = []
        try NativePointerTransaction.apply(before: baseline, target: target, write: { property, _ in writes.append(property) }, read: { target })
        XCTAssertEqual(writes, [.resolution, .acceleration])
    }
    func testLandedResolutionFailureRecoversBeforeReapplyingCurve() {
        let target = NativePointerValues(resolution: baseline.resolution / 2, acceleration: baseline.acceleration)
        var resolution = baseline.resolution; var acceleration = baseline.acceleration; var writes: [NativePointerProperty] = []
        XCTAssertThrowsError(try NativePointerTransaction.apply(before: baseline, target: target, write: { property, value in
            writes.append(property)
            if property == .resolution { resolution = value } else { acceleration = value }
            if writes.count == 1 { throw NativePointerError.writeFailed }
        }, read: { NativePointerValues(resolution: resolution, acceleration: acceleration) }))
        XCTAssertEqual(writes, [.resolution, .resolution, .acceleration])
        XCTAssertEqual(resolution, baseline.resolution); XCTAssertEqual(acceleration, baseline.acceleration)
    }
    func testReadbackFailureRestoresBothNativeProperties() {
        let target = NativePointerValues(resolution: baseline.resolution / 2, acceleration: 0)
        var writes: [Int64] = []
        XCTAssertThrowsError(try NativePointerTransaction.apply(before: baseline, target: target, write: { _, value in writes.append(value) }, read: { self.baseline }))
        XCTAssertEqual(writes, [target.resolution, target.acceleration, baseline.resolution, baseline.acceleration])
    }
    func testFailedNativeRecoveryIsReported() {
        XCTAssertThrowsError(try NativePointerTransaction.apply(before: baseline,
            target: NativePointerValues(resolution: 1, acceleration: 0), write: { _, _ in throw NativePointerError.writeFailed }, read: { self.baseline })) { error in
                guard case NativePointerError.recoveryFailed = error else { return XCTFail("Must report recovery failure") }
            }
    }
    func testNewActionCapturesPressAndMatchingReleaseAcrossEdits() {
        var profile = MouseProfile(); let original = ActionBinding(action: .open, openTarget: "https://example.com")
        profile.bindings["100"] = original
        var router = InputRouter()
        XCTAssertEqual(router.route(button: 100, phase: .down, profile: profile).emissions.map(\.binding), [original])
        profile.bindings["100"] = ActionBinding(action: .passthrough)
        XCTAssertTrue(router.route(button: 100, phase: .down, profile: profile).emissions.isEmpty)
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: profile).suppress)
        router.reset(); XCTAssertFalse(router.route(button: 100, phase: .up, profile: profile).suppress)
    }
    func testServiceBaselinesDoNotCompoundOrCrossSources() throws {
        let other = NativePointerValues(resolution: 26214400, acceleration: 52429)
        let profile = MouseProfile(pointerSensitivity: 2)
        XCTAssertEqual(try baseline.target(profile: profile).resolution, baseline.resolution / 2)
        XCTAssertEqual(try other.target(profile: profile).resolution, other.resolution / 2)
        XCTAssertEqual(try baseline.target(profile: MouseProfile(pointerSensitivity: 1)), baseline)
    }
}
