import XCTest
@testable import TailorMouseCore

final class InputRouterTests: XCTestCase {
    func testUnassignedNagaButtonsConsumeMatchedPairsWithoutTypingAndKeepNativeClicks() {
        var router = InputRouter()
        let profile = MouseProfile()
        for button in 100...111 {
            let down = router.route(button: button, phase: .down, profile: profile)
            XCTAssertTrue(down.suppress)
            XCTAssertEqual(down.emissions.map { $0.binding.action }, [.disabled])
            XCTAssertTrue(router.route(button: button, phase: .down, profile: profile).emissions.isEmpty)
            var changed = profile
            changed.bindings[String(button)] = ActionBinding(action: .passthrough)
            XCTAssertTrue(router.route(button: button, phase: .up, profile: changed).suppress)
            XCTAssertFalse(router.route(button: button, phase: .up, profile: changed).suppress)
            XCTAssertFalse(router.route(button: button, phase: .down, profile: changed).suppress)
            XCTAssertFalse(router.route(button: button, phase: .up, profile: profile).suppress)
        }
        for button in 0...2 {
            XCTAssertFalse(router.route(button: button, phase: .down, profile: profile).suppress)
            XCTAssertFalse(router.route(button: button, phase: .up, profile: profile).suppress)
        }
        _ = router.route(button: 100, phase: .down, profile: profile)
        router.reset()
        XCTAssertFalse(router.route(button: 100, phase: .up, profile: profile).suppress)
        XCTAssertTrue(router.route(button: 100, phase: .down, profile: profile).suppress)
    }
    func testAllTwelveNagaButtonsAndBothKeyboardBanks() {
        let top: [UInt16] = [18,19,20,21,23,22,26,28,25,29,27,24]
        let pad: [UInt16] = [83,84,85,86,87,88,89,91,92,82,78,69]
        var router = InputRouter()
        var profile = MouseProfile()
        for i in 0..<12 { profile.bindings[String(100+i)] = ActionBinding(action: .copy) }
        for i in 0..<12 {
            XCTAssertEqual(NagaKeyMap.button(for: top[i]), 100+i)
            XCTAssertEqual(NagaKeyMap.button(for: pad[i]), 100+i)
            XCTAssertEqual(NagaKeyMap.keyCode(for: 100+i), top[i])
            XCTAssertEqual(router.route(button: 100+i, phase: .down, profile: profile).emissions.first?.binding.action, .copy)
            XCTAssertTrue(router.route(button: 100+i, phase: .up, profile: MouseProfile()).suppress)
        }
        XCTAssertNil(NagaKeyMap.button(for: 0))
        XCTAssertNil(NagaKeyMap.keyCode(for: 112))
    }
    func testMappingSnapshotsAndDuplicateDownAndDrag() {
        var router = InputRouter()
        var profile = MouseProfile(bindings: ["10": ActionBinding(action: .paste)])
        let down = router.route(button: 10, phase: .down, profile: profile)
        XCTAssertEqual(down.emissions.first?.binding.action, .paste)
        profile.bindings["10"] = ActionBinding(action: .passthrough)
        XCTAssertEqual(router.route(button: 10, phase: .down, profile: profile), RoutingDecision(suppress: true))
        XCTAssertEqual(router.route(button: 10, phase: .drag, profile: profile), RoutingDecision(suppress: true))
        XCTAssertEqual(router.route(button: 10, phase: .up, profile: profile), RoutingDecision(suppress: true))
        XCTAssertFalse(router.route(button: 10, phase: .up, profile: profile).suppress)
    }
    func testModifierExactThenFallback() {
        var profile = MouseProfile(bindings: ["100": ActionBinding(action: .copy)], modifierBindings: ["100:1": ActionBinding(action: .paste)])
        XCTAssertEqual(profile.actionBinding(for: 100, modifiers: .command).action, .paste)
        XCTAssertEqual(profile.actionBinding(for: 100, modifiers: .option).action, .copy)
        profile.modifierBindings["100:0"] = ActionBinding(action: .cut)
        XCTAssertEqual(profile.actionBinding(for: 100).action, .cut)
    }
    func testChordSnapshotsAndPairedRelease() {
        let chord = ChordBinding(buttons: [100,101], modifiers: .command, binding: ActionBinding(action: .undo))
        let profile = MouseProfile(bindings: ["100": ActionBinding(action: .copy)], chords: [chord])
        var router = InputRouter()
        XCTAssertEqual(router.route(button: 100, phase: .down, profile: profile, modifiers: .command), RoutingDecision(suppress: true))
        XCTAssertEqual(router.route(button: 100, phase: .drag, profile: MouseProfile()), RoutingDecision(suppress: true))
        let result = router.route(button: 101, phase: .down, profile: MouseProfile(), modifiers: .command)
        XCTAssertEqual(result.emissions.map { $0.binding.action }, [.undo])
        XCTAssertTrue(result.suppress)
        XCTAssertTrue(router.route(button: 101, phase: .up, profile: MouseProfile()).suppress)
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: MouseProfile()).suppress)
    }
    func testUnmatchedChordReplaysCapturedSingleAndSuppressesRelease() {
        var profile = MouseProfile(bindings: ["100": ActionBinding(action: .copy), "102": ActionBinding(action: .passthrough)], chords: [ChordBinding(buttons: [100,101], binding: ActionBinding(action: .undo))])
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: profile)
        profile.bindings["100"] = ActionBinding(action: .paste)
        XCTAssertEqual(router.route(button: 100, phase: .up, profile: profile).emissions.first?.binding.action, .copy)
        _ = router.route(button: 100, phase: .down, profile: profile)
        let mismatch = router.route(button: 102, phase: .down, profile: profile)
        XCTAssertFalse(mismatch.suppress)
        XCTAssertEqual(mismatch.emissions.map { $0.binding.action }, [.paste])
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: profile).suppress)
    }
    func testPassthroughPrefixReplaysCompleteClickAndInvalidPrimaryChordIgnored() {
        var router = InputRouter()
        let profile = MouseProfile(bindings: ["100": ActionBinding(action: .passthrough)], chords: [ChordBinding(buttons: [100,101], binding: ActionBinding(action: .copy)), ChordBinding(buttons: [0,3], binding: ActionBinding(action: .paste))])
        XCTAssertFalse(router.route(button: 0, phase: .down, profile: profile).suppress)
        XCTAssertFalse(router.route(button: 0, phase: .drag, profile: profile).suppress)
        XCTAssertFalse(router.route(button: 0, phase: .up, profile: profile).suppress)
        XCTAssertTrue(router.route(button: 100, phase: .down, profile: profile).suppress)
        let up = router.route(button: 100, phase: .up, profile: profile)
        XCTAssertTrue(up.suppress)
        XCTAssertEqual(up.emissions, [InputEmission(button: 100, binding: ActionBinding())])
    }
    func testThreeButtonPrefixReleaseFlushesRemainingSingles() {
        var router = InputRouter()
        let profile = MouseProfile(bindings: ["3": ActionBinding(action: .copy), "4": ActionBinding(action: .paste)], chords: [ChordBinding(buttons: [3,4,5], binding: ActionBinding(action: .undo))])
        XCTAssertTrue(router.route(button: 3, phase: .down, profile: profile).emissions.isEmpty)
        XCTAssertTrue(router.route(button: 4, phase: .down, profile: profile).emissions.isEmpty)
        XCTAssertEqual(router.route(button: 3, phase: .up, profile: profile).emissions.map { $0.binding.action }, [.copy,.paste])
        XCTAssertTrue(router.route(button: 4, phase: .up, profile: profile).emissions.isEmpty)
    }
    func testIndependentSourcesAndRecovery() {
        var mouseA = InputRouter(), mouseB = InputRouter()
        let mapped = MouseProfile(button3: .copy)
        XCTAssertTrue(mouseA.route(button: 3, phase: .down, profile: mapped).suppress)
        XCTAssertFalse(mouseB.route(button: 3, phase: .down, profile: MouseProfile()).suppress)
        XCTAssertFalse(mouseB.route(button: 3, phase: .up, profile: mapped).suppress)
        XCTAssertTrue(mouseA.route(button: 3, phase: .up, profile: MouseProfile()).suppress)
        _ = mouseA.route(button: 3, phase: .down, profile: mapped)
        mouseA.reset()
        XCTAssertFalse(mouseA.route(button: 3, phase: .up, profile: mapped).suppress)
        XCTAssertEqual(mouseA.route(button: 3, phase: .down, profile: mapped).emissions.count, 1)
        XCTAssertFalse(mouseA.route(button: -1, phase: .down, profile: mapped).suppress)
        XCTAssertFalse(mouseA.route(button: 112, phase: .down, profile: mapped).suppress)
    }
}
