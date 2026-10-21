import XCTest
@testable import TailorMouseCore

final class HeldChordTests: XCTestCase {
    private let copy = ActionBinding(action: .copy)

    func testHeldSideButtonCanTriggerLeftAndRightChordsRepeatedly() {
        let profile = MouseProfile(chords: [
            ChordBinding(buttons: [100,0], binding: copy),
            ChordBinding(buttons: [100,1], binding: ActionBinding(action: .paste))
        ])
        var router = InputRouter()
        XCTAssertTrue(router.route(button: 100, phase: .down, profile: profile).emissions.isEmpty)
        for button in [0,0,1,0,1] {
            let down = router.route(button: button, phase: .down, profile: profile)
            XCTAssertTrue(down.suppress)
            XCTAssertEqual(down.emissions.map(\.binding.action), [button == 0 ? .copy : .paste])
            XCTAssertTrue(router.route(button: button, phase: .down, profile: profile).emissions.isEmpty)
            XCTAssertTrue(router.route(button: button, phase: .drag, profile: profile).suppress)
            let up = router.route(button: button, phase: .up, profile: profile)
            XCTAssertTrue(up.suppress); XCTAssertTrue(up.emissions.isEmpty)
        }
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: profile).emissions.isEmpty)
        // With the anchor released, a main click remains native.
        XCTAssertFalse(router.route(button: 0, phase: .down, profile: profile).suppress)
        XCTAssertFalse(router.route(button: 0, phase: .up, profile: profile).suppress)
    }

    func testHeldNativePrimaryRetainsItsNativeReleaseAcrossRepeatedSidePresses() {
        let profile = MouseProfile(chords: [ChordBinding(buttons: [0,100], binding: copy)])
        var router = InputRouter()
        XCTAssertFalse(router.route(button: 0, phase: .down, profile: profile).suppress)
        for _ in 0..<3 {
            XCTAssertEqual(router.route(button: 100, phase: .down, profile: MouseProfile()).emissions.map(\.binding), [copy])
            XCTAssertTrue(router.route(button: 100, phase: .up, profile: MouseProfile()).suppress)
            XCTAssertFalse(router.route(button: 0, phase: .drag, profile: MouseProfile()).suppress)
        }
        let up = router.route(button: 0, phase: .up, profile: MouseProfile())
        XCTAssertFalse(up.suppress); XCTAssertTrue(up.emissions.isEmpty)
    }

    func testEitherHeldChordMemberCanRearmAfterOtherMemberIsReleased() {
        let profile = MouseProfile(chords: [ChordBinding(buttons: [100,101], binding: copy)])
        for anchor in [100,101] {
            let other = anchor == 100 ? 101 : 100
            var router = InputRouter()
            _ = router.route(button: anchor, phase: .down, profile: profile)
            for _ in 0..<3 {
                XCTAssertEqual(router.route(button: other, phase: .down, profile: profile).emissions.map(\.binding), [copy])
                XCTAssertTrue(router.route(button: other, phase: .up, profile: profile).emissions.isEmpty)
            }
            XCTAssertTrue(router.route(button: anchor, phase: .up, profile: profile).emissions.isEmpty)
        }
    }

    func testHeldShortcutChordReleasesAndStartsAgainOnEverySecondPress() {
        let held = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 8), shortcutBehavior: .repeatWhileHeld)
        let profile = MouseProfile(chords: [ChordBinding(buttons: [100,0], binding: held)])
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: profile)
        for _ in 0..<3 {
            XCTAssertEqual(router.route(button: 0, phase: .down, profile: profile).emissions,
                [InputEmission(button: 0, binding: held, phase: .down)])
            XCTAssertEqual(router.route(button: 0, phase: .up, profile: MouseProfile()).emissions,
                [InputEmission(button: 0, binding: held, phase: .up)])
        }
        _ = router.route(button: 0, phase: .down, profile: profile)
        XCTAssertEqual(router.route(button: 100, phase: .up, profile: profile).emissions,
            [InputEmission(button: 0, binding: held, phase: .up)])
        XCTAssertTrue(router.route(button: 0, phase: .up, profile: profile).emissions.isEmpty)
    }

    func testRearmedChordKeepsPressTimeProfileAndSelectsCurrentModifierVariant() {
        let profile = MouseProfile(chords: [ChordBinding(buttons: [100,0], binding: copy),
            ChordBinding(buttons: [100,0], modifiers: .option, binding: ActionBinding(action: .paste))])
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: profile)
        for modifiers in [ModifierMask(), .option, []] {
            let down = router.route(button: 0, phase: .down, profile: MouseProfile(), modifiers: modifiers)
            XCTAssertEqual(down.emissions.map(\.binding.action), [modifiers.isEmpty ? .copy : .paste])
            XCTAssertTrue(router.route(button: 0, phase: .up, profile: MouseProfile()).suppress)
        }
    }

    func testThreeButtonChordRetainsTwoHeldMembersAcrossRepeatedThirdPresses() {
        let profile = MouseProfile(chords: [ChordBinding(buttons: [100,101,0], binding: copy)])
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: profile)
        _ = router.route(button: 101, phase: .down, profile: profile)
        for _ in 0..<3 {
            XCTAssertEqual(router.route(button: 0, phase: .down, profile: profile).emissions.map(\.binding), [copy])
            XCTAssertTrue(router.route(button: 0, phase: .up, profile: profile).suppress)
        }
        XCTAssertTrue(router.route(button: 101, phase: .up, profile: profile).emissions.isEmpty)
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: profile).emissions.isEmpty)
    }

    func testResetDropsHeldAnchorAndDisconnectRequiresAFreshPress() {
        let profile = MouseProfile(chords: [ChordBinding(buttons: [100,0], binding: copy)])
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: profile)
        _ = router.route(button: 0, phase: .down, profile: profile)
        _ = router.route(button: 0, phase: .up, profile: profile)
        XCTAssertTrue(router.reset().isEmpty)
        XCTAssertTrue(router.route(button: 0, phase: .down, profile: profile).emissions.isEmpty)
        XCTAssertFalse(router.route(button: 0, phase: .up, profile: profile).suppress)
        XCTAssertFalse(router.route(button: 100, phase: .up, profile: profile).suppress)
    }
}
