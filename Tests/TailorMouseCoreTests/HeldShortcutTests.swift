import XCTest
@testable import TailorMouseCore

final class HeldShortcutTests: XCTestCase {
    private let c = Shortcut(keyCode: 8)
    private let owner = ShortcutHoldOwner(source: "receiver", button: 102)
    private var binding: ActionBinding { ActionBinding(action: .shortcut, shortcut: c, shortcutBehavior: .repeatWhileHeld) }

    func testLegacyShortcutsStayTapsAndNewBehaviorsRoundTrip() throws {
        let legacy = Data(#"{"action":"shortcut","shortcut":{"keyCode":8,"modifiers":0},"mouseButton":0,"scrollX":0,"scrollY":3}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ActionBinding.self, from: legacy).heldShortcut)
        for behavior in ShortcutBehavior.allCases {
            let value = ActionBinding(action: .shortcut, shortcut: c, shortcutBehavior: behavior)
            XCTAssertEqual(try JSONDecoder().decode(ActionBinding.self, from: JSONEncoder().encode(value)), value)
        }
    }

    func testButtonHoldSnapshotsMappingAndEmitsOnlyMatchedDownUp() {
        var router = InputRouter()
        let profile = MouseProfile(bindings: ["102": binding])
        let down = router.route(button: 102, phase: .down, profile: profile)
        XCTAssertEqual(down.emissions, [InputEmission(button: 102, binding: binding, phase: .down)])
        let changed = MouseProfile(bindings: ["102": ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 2))])
        XCTAssertTrue(router.route(button: 102, phase: .down, profile: changed).emissions.isEmpty)
        XCTAssertTrue(router.route(button: 102, phase: .drag, profile: changed).emissions.isEmpty)
        let up = router.route(button: 102, phase: .up, profile: changed, modifiers: .command)
        XCTAssertTrue(up.suppress)
        XCTAssertEqual(up.emissions, [InputEmission(button: 102, binding: binding, phase: .up)])
        XCTAssertTrue(router.route(button: 102, phase: .up, profile: profile).emissions.isEmpty)
    }

    func testKeyboardStyleRepeatsAreDownsWithOneFinalRelease() {
        var output = HeldShortcuts()
        let down = output.press(owner: owner, shortcut: c, repeating: true, now: 0, delay: 0.5, interval: 0.05)
        XCTAssertEqual(down.map(\.edge.phase), [.down]); XCTAssertFalse(down[0].isRepeat)
        XCTAssertTrue(output.repeats(now: 0.49).isEmpty)
        let repeatDown = output.repeats(now: 0.5)
        XCTAssertEqual(repeatDown.map(\.edge.phase), [.down]); XCTAssertTrue(repeatDown[0].isRepeat)
        XCTAssertTrue(output.repeats(now: 0.51).isEmpty)
        // A late timer emits one repeat, not all ticks missed while blocked.
        XCTAssertEqual(output.repeats(now: 10).count, 1)
        let up = output.release(owner: owner)
        XCTAssertEqual(up.map(\.edge.phase), [.up]); XCTAssertFalse(up[0].isRepeat)
        XCTAssertNil(output.nextDeadline)
        XCTAssertTrue(output.repeats(now: 100).isEmpty); XCTAssertTrue(output.release(owner: owner).isEmpty)
    }

    func testHoldWithoutRepeatAndDuplicatePhysicalDownDoNotRepeat() {
        var output = HeldShortcuts()
        XCTAssertEqual(output.press(owner: owner, shortcut: c, repeating: false, now: 0, delay: 0.5, interval: 0.05).count, 1)
        XCTAssertTrue(output.press(owner: owner, shortcut: Shortcut(keyCode: 2), repeating: true, now: 1, delay: 0, interval: 0.01).isEmpty)
        XCTAssertTrue(output.repeats(now: 20).isEmpty)
        XCTAssertEqual(output.release(owner: owner).map(\.edge.keyCode), [8])
    }

    func testStopAndDisconnectReleaseExactlyOnceAndAllowFreshPress() {
        var output = HeldShortcuts()
        let bluetooth = ShortcutHoldOwner(source: "bluetooth", button: 102)
        _ = output.press(owner: owner, shortcut: c, repeating: true, now: 0, delay: 0.5, interval: 0.05)
        _ = output.press(owner: bluetooth, shortcut: Shortcut(keyCode: 2), repeating: true, now: 0, delay: 0.5, interval: 0.05)
        XCTAssertEqual(output.release(source: "receiver").map(\.edge.keyCode), [8])
        XCTAssertTrue(output.release(source: "receiver").isEmpty)
        XCTAssertEqual(output.repeats(now: 1).map(\.edge.keyCode), [2])
        XCTAssertEqual(output.releaseAll().map(\.edge.keyCode), [2]); XCTAssertTrue(output.releaseAll().isEmpty)
        XCTAssertTrue(output.repeats(now: 100).isEmpty)
        XCTAssertEqual(output.press(owner: owner, shortcut: c, repeating: true, now: 101, delay: 0.5, interval: 0.05).count, 1)
    }

    func testTwoSourcesHoldingSameKeyDoNotReleaseEachOtherOrDoubleRepeat() {
        var output = HeldShortcuts()
        let other = ShortcutHoldOwner(source: "bluetooth", button: 102)
        XCTAssertEqual(output.press(owner: owner, shortcut: c, repeating: true, now: 0, delay: 0.5, interval: 0.05).count, 1)
        XCTAssertTrue(output.press(owner: other, shortcut: c, repeating: true, now: 0, delay: 0.5, interval: 0.05).isEmpty)
        XCTAssertEqual(output.repeats(now: 1).count, 1)
        XCTAssertTrue(output.release(owner: other).isEmpty)
        XCTAssertEqual(output.repeats(now: 2).count, 1)
        XCTAssertEqual(output.release(owner: owner).map(\.edge.phase), [.up])
    }

    func testHeldChordReleasesOnEitherMemberAndUsesItsOriginalBinding() {
        for released in [100, 101] {
            var router = InputRouter()
            let profile = MouseProfile(chords: [ChordBinding(buttons: [100,101], binding: binding)])
            XCTAssertTrue(router.route(button: 100, phase: .down, profile: profile).emissions.isEmpty)
            XCTAssertEqual(router.route(button: 101, phase: .down, profile: profile).emissions,
                [InputEmission(button: 101, binding: binding, phase: .down)])
            XCTAssertEqual(router.route(button: released, phase: .up, profile: MouseProfile()).emissions,
                [InputEmission(button: 101, binding: binding, phase: .up)])
            XCTAssertTrue(router.route(button: released == 100 ? 101 : 100, phase: .up, profile: profile).emissions.isEmpty)
        }
    }

    func testPendingChordSingleReplaysTapAfterReleaseButHoldsAfterMismatch() {
        var router = InputRouter()
        let profile = MouseProfile(bindings: ["102": binding], chords: [ChordBinding(buttons: [102,103], binding: ActionBinding(action: .copy))])
        _ = router.route(button: 102, phase: .down, profile: profile)
        XCTAssertEqual(router.route(button: 102, phase: .up, profile: profile).emissions,
            [InputEmission(button: 102, binding: binding)])
        _ = router.route(button: 102, phase: .down, profile: profile)
        XCTAssertEqual(router.route(button: 0, phase: .down, profile: profile).emissions,
            [InputEmission(button: 102, binding: binding, phase: .down)])
        XCTAssertEqual(router.reset(), [InputEmission(button: 102, binding: binding, phase: .up)])
        XCTAssertTrue(router.reset().isEmpty)
        XCTAssertTrue(router.route(button: 102, phase: .up, profile: profile).emissions.isEmpty)
    }

    func testBluetoothRawSnapshotAndReceiverKeyboardProduceHeldCThroughSameRouter() {
        for bluetooth in [false, true] {
            var raw = NagaBluetoothReportDecoder(); var keyboard = NagaKeyboardDecoder(); var router = InputRouter()
            let profile = MouseProfile(bindings: ["102": binding])
            var phases: [InputEmissionPhase] = []
            for (index, phase) in [ButtonPhase.down, .up].enumerated() {
                let keys: [UInt16] = bluetooth ? raw.route(reportID: 6, bytes: phase == .down ? [6,0,0,0x20,0,0,0,0] : [6,0,0,0,0,0,0,0]).map(\.keyCode) : [20]
                for key in keys {
                    let result = keyboard.route(NagaKeyboardInput(token: UInt64(index + 1), keyCode: key,
                        phase: phase, modifiers: [], profile: profile), now: Double(index), layout: NagaKeyboardLayout())
                    for edge in result.dispatches {
                        phases += router.route(button: edge.button, phase: edge.phase, profile: edge.profile).emissions.map(\.phase)
                    }
                }
            }
            XCTAssertEqual(phases, [.down, .up])
        }
    }

    func testExtendedFunctionKeyModifiersAndInvalidRepeatSettingsStayPaired() {
        var output = HeldShortcuts()
        let key = Shortcut(keyCode: 127, modifiers: [.option, .shift], functionKey: 24)
        let down = output.press(owner: owner, shortcut: key, repeating: true, now: 0, delay: .infinity, interval: 0)
        XCTAssertEqual(down[0].edge.unicode, 0xF71B); XCTAssertEqual(down[0].edge.modifiers, [.option, .shift])
        XCTAssertNil(output.nextDeadline)
        let up = output.releaseAll()
        XCTAssertEqual(up[0].edge.unicode, down[0].edge.unicode); XCTAssertEqual(up[0].edge.modifiers, down[0].edge.modifiers)
        XCTAssertEqual(up[0].edge.phase, .up)
    }
}
