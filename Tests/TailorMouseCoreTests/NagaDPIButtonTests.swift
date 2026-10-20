import XCTest
@testable import TailorMouseCore

final class NagaDPIButtonTests: XCTestCase {
    private let originals = [NagaDPIButtonBinding(slot: 9, block: [1,1,9,0,0,0,0]), NagaDPIButtonBinding(slot: 10, block: [1,1,10,0,0,0,0])]
    private var targets: [NagaDPIButtonBinding] { NagaDPIButtonBinding.legacyTargets }

    func testOnlyOriginalUSBAndReceiverCanEnablePhysicalAliases() {
        var config = ProfileConfiguration(); config.remapNagaDPIButtons = true
        for (product, transport, expected) in [(0x008f,"USB",true),(0x0090,"USB",true),(0x0092,"Bluetooth Low Energy",false),(0x00a8,"USB",false),(0x008f,"Bluetooth",false)] {
            let identity = DeviceIdentity(vendorID: 0x1532, productID: product, transport: transport, product: "Naga")
            XCTAssertEqual(config.nagaInputLayout(for: identity).button(for: 105), expected ? 112 : nil)
            XCTAssertEqual(config.nagaInputLayout(for: identity).button(for: 107), expected ? 113 : nil)
        }
        XCTAssertFalse(NagaDPIButton.supports(DeviceIdentity(vendorID: 1, productID: 0x008f, transport: "USB", product: "Other")))
    }
    func testOptInRoundTripsAndLegacyConfigurationsStayOff() throws {
        var config = ProfileConfiguration()
        XCTAssertFalse(config.remapNagaDPIButtons)
        config.defaultProfile.bindings["112"] = ActionBinding(action: .modifierKey, modifierKey: .command)
        config.remapNagaDPIButtons = true
        let encoded = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(ProfileConfiguration.self, from: encoded), config)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object.removeValue(forKey: "remapPhysicalNagaDPIButtons")
        object["remapNagaDPIButtons"] = true
        let legacy = try JSONDecoder().decode(ProfileConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(legacy.remapNagaDPIButtons)
        XCTAssertEqual(legacy.defaultProfile.bindings, config.defaultProfile.bindings)
    }
    func testRuntimeAliasesPreserveCalibrationAndDoNotRecognizeAnUnconfiguredFunctionKey() {
        let original = NagaKeyboardLayout(keyOverrides: ["29":109], sequences: [NagaKeySequence(button: 110, keyCodes: [18,19])])
        let active = original.includingDPIButtons(true)
        XCTAssertEqual(active.button(for: 29), 109)
        XCTAssertEqual(active.sequences, original.sequences)
        XCTAssertNil(original.button(for: 105))
        XCTAssertFalse(NagaBluetoothReportDecoder.handles(keyCode: 105, layout: original))
        XCTAssertTrue(NagaBluetoothReportDecoder.handles(keyCode: 105, layout: active))
        XCTAssertEqual(original.includingDPIButtons(false), original)
    }
    func testConflictingCalibrationIsRetainedRatherThanReinterpreted() {
        for layout in [NagaKeyboardLayout(keyOverrides: ["105":100]),
                       NagaKeyboardLayout(sequences: [NagaKeySequence(button: 110, keyCodes: [18,107])])] {
            XCTAssertTrue(layout.hasDPIButtonAliasConflict)
            XCTAssertEqual(layout.includingDPIButtons(true), layout)
        }
        XCTAssertFalse(NagaKeyboardLayout(keyOverrides: ["29":109]).hasDPIButtonAliasConflict)
    }
    func testDPIRecordingRequiresTheMatchingSourceAndRelease() {
        var recorder = MouseButtonRecording(); recorder.begin()
        XCTAssertNil(recorder.route(button: 112, phase: .down, source: "receiver"))
        XCTAssertNil(recorder.route(button: 112, phase: .up, source: "other"))
        XCTAssertEqual(recorder.route(button: 112, phase: .up, source: "receiver"), 112)
        XCTAssertFalse(recorder.active)
    }
    func testLiveNormalLayerFramingAndStrictBounds() throws {
        for target in originals {
            let read = try NagaDPIButtonProtocol.read(slot: target.slot)
            let write = try NagaDPIButtonProtocol.write(target)
            XCTAssertEqual(read.count, 90); XCTAssertEqual(write.count, 90)
            XCTAssertEqual(Array(write[5..<11]), [10,2,0x0c,0,target.slot,0])
            XCTAssertEqual(Array(write[11..<18]), target.block)
            XCTAssertEqual(read[7], 0x8c)
            XCTAssertEqual(write[88], NagaDPIButtonProtocol.checksum(write))
        }
        for slot: UInt8 in [0,1,8,13,0x40,0x60] {
            XCTAssertThrowsError(try NagaDPIButtonProtocol.read(slot: slot))
            XCTAssertThrowsError(try NagaDPIButtonProtocol.write(.init(slot: slot, block: [1,1,1,0,0,0,0])))
        }
        XCTAssertThrowsError(try NagaDPIButtonProtocol.write(.init(slot: 9, block: [])))
        XCTAssertThrowsError(try NagaDPIButtonProtocol.write(.init(slot: 9, block: [1,6,0,0,0,0,0])))
    }
    func testResponseEchoChecksumAndStoredLayerAreHandled() throws {
        var response = try NagaDPIButtonProtocol.write(originals[0])
        response[0] = 2; response[7] = 0x8c; response[10] = 1
        response[88] = NagaDPIButtonProtocol.checksum(response)
        XCTAssertEqual(try NagaDPIButtonProtocol.parse(response, slot: 9), originals[0])
        for (index, value): (Int, UInt8) in [(0,1),(1,0),(5,9),(6,4),(7,0x0c),(8,1),(9,10),(89,1)] {
            var changed = response; changed[index] = value
            changed[88] = NagaDPIButtonProtocol.checksum(changed)
            XCTAssertThrowsError(try NagaDPIButtonProtocol.parse(changed, slot: 9))
        }
        response[11] ^= 1
        XCTAssertThrowsError(try NagaDPIButtonProtocol.parse(response, slot: 9))
        XCTAssertThrowsError(try NagaDPIButtonProtocol.parse(Array(response.dropLast()), slot: 9))
    }
    func testOnlyPhysicalDPITargetsCanBeProgrammedAndLegacyWheelTunnelsStayForbidden() {
        XCTAssertEqual(NagaDPIButton.up.slot, 12)
        XCTAssertEqual(NagaDPIButton.down.slot, 11)
        XCTAssertTrue(NagaDPIButton.remappingAvailable)
        for button in NagaDPIButton.allCases {
            let packet = try! NagaDPIButtonProtocol.write(.init(slot: button.slot, block: [2,2,0,button.usage,0,0,0]))
            XCTAssertEqual(Array(packet[8..<11]), [0,button.slot,0])
            XCTAssertFalse([UInt8(9),10].contains(packet[9]))
        }
        // The old wheel-to-F13/F14 assignments can only be recognized for restoration.
        for target in targets { XCTAssertThrowsError(try NagaDPIButtonProtocol.write(target)) }
    }
    func testMalformedRecoveryCannotReadOrWriteHardware() {
        for invalid in [[], [originals[0]], [originals[0], originals[0]]] {
            XCTAssertThrowsError(try NagaDPIButtonTransaction.restore(originals: invalid,
                read: { _ in XCTFail("Invalid recovery must not read"); return self.originals[0] },
                write: { _ in XCTFail("Invalid recovery must not write") }))
        }
    }
    func testRestoreDoesNotOverwriteAnOutsideChangeAndStillRecoversOtherSlot() {
        let external = NagaDPIButtonBinding(slot: 9, block: [2,2,0,0x1e,0,0,0])
        var actual = [UInt8(9):external, 10:targets[1]]
        XCTAssertThrowsError(try NagaDPIButtonTransaction.restore(originals: originals, read: { actual[$0]! }, write: { actual[$0.slot] = $0 })) { error in
            XCTAssertEqual(error as? NagaDPIButtonError, .conflict)
        }
        XCTAssertEqual(actual[9], external); XCTAssertEqual(actual[10], originals[1])
    }
    func testPartialRecoveryAndAlreadyRestoredSlotsAreIdempotent() throws {
        var actual = [UInt8(9):targets[0], 10:originals[1]]; var writes = 0
        for _ in 0..<2 {
            try NagaDPIButtonTransaction.restore(originals: originals, read: { actual[$0]! }, write: { writes += 1; actual[$0.slot] = $0 })
        }
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(actual[9], originals[0]); XCTAssertEqual(actual[10], originals[1])
    }
    func testRestoreAttemptsBothSlotsAfterAReadFailure() {
        var reads: [UInt8] = []; var writes: [UInt8] = []
        XCTAssertThrowsError(try NagaDPIButtonTransaction.restore(originals: originals, read: { slot in
            reads.append(slot); if slot == 10 { throw NagaDPIButtonError.readback }; return self.targets[0]
        }, write: { writes.append($0.slot) })) { error in XCTAssertEqual(error as? NagaDPIButtonError, .recovery) }
        XCTAssertEqual(reads, [10,9]); XCTAssertEqual(writes, [9])
    }
    func testLegacyWheelTunnelCannotDispatchDPIBindingsWithOldSavedOptIn() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProfileConfiguration())) as! [String:Any]
        object.removeValue(forKey: "remapPhysicalNagaDPIButtons"); object["remapNagaDPIButtons"] = true
        let config = try JSONDecoder().decode(ProfileConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(config.remapNagaDPIButtons)
        let identity = DeviceIdentity(vendorID: 0x1532, productID: 0x0090, transport: "USB", product: "Naga")
        let layout = config.nagaInputLayout(for: identity)
        var decoder = NagaKeyboardDecoder()
        let profile = MouseProfile(bindings: ["112": ActionBinding(action: .copy), "113": ActionBinding(action: .paste)])
        for keyCode: UInt16 in [105,107] {
            for phase: ButtonPhase in [.down,.up] {
                let result = decoder.route(NagaKeyboardInput(token: UInt64(keyCode), keyCode: keyCode,
                    phase: phase, modifiers: [], profile: profile), now: 0, layout: layout)
                XCTAssertTrue(result.dispatches.isEmpty)
            }
        }
        decoder.reset()
        XCTAssertTrue(decoder.ownedKeys.isEmpty)
    }
    func testHeldDPIShortcutKeepsItsPressMappingAndResetReleasesExactlyOnce() {
        var router = InputRouter()
        let command = ActionBinding(action: .modifierKey, modifierKey: .command)
        let profile = MouseProfile(bindings: ["113":command])
        XCTAssertEqual(router.route(button: 113, phase: .down, profile: profile).emissions, [InputEmission(button: 113, binding: command, phase: .down)])
        XCTAssertTrue(router.route(button: 113, phase: .down, profile: MouseProfile()).emissions.isEmpty)
        XCTAssertEqual(router.reset(), [InputEmission(button: 113, binding: command, phase: .up)])
        XCTAssertTrue(router.reset().isEmpty)
        XCTAssertFalse(router.route(button: 113, phase: .up, profile: profile).suppress)
    }
    func testDPIAnchorChordRepeatsWhileHeldAndCanUseScroll() {
        let chord = ChordBinding(buttons: [112,0], binding: ActionBinding(action: .copy))
        let scroll = ChordBinding(buttons: [112,WheelDirection.right.chordInput], binding: ActionBinding(action: .paste))
        let profile = MouseProfile(chords: [chord,scroll]); var router = InputRouter()
        XCTAssertTrue(chord.isValid); XCTAssertTrue(scroll.isValid)
        _ = router.route(button: 112, phase: .down, profile: profile)
        for _ in 0..<3 {
            XCTAssertEqual(router.route(button: 0, phase: .down, profile: profile).emissions.map(\.binding.action), [.copy])
            _ = router.route(button: 0, phase: .up, profile: profile)
            XCTAssertEqual(router.routeScroll(direction: .right).emissions.map(\.binding.action), [.paste])
        }
        _ = router.route(button: 112, phase: .up, profile: profile)
        XCTAssertFalse(router.routeScroll(direction: .right).suppress)
    }
    func testUnassignedDPIInputsAreConsumedOnlyOnceRoutedAndLabelsAreDistinct() {
        let profile = MouseProfile()
        for button in NagaDPIButton.allCases {
            var router = InputRouter()
            XCTAssertEqual(profile.action(for: button.rawValue), .disabled)
            XCTAssertTrue(router.route(button: button.rawValue, phase: .down, profile: profile).suppress)
            XCTAssertTrue(router.route(button: button.rawValue, phase: .up, profile: profile).suppress)
            XCTAssertEqual(ChordButtonChoices.title(button.rawValue), button.title)
        }
        XCTAssertEqual(ChordButtonChoices.sideButtons, Array(100...111))
        XCTAssertEqual(ChordButtonChoices.dpiButtons, [112,113])
    }
}
