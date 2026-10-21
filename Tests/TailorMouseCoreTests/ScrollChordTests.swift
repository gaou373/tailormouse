import XCTest
@testable import TailorMouseCore

final class ScrollChordTests: XCTestCase {
    private let copy = ActionBinding(action: .copy)
    private func profile(_ direction: WheelDirection, button: Int = 100, binding: ActionBinding? = nil) -> MouseProfile {
        MouseProfile(chords: [ChordBinding(buttons: [button, direction.chordInput], binding: binding ?? copy)])
    }

    func testEveryDirectionRepeatsUntilAnchorReleaseAndDoesNotReplaySingleAction() {
        for direction in WheelDirection.allCases {
            var router = InputRouter()
            let p = profile(direction)
            XCTAssertTrue(router.routeScroll(direction: direction).emissions.isEmpty)
            XCTAssertTrue(router.route(button: 100, phase: .down, profile: p).emissions.isEmpty)
            for _ in 0..<10 {
                XCTAssertEqual(router.routeScroll(direction: direction), RoutingDecision(suppress: true,
                    emissions: [InputEmission(button: direction.chordInput, binding: copy)]))
            }
            XCTAssertEqual(router.route(button: 100, phase: .up, profile: p), RoutingDecision(suppress: true))
            XCTAssertEqual(router.routeScroll(direction: direction), RoutingDecision(suppress: false))
            XCTAssertTrue(router.reset().isEmpty)
        }
    }

    func testUnassignedAxisOrOppositeDirectionDoesNotConsumeOrCancelCandidate() {
        var router = InputRouter()
        let p = profile(.up)
        _ = router.route(button: 100, phase: .down, profile: p)
        for direction in [WheelDirection.down, .left, .right] {
            XCTAssertEqual(router.routeScroll(direction: direction), RoutingDecision(suppress: false))
        }
        XCTAssertEqual(router.routeScroll(direction: .up).emissions.map(\.binding), [copy])
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: p).emissions.isEmpty)
    }

    func testHeldPrimaryKeepsNativeClickDragAndRelease() {
        for button in 0...2 {
            var router = InputRouter()
            let p = profile(.left, button: button)
            XCTAssertFalse(router.route(button: button, phase: .down, profile: p).suppress)
            for _ in 0..<3 { XCTAssertEqual(router.routeScroll(direction: .left).emissions.map(\.binding), [copy]) }
            XCTAssertFalse(router.route(button: button, phase: .drag, profile: p).suppress)
            XCTAssertEqual(router.route(button: button, phase: .up, profile: p), RoutingDecision(suppress: false))
        }
    }

    func testModifierVariantAndMappingSnapshotSurviveApplicationChange() {
        var p = profile(.right)
        let option = ActionBinding(action: .paste)
        p.chords.append(ChordBinding(buttons: [100, WheelDirection.right.chordInput], modifiers: .option, binding: option))
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: p)
        p.chords.removeAll()
        for modifiers in [ModifierMask(), .option, .command, []] {
            XCTAssertEqual(router.routeScroll(direction: .right, modifiers: modifiers).emissions.map(\.binding),
                           [modifiers == .option ? option : copy])
        }
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: p).emissions.isEmpty)
        _ = router.route(button: 100, phase: .down, profile: p)
        XCTAssertFalse(router.routeScroll(direction: .right).suppress)
    }

    func testModifierOnlyChordRequiresExactCurrentModifiers() {
        var p = profile(.down)
        p.chords[0].modifiers = .option
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: p)
        XCTAssertFalse(router.routeScroll(direction: .down).suppress)
        XCTAssertFalse(router.routeScroll(direction: .down, modifiers: [.option, .shift]).suppress)
        XCTAssertEqual(router.routeScroll(direction: .down, modifiers: .option).emissions.map(\.binding), [copy])
    }

    func testScrollShortcutCompletesEveryTickEvenWhenConfiguredForHoldOrRepeat() {
        for behavior in [ShortcutBehavior.hold, .repeatWhileHeld] {
            let binding = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 8), shortcutBehavior: behavior)
            var router = InputRouter()
            let p = profile(.up, binding: binding)
            _ = router.route(button: 100, phase: .down, profile: p)
            for _ in 0..<3 {
                XCTAssertEqual(router.routeScroll(direction: .up).emissions, [InputEmission(button: 200, binding: binding)])
            }
            XCTAssertTrue(router.reset().isEmpty)
            XCTAssertFalse(router.routeScroll(direction: .up).suppress)
            XCTAssertTrue(router.route(button: 100, phase: .up, profile: p).emissions.isEmpty)
        }
    }

    func testHeldSingleReleasedBeforeScrollChordAfterUnrelatedPressFlushesCandidate() {
        let held = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 8), shortcutBehavior: .hold)
        var p = profile(.up)
        p.bindings["100"] = held
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: p)
        XCTAssertEqual(router.route(button: 2, phase: .down, profile: p).emissions,
                       [InputEmission(button: 100, binding: held, phase: .down)])
        XCTAssertEqual(router.routeScroll(direction: .up).emissions,
                       [InputEmission(button: 100, binding: held, phase: .up), InputEmission(button: 200, binding: copy)])
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: p).emissions.isEmpty)
        XCTAssertTrue(router.reset().isEmpty)
    }

    func testUnmatchedAnchorReplaysSingleOnceAndResetDropsPendingCandidate() {
        var p = profile(.up)
        p.bindings["100"] = ActionBinding(action: .paste)
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: p)
        XCTAssertFalse(router.routeScroll(direction: .down).suppress)
        XCTAssertEqual(router.route(button: 100, phase: .up, profile: p).emissions.map(\.binding.action), [.paste])
        _ = router.route(button: 100, phase: .down, profile: p)
        XCTAssertTrue(router.reset().isEmpty)
        XCTAssertFalse(router.routeScroll(direction: .up).suppress)
    }

    func testMultipleHeldButtonsPreferMostSpecificScrollChordAndRemainReusable() {
        var p = profile(.up)
        p.chords.append(ChordBinding(buttons: [100, 101, 200], binding: ActionBinding(action: .paste)))
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: p)
        _ = router.route(button: 101, phase: .down, profile: p)
        for _ in 0..<3 { XCTAssertEqual(router.routeScroll(direction: .up).emissions.map(\.binding.action), [.paste]) }
        _ = router.route(button: 101, phase: .up, profile: p)
        XCTAssertEqual(router.routeScroll(direction: .up).emissions.map(\.binding), [copy])
        _ = router.route(button: 100, phase: .up, profile: p)
        XCTAssertFalse(router.routeScroll(direction: .up).suppress)
    }

    func testScrollChordConfigurationRoundTripAndInvalidCombinations() throws {
        for direction in WheelDirection.allCases {
            let p = profile(direction)
            let restored = try JSONDecoder().decode(ProfileConfiguration.self, from: JSONEncoder().encode(ProfileConfiguration(defaultProfile: p)))
            XCTAssertEqual(restored.defaultProfile, p)
            XCTAssertTrue(restored.defaultProfile.chords[0].isValid)
            XCTAssertEqual(ChordButtonChoices.title(direction.chordInput), "Scroll " + direction.rawValue.capitalized)
        }
        for buttons in [[200], [200, 201], [100, 200, 202], [100, 204], [100, 200, 200]] {
            XCTAssertFalse(ChordBinding(buttons: buttons, binding: copy).isValid)
        }
    }

    func testScrollRecordingIsScopedAndCannotReplaceUnfinishedButtonPress() {
        for direction in WheelDirection.allCases {
            var recorder = MouseButtonRecording()
            XCTAssertNil(recorder.scroll(direction: direction, source: "mouse"))
            recorder.begin()
            XCTAssertNil(recorder.scroll(direction: direction, source: ""))
            XCTAssertEqual(recorder.scroll(direction: direction, source: "mouse"), direction.chordInput)
            XCTAssertFalse(recorder.active)
            XCTAssertNil(recorder.scroll(direction: direction, source: "mouse"))
            recorder.begin()
            _ = recorder.route(button: 100, phase: .down, source: "mouse")
            XCTAssertNil(recorder.scroll(direction: direction, source: "mouse"))
            XCTAssertEqual(recorder.route(button: 100, phase: .up, source: "mouse"), 100)
            recorder.begin(); recorder.cancel()
            XCTAssertNil(recorder.scroll(direction: direction, source: "mouse"))
        }
    }

    func testConnectionStateIsIsolatedAndScrollCannotBecomeAPhysicalPress() {
        var wired = InputRouter(), receiver = InputRouter(), bluetooth = InputRouter()
        let p = profile(.up)
        _ = wired.route(button: 100, phase: .down, profile: p)
        XCTAssertTrue(wired.routeScroll(direction: .up).suppress)
        XCTAssertFalse(receiver.routeScroll(direction: .up).suppress)
        XCTAssertFalse(bluetooth.routeScroll(direction: .up).suppress)
        for phase in [ButtonPhase.down, .up, .drag] {
            XCTAssertFalse(wired.route(button: 200, phase: phase, profile: p).suppress)
        }
        wired.reset()
        XCTAssertFalse(wired.routeScroll(direction: .up).suppress)
    }
}
