import XCTest
@testable import TailorMouseCore

final class ModifierKeyTests: XCTestCase {
    private let command = ActionBinding(action: .modifierKey, modifierKey: .command)
    private let side = ShortcutHoldOwner(source: "USB", button: 100)
    private func press(_ engine: inout HeldShortcuts, owner: ShortcutHoldOwner, key: ModifierKey) -> [HeldShortcutEvent] {
        engine.press(owner: owner, shortcut: key.shortcut, repeating: true, now: 0, delay: 0.2, interval: 0.05)
    }

    func testModifierOnlyBindingHasNoLetterAndRoundTripsWithoutChangingLegacyShortcut() throws {
        XCTAssertNil(command.shortcut)
        XCTAssertEqual(command.heldShortcut, ModifierKey.command.shortcut)
        XCTAssertEqual(try JSONDecoder().decode(ActionBinding.self, from: JSONEncoder().encode(command)), command)
        let legacy = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 0))
        XCTAssertEqual(try JSONDecoder().decode(ActionBinding.self, from: JSONEncoder().encode(legacy)), legacy)
        XCTAssertNil(legacy.modifierKey)
        XCTAssertEqual(ActionCategory.category(for: .modifierKey), .modifierKey)
        XCTAssertNil(ActionBinding(action: .modifierKey).heldShortcut)
    }

    func testEachModifierUsesOnlyItsOwnKeyAndNeverRepeats() {
        for key in ModifierKey.allCases {
            var engine = HeldShortcuts()
            let down = press(&engine, owner: side, key: key)
            XCTAssertEqual(down.map(\.edge.keyCode), [key.keyCode])
            XCTAssertEqual(down.map(\.edge.phase), [.down])
            XCTAssertEqual(down.map(\.edge.modifiers), [key.mask])
            XCTAssertEqual(engine.heldModifiers, key.mask)
            XCTAssertTrue(engine.repeats(now: 100).isEmpty)
            XCTAssertNil(engine.nextDeadline)
            let up = engine.release(owner: side)
            XCTAssertEqual(up.map(\.edge.keyCode), [key.keyCode])
            XCTAssertEqual(up.map(\.edge.phase), [.up])
            XCTAssertEqual(up.map(\.edge.modifiers), [[]])
            XCTAssertTrue(engine.heldModifiers.isEmpty)
            XCTAssertTrue(engine.release(owner: side).isEmpty)
        }
    }

    func testModifierStartsImmediatelyEvenWhenButtonIsAChordAnchor() {
        let p = MouseProfile(bindings: ["100": command], chords: [ChordBinding(buttons: [100,0], binding: ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 51)))])
        var router = InputRouter()
        XCTAssertEqual(router.route(button: 100, phase: .down, profile: p).emissions, [InputEmission(button: 100, binding: command, phase: .down)])
        XCTAssertTrue(router.route(button: 100, phase: .down, profile: p).emissions.isEmpty)
        for _ in 0..<3 {
            let chord = router.route(button: 0, phase: .down, profile: p, modifiers: .command)
            XCTAssertEqual(chord.emissions.count, 1)
            XCTAssertEqual(chord.emissions[0].binding.shortcut, Shortcut(keyCode: 51, modifiers: .command))
            XCTAssertEqual(chord.emissions[0].phase, .complete)
            XCTAssertTrue(router.route(button: 0, phase: .up, profile: p).emissions.isEmpty)
        }
        XCTAssertEqual(router.route(button: 100, phase: .up, profile: MouseProfile()).emissions,
                       [InputEmission(button: 100, binding: command, phase: .up)])
        XCTAssertTrue(router.reset().isEmpty)
    }

    func testChordModifierOutputReleasesOnEitherMemberAndOnStop() {
        let p = MouseProfile(chords: [ChordBinding(buttons: [100,101], binding: command)])
        for released in [100,101] {
            var router = InputRouter()
            _ = router.route(button: 100, phase: .down, profile: p)
            XCTAssertEqual(router.route(button: 101, phase: .down, profile: p).emissions, [InputEmission(button: 101, binding: command, phase: .down)])
            XCTAssertEqual(router.route(button: released, phase: .up, profile: MouseProfile()).emissions, [InputEmission(button: 101, binding: command, phase: .up)])
            XCTAssertTrue(router.reset().isEmpty)
        }
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: p)
        _ = router.route(button: 101, phase: .down, profile: p)
        XCTAssertEqual(router.reset(), [InputEmission(button: 101, binding: command, phase: .up)])
        XCTAssertTrue(router.reset().isEmpty)
    }

    func testTwoOwnersOfCommandReleaseOnlyAfterLastOwnerAndDisconnectIsScoped() {
        var engine = HeldShortcuts()
        let receiver = ShortcutHoldOwner(source: "receiver", button: 100)
        XCTAssertEqual(press(&engine, owner: side, key: .command).count, 1)
        XCTAssertTrue(press(&engine, owner: receiver, key: .command).isEmpty)
        XCTAssertTrue(engine.release(source: "USB").isEmpty)
        XCTAssertEqual(engine.heldModifiers, .command)
        XCTAssertEqual(engine.release(source: "receiver").map(\.edge.phase), [.up])
        XCTAssertTrue(engine.heldModifiers.isEmpty)
        XCTAssertTrue(engine.releaseAll().isEmpty)
    }

    func testDifferentModifierOwnersHaveCumulativeFlagsAndMatchedRecovery() {
        var engine = HeldShortcuts()
        let other = ShortcutHoldOwner(source: "Bluetooth", button: 101)
        XCTAssertEqual(press(&engine, owner: side, key: .command).map(\.edge.modifiers), [.command])
        XCTAssertEqual(press(&engine, owner: other, key: .shift).map(\.edge.modifiers), [[.command,.shift]])
        XCTAssertEqual(engine.release(owner: side).map(\.edge.modifiers), [.shift])
        XCTAssertEqual(engine.releaseAll().map(\.edge.modifiers), [[]])
        XCTAssertTrue(engine.heldModifiers.isEmpty)
    }

    func testPhysicalKeyboardModifierIsNotReleasedOrOverwritten() {
        var engine = HeldShortcuts()
        let down = press(&engine, owner: side, key: .command)[0]
        XCTAssertNil(down.modifierOutputFlags(physical: .command))
        XCTAssertEqual(down.modifierOutputFlags(physical: .shift), [.shift,.command])
        let up = engine.release(owner: side)[0]
        XCTAssertNil(up.modifierOutputFlags(physical: .command))
        XCTAssertEqual(up.modifierOutputFlags(physical: .shift), .shift)
        XCTAssertEqual(up.modifierOutputFlags(physical: []), [])
    }

    func testPressTimeModifierIdentitySurvivesProfileEditAndReset() {
        var p = MouseProfile(bindings: ["100": command])
        var router = InputRouter()
        _ = router.route(button: 100, phase: .down, profile: p)
        p.bindings["100"] = ActionBinding(action: .modifierKey, modifierKey: .option)
        XCTAssertEqual(router.route(button: 100, phase: .up, profile: p).emissions, [InputEmission(button: 100, binding: command, phase: .up)])
        _ = router.route(button: 100, phase: .down, profile: p)
        XCTAssertEqual(router.reset().first?.binding.modifierKey, .option)
        XCTAssertTrue(router.reset().isEmpty)
        XCTAssertTrue(router.route(button: 100, phase: .up, profile: p).emissions.isEmpty)
    }

    func testScrollModifierOutputIsACompleteTapWithNoHeldCandidate() {
        let p = MouseProfile(chords: [ChordBinding(buttons: [101,200], binding: command)])
        var router = InputRouter()
        _ = router.route(button: 101, phase: .down, profile: p)
        XCTAssertEqual(router.routeScroll(direction: .up).emissions, [InputEmission(button: 200, binding: command)])
        XCTAssertTrue(router.route(button: 101, phase: .up, profile: p).emissions.isEmpty)
        XCTAssertTrue(router.reset().isEmpty)
    }

    func testAllNagaTransportsProduceMatchedCommandOnlyHolds() {
        for product in [0x008f,0x0090,0x0092] {
            let identity = DeviceIdentity(vendorID: 0x1532, productID: product, transport: product == 0x0092 ? "Bluetooth" : "USB", product: "")
            let format = NagaKeyboardReportFormat(identity: identity)!
            let down: [UInt8] = product == 0x0092 ? [6,0,0x1e,0,0,0,0,0] : [0,0,0x1e,0,0,0,0,0]
            let up: [UInt8] = product == 0x0092 ? [6,0,0,0,0,0,0,0] : Array(repeating: 0, count: 8)
            var raw = NagaBluetoothReportDecoder(), decoder = NagaKeyboardDecoder(), router = InputRouter()
            var token: UInt64 = 0
            var output: [InputEmission] = []
            let p = MouseProfile(bindings: ["100": command])
            for bytes in [down,down,up] {
                for edge in raw.route(reportID: 6, bytes: format.canonical(reportID: format.reportID, bytes: bytes)!) {
                    token += 1
                    for input in decoder.route(NagaKeyboardInput(token: token, keyCode: edge.keyCode, phase: edge.phase, modifiers: edge.modifiers, profile: p), now: Double(token), layout: NagaKeyboardLayout()).dispatches {
                        output += router.route(button: input.button, phase: input.phase, profile: input.profile).emissions
                    }
                }
            }
            XCTAssertEqual(output, [InputEmission(button: 100, binding: command, phase: .down), InputEmission(button: 100, binding: command, phase: .up)])
            XCTAssertEqual(output.compactMap { $0.binding.heldShortcut?.keyCode }, [55,55])
        }
    }
}
