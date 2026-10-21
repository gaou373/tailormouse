import XCTest
@testable import TailorMouseCore

final class NagaBluetoothReportTests: XCTestCase {
    private func report(_ keys: [UInt8] = [], modifiers: UInt8 = 0) -> [UInt8] {
        [6, modifiers] + Array(keys.prefix(6)) + Array(repeating: 0, count: max(0, 6 - keys.count))
    }
    func testObservedSideOneProducesMatchedEdgesWithoutRepeatedDowns() {
        var decoder = NagaBluetoothReportDecoder()
        let down: [UInt8] = [6, 0, 0, 0x1e, 0, 0, 0, 0]
        let up = report()
        for _ in 0..<3 {
            let presses = decoder.route(reportID: 6, bytes: down)
            XCTAssertEqual(presses.map(\.keyCode), [18]); XCTAssertTrue(presses[0].phase == .down)
            XCTAssertTrue(decoder.route(reportID: 6, bytes: down).isEmpty)
            let releases = decoder.route(reportID: 6, bytes: up)
            XCTAssertEqual(releases.map(\.keyCode), [18]); XCTAssertTrue(releases[0].phase == .up)
            XCTAssertTrue(decoder.route(reportID: 6, bytes: up).isEmpty)
        }
    }
    func testAllTwelveStandardButtonsReachExistingKeyboardDecoder() {
        let usages: [UInt8] = Array(0x1e...0x27) + [0x2d, 0x2e]
        var raw = NagaBluetoothReportDecoder(); var keyboard = NagaKeyboardDecoder(); var token: UInt64 = 0
        for (index, usage) in usages.enumerated() {
            for bytes in [report([usage]), report()] {
                let transitions = raw.route(reportID: 6, bytes: bytes)
                XCTAssertEqual(transitions.count, 1)
                for transition in transitions {
                    token += 1
                    let result = keyboard.route(NagaKeyboardInput(token: token, keyCode: transition.keyCode,
                        phase: transition.phase, modifiers: transition.modifiers, profile: MouseProfile()), now: Double(token), layout: NagaKeyboardLayout())
                    XCTAssertTrue(result.consume); XCTAssertEqual(result.dispatches.map(\.button), [100 + index])
                    XCTAssertTrue(result.dispatches[0].phase == transition.phase)
                }
            }
        }
    }
    func testTenElevenHoldIndependentlyUntilTheirOwnRelease() {
        var decoder = NagaBluetoothReportDecoder()
        XCTAssertEqual(decoder.route(reportID: 6, bytes: report([0x27])).map(\.keyCode), [29])
        XCTAssertEqual(decoder.route(reportID: 6, bytes: report([0x27, 0x2d])).map(\.keyCode), [27])
        for _ in 0..<100 { XCTAssertTrue(decoder.route(reportID: 6, bytes: report([0x27, 0x2d])).isEmpty) }
        let firstUp = decoder.route(reportID: 6, bytes: report([0x2d]))
        XCTAssertEqual(firstUp.map(\.keyCode), [29]); XCTAssertTrue(firstUp[0].phase == .up)
        let secondUp = decoder.route(reportID: 6, bytes: report())
        XCTAssertEqual(secondUp.map(\.keyCode), [27]); XCTAssertTrue(secondUp[0].phase == .up)
    }
    func testProfileAndModifierSnapshotSurvivesHeldReportUpdates() {
        var raw = NagaBluetoothReportDecoder(); var keyboard = NagaKeyboardDecoder(); var router = InputRouter()
        var first = MouseProfile(); first.modifierBindings["100:1"] = ActionBinding(action: .copy)
        var second = first; second.modifierBindings["100:1"] = ActionBinding(action: .paste)
        var actions: [ButtonAction] = []; var releases = 0; var token: UInt64 = 0
        for (bytes, profile) in [(report([0x1e], modifiers: 8), first), (report([0x1e]), second), (report(), second)] {
            for input in raw.route(reportID: 6, bytes: bytes) {
                token += 1
                let result = keyboard.route(NagaKeyboardInput(token: token, keyCode: input.keyCode,
                    phase: input.phase, modifiers: input.modifiers, profile: profile), now: Double(token), layout: NagaKeyboardLayout())
                for dispatch in result.dispatches {
                    let routed = router.route(button: dispatch.button, phase: dispatch.phase, profile: dispatch.profile, modifiers: dispatch.modifiers)
                    actions += routed.emissions.map { $0.binding.action }
                    if dispatch.phase == .up { releases += 1; XCTAssertTrue(routed.suppress) }
                }
            }
        }
        XCTAssertEqual(actions, [.copy]); XCTAssertEqual(releases, 1)
    }
    func testRolloverAndMalformedReportsDoNotManufactureReleases() {
        var decoder = NagaBluetoothReportDecoder()
        _ = decoder.route(reportID: 6, bytes: report([0x1e]))
        XCTAssertTrue(decoder.route(reportID: 6, bytes: report([1])).isEmpty)
        XCTAssertTrue(decoder.route(reportID: 1, bytes: report()).isEmpty)
        XCTAssertTrue(decoder.route(reportID: 6, bytes: [6, 0]).isEmpty)
        let released = decoder.route(reportID: 6, bytes: report())
        XCTAssertEqual(released.map(\.keyCode), [18]); XCTAssertTrue(released[0].phase == .up)
    }
    func testPrimeDoesNotFireButtonAlreadyHeldBeforeStart() {
        var decoder = NagaBluetoothReportDecoder()
        decoder.prime(reportID: 6, bytes: report([0x1e]))
        XCTAssertTrue(decoder.route(reportID: 6, bytes: report([0x1e])).isEmpty)
        XCTAssertTrue(decoder.route(reportID: 6, bytes: report()).isEmpty)
        XCTAssertEqual(decoder.route(reportID: 6, bytes: report([0x1e])).map(\.keyCode), [18])
    }
    func testResetAndSourceIsolationAllowFreshPresses() {
        var first = NagaBluetoothReportDecoder(); var second = NagaBluetoothReportDecoder()
        _ = first.route(reportID: 6, bytes: report([0x1e]))
        XCTAssertTrue(second.route(reportID: 6, bytes: report()).isEmpty)
        first.reset()
        XCTAssertTrue(first.route(reportID: 6, bytes: report()).isEmpty)
        XCTAssertEqual(first.route(reportID: 6, bytes: report([0x1e])).count, 1)
    }
    func testQuartzOwnershipIsLimitedToSupportedLayoutKeys() {
        XCTAssertTrue(NagaBluetoothReportDecoder.handles(keyCode: 18, layout: NagaKeyboardLayout()))
        XCTAssertFalse(NagaBluetoothReportDecoder.handles(keyCode: 0, layout: NagaKeyboardLayout()))
        XCTAssertFalse(NagaBluetoothReportDecoder.handles(keyCode: 36, layout: NagaKeyboardLayout()))
        let macro = NagaKeyboardLayout(sequences: [NagaKeySequence(button: 109, keyCodes: [29, 36])])
        XCTAssertTrue(NagaBluetoothReportDecoder.handles(keyCode: 36, layout: macro))
    }
    func testPostedPassthroughKeysAreReleasedExactlyOnceOnStopOrDisconnect() {
        var tracker = NagaPostedKeyTracker()
        tracker.posted(keyCode: 29, phase: .down); tracker.posted(keyCode: 29, phase: .down)
        tracker.posted(keyCode: 27, phase: .down); tracker.posted(keyCode: 29, phase: .up)
        XCTAssertEqual(tracker.takeReleases(), [27]); XCTAssertTrue(tracker.takeReleases().isEmpty)
        tracker.posted(keyCode: 29, phase: .down); tracker.posted(keyCode: 29, phase: .up)
        XCTAssertTrue(tracker.takeReleases().isEmpty)
    }
}
