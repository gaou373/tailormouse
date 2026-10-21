import XCTest
@testable import TailorMouseCore

final class ShortcutModifierInheritanceTests: XCTestCase {
    func testHeldCommandCombinesWithPlainBackspaceChordOnEveryClick() {
        let backspace = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 51))
        let profile = MouseProfile(chords: [ChordBinding(buttons: [100, 0], binding: backspace)])
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: profile)
        for _ in 0..<3 {
            let output = router.route(button: 0, phase: .down, profile: profile, modifiers: .command).emissions
            XCTAssertEqual(output.count, 1)
            XCTAssertEqual(output.first?.binding.shortcut, Shortcut(keyCode: 51, modifiers: .command))
            XCTAssertEqual(output.first?.binding.shortcut?.edges.map(\.phase), [.down, .up])
            XCTAssertTrue(router.route(button: 0, phase: .up, profile: profile).emissions.isEmpty)
        }
        XCTAssertEqual(router.route(button: 0, phase: .down, profile: profile).emissions.first?.binding, backspace)
        _ = router.route(button: 0, phase: .up, profile: profile)
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: profile).emissions.isEmpty)
    }

    func testExplicitModifierButtonVariantConsumesItsSelectorAndKeepsAssignedOutput() {
        let normal = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 37))
        let option = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 31))
        let profile = MouseProfile(bindings: ["101": normal], modifierBindings: ["101:4": option])
        var router = InputRouter()
        XCTAssertEqual(router.route(button: 101, phase: .down, profile: profile, modifiers: .option).emissions.first?.binding, option)
        _ = router.route(button: 101, phase: .up, profile: profile)
        XCTAssertEqual(router.route(button: 101, phase: .down, profile: profile, modifiers: .command).emissions.first?.binding.shortcut,
                       Shortcut(keyCode: 37, modifiers: .command))
        XCTAssertEqual(profile.bindings["101"], normal)
    }

    func testExplicitChordVariantConsumesSelectorButBaseChordKeepsKeyboardModifiers() {
        let normal = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 51))
        let variant = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 31, modifiers: .shift))
        let p = MouseProfile(chords: [ChordBinding(buttons: [100,0], binding: normal),
            ChordBinding(buttons: [100,0], modifiers: .option, binding: variant)])
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: p)
        for modifiers in [ModifierMask.option, .command, []] {
            let result = router.route(button: 0, phase: .down, profile: p, modifiers: modifiers)
            XCTAssertEqual(result.emissions.first?.binding.shortcut,
                modifiers == .option ? variant.shortcut : Shortcut(keyCode: 51, modifiers: modifiers))
            _ = router.route(button: 0, phase: .up, profile: p)
        }
    }

    func testEveryHeldModifierCombinesWithConfiguredShortcutWithoutMutatingSavedBinding() {
        let saved = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 51, modifiers: .shift))
        for raw in UInt(0)...15 {
            let modifiers = ModifierMask(rawValue: raw)
            let p = MouseProfile(bindings: ["100": saved])
            let output = p.outputBinding(for: 100, modifiers: modifiers)
            XCTAssertEqual(output.shortcut, Shortcut(keyCode: 51, modifiers: modifiers.union(.shift)))
            XCTAssertEqual(p.actionBinding(for: 100, modifiers: modifiers), saved)
        }
    }

    func testHeldChordKeepsMatchedModifierSnapshotThroughRepeatsAndStop() {
        let binding = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 51), shortcutBehavior: .repeatWhileHeld)
        let p = MouseProfile(chords: [ChordBinding(buttons: [100,0], binding: binding)])
        var router = InputRouter(), output = HeldShortcuts()
        let owner = ShortcutHoldOwner(source: "USB", button: 0)
        _ = router.route(button: 100, phase: .down, profile: p)
        let down = router.route(button: 0, phase: .down, profile: p, modifiers: .command).emissions[0]
        let shortcut = down.binding.heldShortcut!
        XCTAssertEqual(shortcut, Shortcut(keyCode: 51, modifiers: .command))
        XCTAssertEqual(output.press(owner: owner, shortcut: shortcut, repeating: true, now: 0, delay: 0.2, interval: 0.05).map(\.edge.modifiers), [.command])
        XCTAssertEqual(output.repeats(now: 0.3).map(\.edge.modifiers), [.command])
        // Command may be released, and the profile changed, before the mouse.
        let release = router.route(button: 100, phase: .up, profile: MouseProfile()).emissions
        XCTAssertEqual(release, [InputEmission(button: 0, binding: down.binding, phase: .up)])
        XCTAssertEqual(output.release(owner: owner).map(\.edge.modifiers), [.command])
        XCTAssertTrue(router.reset().isEmpty); XCTAssertTrue(output.releaseAll().isEmpty)
        _ = router.route(button: 100, phase: .down, profile: p)
        _ = router.route(button: 0, phase: .down, profile: p, modifiers: .command)
        XCTAssertEqual(router.reset().map(\.binding.shortcut), [Shortcut(keyCode: 51, modifiers: .command)])
        XCTAssertTrue(router.reset().isEmpty)
    }

    func testDeferredSingleRetainsPressTimeModifiersAfterKeyboardRelease() {
        let binding = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 51))
        let p = MouseProfile(bindings: ["100": binding], chords: [ChordBinding(buttons: [100,0], binding: ActionBinding(action: .copy))])
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: p, modifiers: .command)
        let replay = router.route(button: 100, phase: .up, profile: MouseProfile()).emissions
        XCTAssertEqual(replay.first?.binding.shortcut, Shortcut(keyCode: 51, modifiers: .command))
        XCTAssertEqual(replay.first?.phase, .complete)
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: p).emissions.isEmpty)
    }

    func testWheelAndScrollChordUseSameModifierConsumptionPolicy() {
        let key = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 51))
        for direction in WheelDirection.allCases {
            var p = MouseProfile(wheelBindings: [direction.rawValue: key], chords: [ChordBinding(buttons: [100,direction.chordInput], binding: key)])
            var deltas: [Int64] = [0,0]; deltas[direction.axis] = Int64(direction.sign)
            XCTAssertEqual(WheelActionRouter.route(deltas: deltas, continuous: false, profile: p, modifiers: .command).first?.binding.shortcut,
                           Shortcut(keyCode: 51, modifiers: .command))
            p.wheelBindings["\(direction.rawValue):1"] = key
            XCTAssertEqual(WheelActionRouter.route(deltas: deltas, continuous: false, profile: p, modifiers: .command).first?.binding, key)
            var router = InputRouter()
            _ = router.route(button: 100, phase: .down, profile: p)
            XCTAssertEqual(router.routeScroll(direction: direction, modifiers: .command).emissions.first?.binding.shortcut,
                           Shortcut(keyCode: 51, modifiers: .command))
            XCTAssertTrue(router.route(button: 100, phase: .up, profile: p).emissions.isEmpty)
        }
    }

    func testNativeAndFixedSystemActionsDoNotChangeAndExplicitCommandShortcutStaysCommand() {
        let p = MouseProfile(bindings: ["100": ActionBinding(action: .copy), "101": ActionBinding(action: .passthrough),
            "102": ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 51, modifiers: .command))])
        XCTAssertEqual(p.outputBinding(for: 100, modifiers: .option), p.actionBinding(for: 100))
        XCTAssertEqual(p.outputBinding(for: 101, modifiers: .command), p.actionBinding(for: 101))
        XCTAssertEqual(p.outputBinding(for: 102, modifiers: .command).shortcut, Shortcut(keyCode: 51, modifiers: .command))
    }
}
