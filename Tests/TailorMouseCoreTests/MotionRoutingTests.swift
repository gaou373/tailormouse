import XCTest
@testable import TailorMouseCore

final class MotionRoutingTests: XCTestCase {
    func testUnmatchedAndPassthroughDragsRemainNativeAcrossProfileChanges() {
        var router = InputRouter()
        XCTAssertFalse(router.suppressesDrag(button: 2))
        _ = router.route(button: 2, phase: .down, profile: MouseProfile())
        let edited = MouseProfile(bindings: ["2":ActionBinding(action: .copy)])
        XCTAssertFalse(router.suppressesDrag(button: 2))
        XCTAssertFalse(router.route(button: 2, phase: .up, profile: edited).suppress)
    }
    func testRemappedDragsRetainPressOwnershipAndRecovery() {
        var router = InputRouter()
        let binding = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 8), shortcutBehavior: .hold)
        let profile = MouseProfile(bindings: ["2":binding])
        XCTAssertEqual(router.route(button: 2, phase: .down, profile: profile).emissions.map(\.phase), [.down])
        for _ in 0..<1000 { XCTAssertTrue(router.suppressesDrag(button: 2)) }
        XCTAssertEqual(router.route(button: 2, phase: .up, profile: MouseProfile()).emissions.map(\.phase), [.up])
        XCTAssertFalse(router.suppressesDrag(button: 2))
        _ = router.route(button: 2, phase: .down, profile: profile)
        XCTAssertEqual(router.reset().map(\.phase), [.up])
        XCTAssertFalse(router.suppressesDrag(button: 2)); XCTAssertTrue(router.reset().isEmpty)
    }
    func testCompletedChordDragAndPairedReleaseRemainSuppressed() {
        var router = InputRouter()
        let held = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 8), shortcutBehavior: .hold)
        let profile = MouseProfile(chords: [ChordBinding(buttons: [100,2], binding: held)])
        _ = router.route(button: 100, phase: .down, profile: profile)
        XCTAssertEqual(router.route(button: 2, phase: .down, profile: profile).emissions.map(\.phase), [.down])
        XCTAssertTrue(router.suppressesDrag(button: 2))
        XCTAssertEqual(router.route(button: 2, phase: .up, profile: profile).emissions.map(\.phase), [.up])
        _ = router.route(button: 100, phase: .up, profile: profile)
        XCTAssertFalse(router.suppressesDrag(button: 2)); XCTAssertTrue(router.reset().isEmpty)
    }
    func testRawAttachmentPreservesReleaseOfANativeOwnedHold() {
        var keyboard = NagaKeyboardDecoder(); var reports = NagaBluetoothReportDecoder(); var router = InputRouter()
        let binding = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 8), shortcutBehavior: .hold)
        let profile = MouseProfile(bindings: ["100":binding])
        let down = keyboard.route(NagaKeyboardInput(token: 1, keyCode: 18, phase: .down, modifiers: [], profile: profile), now: 0, layout: NagaKeyboardLayout())
        XCTAssertEqual(down.dispatches.count, 1)
        XCTAssertEqual(router.route(button: 100, phase: .down, profile: profile).emissions.map(\.phase), [.down])
        reports.prime(reportID: 6, bytes: [6,0,0x1e,0,0,0,0,0], alreadyOwned: keyboard.ownedKeys)
        XCTAssertTrue(reports.route(reportID: 6, bytes: [6,0,0x1e,0,0,0,0,0]).isEmpty)
        let released = reports.route(reportID: 6, bytes: [6,0,0,0,0,0,0,0])
        XCTAssertEqual(released.map(\.phase), [.up])
        let up = keyboard.route(NagaKeyboardInput(token: 2, keyCode: released[0].keyCode, phase: .up, modifiers: [], profile: profile), now: 1, layout: NagaKeyboardLayout())
        XCTAssertEqual(up.dispatches.map(\.button), [100])
        XCTAssertEqual(router.route(button: 100, phase: .up, profile: profile).emissions.map(\.phase), [.up])
        XCTAssertTrue(router.reset().isEmpty); XCTAssertTrue(keyboard.ownedKeys.isEmpty)
    }
    func testRawAttachmentStillIgnoresUnownedPreStartKeys() {
        var reports = NagaBluetoothReportDecoder()
        reports.prime(reportID: 6, bytes: [6,0,0x1e,0x1f,0,0,0,0], alreadyOwned: [18])
        let up = reports.route(reportID: 6, bytes: [6,0,0,0,0,0,0,0])
        XCTAssertEqual(up.map(\.keyCode), [18]); XCTAssertEqual(up.map(\.phase), [.up])
        XCTAssertTrue(reports.route(reportID: 6, bytes: [6,0,0,0,0,0,0,0]).isEmpty)
    }
    func testDeviceSnapshotEqualityIncludesAttributionAndConnectionChanges() {
        let id = DeviceIdentity(vendorID: 0x1532, productID: 0x0090, transport: "USB", product: "Naga")
        let a = DeviceEndpoint(id: 1, identity: id, senderIDs: [1,2], connectionID: "receiver", canIdentifyEvents: true)
        XCTAssertEqual(a, DeviceEndpoint(id: 1, identity: id, senderIDs: [1,2], connectionID: "receiver", canIdentifyEvents: true))
        XCTAssertNotEqual(a, DeviceEndpoint(id: 1, identity: id, senderIDs: [1,3], connectionID: "receiver", canIdentifyEvents: true))
        XCTAssertNotEqual(a, DeviceEndpoint(id: 1, identity: id, senderIDs: [1,2], connectionID: "wired", canIdentifyEvents: true))
    }
}
