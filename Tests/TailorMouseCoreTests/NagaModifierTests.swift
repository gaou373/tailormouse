import XCTest
@testable import TailorMouseCore

final class NagaModifierTests: XCTestCase {
    func testCapturedHardwareFlagClearsDoNotDropHeldKeyboardOption() {
        var state = NagaModifierState(); state.begin(snapshot: [])
        state.changed(.option)
        // The live capture alternated cleared/Option hardware state between
        // one real Option down and its later flagsChanged release.
        for hardware in [ModifierMask.option, [], [], .option, []] {
            XCTAssertEqual(state.resolve(event: [], hardware: hardware), .option)
        }
        state.changed([])
        XCTAssertEqual(state.resolve(event: [], hardware: []), [])
    }

    func testReleaseChangesAndRecoveryReplaceTheKeyboardSnapshot() {
        var state = NagaModifierState(); state.begin(snapshot: .command)
        XCTAssertEqual(state.resolve(event: [], hardware: []), .command)
        state.changed([.shift,.option])
        XCTAssertEqual(state.resolve(event: .control, hardware: .command), [.shift,.option,.control])
        state.changed(.shift)
        XCTAssertEqual(state.resolve(event: [], hardware: []), .shift)
        state.reset(); state.begin(snapshot: [])
        XCTAssertEqual(state.resolve(event: [], hardware: []), [])
    }

    func testStableOptionStateSelectsSameMappingForRepeatedReceiverPresses() {
        var state = NagaModifierState(); state.begin(snapshot: []); state.changed(.option)
        let normal = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 37))
        let option = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 31))
        let profile = MouseProfile(bindings: ["101": normal], modifierBindings: ["101:4": option])
        var decoder = NagaKeyboardDecoder(); var router = InputRouter(); var token: UInt64 = 0
        for hardware in [ModifierMask(), .option, [], .option, []] {
            for phase in [ButtonPhase.down,.up] {
                token += 1
                for edge in decoder.route(NagaKeyboardInput(token: token, keyCode: 19, phase: phase,
                    modifiers: state.resolve(event: [], hardware: hardware), profile: profile), now: Double(token), layout: NagaKeyboardLayout()).dispatches {
                    let result = router.route(button: edge.button, phase: edge.phase, profile: edge.profile, modifiers: edge.modifiers)
                    XCTAssertEqual(result.emissions.map(\.binding), phase == .down ? [option] : [])
                }
            }
        }
        state.changed([]); token += 1
        let edge = decoder.route(NagaKeyboardInput(token: token, keyCode: 19, phase: .down,
            modifiers: state.resolve(event: [], hardware: []), profile: profile), now: Double(token), layout: NagaKeyboardLayout()).dispatches[0]
        XCTAssertEqual(router.route(button: edge.button, phase: edge.phase, profile: edge.profile, modifiers: edge.modifiers).emissions.map(\.binding), [normal])
    }

    func testReceiverKeyWithoutFlagsUsesKeyboardOptionMappingAndRetainsReleaseSnapshot() {
        var profile = MouseProfile(bindings: ["101": ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 37))])
        let option = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 31), shortcutBehavior: .hold)
        profile.modifierBindings["101:4"] = option
        var decoder = NagaKeyboardDecoder(); var router = InputRouter()
        let modifiers = NagaModifiers.resolve(event: [], hardware: .option)
        let down = decoder.route(NagaKeyboardInput(token: 1, keyCode: 19, phase: .down, modifiers: modifiers, profile: profile),
            now: 0, layout: NagaKeyboardLayout()).dispatches[0]
        XCTAssertEqual(router.route(button: down.button, phase: down.phase, profile: down.profile, modifiers: down.modifiers).emissions,
            [InputEmission(button: 101, binding: option, phase: .down)])
        // The keyboard modifier can be released before the mouse button.
        let up = decoder.route(NagaKeyboardInput(token: 2, keyCode: 19, phase: .up, modifiers: [], profile: MouseProfile()),
            now: 1, layout: NagaKeyboardLayout()).dispatches[0]
        XCTAssertEqual(up.modifiers, .option)
        XCTAssertEqual(router.route(button: up.button, phase: up.phase, profile: up.profile, modifiers: up.modifiers).emissions,
            [InputEmission(button: 101, binding: option, phase: .up)])
    }

    func testAllKeyboardModifierCombinationsSelectTheirOwnReceiverMapping() {
        for mask in UInt(0)...15 {
            let modifiers = ModifierMask(rawValue: mask)
            let mapped = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: UInt16(mask)))
            let profile = MouseProfile(modifierBindings: ["101:\(mask)": mapped])
            var decoder = NagaKeyboardDecoder(); var router = InputRouter()
            for (index, phase) in [ButtonPhase.down, .up].enumerated() {
                let flags = NagaModifiers.resolve(event: [], hardware: modifiers)
                for edge in decoder.route(NagaKeyboardInput(token: UInt64(index + 1), keyCode: 19, phase: phase, modifiers: flags, profile: profile),
                    now: Double(index), layout: NagaKeyboardLayout()).dispatches {
                    let result = router.route(button: edge.button, phase: edge.phase, profile: edge.profile, modifiers: edge.modifiers)
                    XCTAssertTrue(result.suppress)
                    XCTAssertEqual(result.emissions.map(\.binding), phase == .down ? [mapped] : [])
                }
            }
        }
    }

    func testOnboardAndExternalModifiersCombineWithoutInventingOtherModifiers() {
        XCTAssertEqual(NagaModifiers.resolve(event: .shift, hardware: .option), [.shift, .option])
        XCTAssertEqual(NagaModifiers.resolve(event: .command, hardware: .command), .command)
        XCTAssertEqual(NagaModifiers.resolve(event: [], hardware: []), [])
    }

    func testModifierChordUsesReceiverSnapshotOnEachRearmedSecondPress() {
        let chord = ChordBinding(buttons: [100,101], modifiers: .option, binding: ActionBinding(action: .copy))
        let profile = MouseProfile(chords: [chord])
        var decoder = NagaKeyboardDecoder(); var router = InputRouter(); var actions: [ButtonAction] = []
        var token: UInt64 = 0
        for (key, phase) in [(UInt16(18), ButtonPhase.down), (19,.down), (19,.up), (19,.down), (19,.up), (18,.up)] {
            token += 1
            for edge in decoder.route(NagaKeyboardInput(token: token, keyCode: key, phase: phase,
                modifiers: NagaModifiers.resolve(event: [], hardware: .option), profile: profile), now: Double(token), layout: NagaKeyboardLayout()).dispatches {
                actions += router.route(button: edge.button, phase: edge.phase, profile: edge.profile, modifiers: edge.modifiers).emissions.map(\.binding.action)
            }
        }
        XCTAssertEqual(actions, [.copy,.copy])
    }

    func testNativeSecondButtonAndWheelUseSameKeyboardModifierSelection() {
        let flags = NagaModifiers.resolve(event: [], hardware: .option)
        var profile = MouseProfile(chords: [ChordBinding(buttons: [100,0], modifiers: .option, binding: ActionBinding(action: .copy))])
        profile.wheelBindings["up:4"] = ActionBinding(action: .paste)
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: profile, modifiers: flags)
        for _ in 0..<3 {
            XCTAssertEqual(router.route(button: 0, phase: .down, profile: profile, modifiers: flags).emissions.map(\.binding.action), [.copy])
            XCTAssertTrue(router.route(button: 0, phase: .up, profile: profile).suppress)
        }
        XCTAssertEqual(WheelActionRouter.route(deltas: [1,0], continuous: false, profile: profile, modifiers: flags).map(\.binding.action), [.paste])
    }
}
