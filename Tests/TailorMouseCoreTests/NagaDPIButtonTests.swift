import XCTest
@testable import TailorMouseCore

final class NagaDPIButtonTests: XCTestCase {
    private let originals = [NagaDPIButtonBinding(slot: 9, block: [1,1,9,0,0,0,0]), NagaDPIButtonBinding(slot: 10, block: [1,1,10,0,0,0,0])]
    private var targets: [NagaDPIButtonBinding] { NagaDPIButtonBinding.targets }

    func testOnlyOriginalUSBAndReceiverCanEnableAliases() {
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
        object.removeValue(forKey: "remapNagaDPIButtons")
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
        for target in targets {
            let read = try NagaDPIButtonProtocol.read(slot: target.slot)
            let write = try NagaDPIButtonProtocol.write(target)
            XCTAssertEqual(read.count, 90); XCTAssertEqual(write.count, 90)
            XCTAssertEqual(Array(write[5..<11]), [10,2,0x0c,0,target.slot,0])
            XCTAssertEqual(Array(write[11..<18]), target.block)
            XCTAssertEqual(read[7], 0x8c)
            XCTAssertEqual(write[88], NagaDPIButtonProtocol.checksum(write))
        }
        for slot: UInt8 in [0,1,8,11,0x40,0x60] {
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
    func testBackupMustPrecedeAnyWrite() throws {
        var calls: [String] = []
        try NagaDPIButtonTransaction.apply(originals: originals, backup: { calls.append("backup") }, write: { calls.append("write:\($0.slot)") })
        XCTAssertEqual(calls, ["backup","write:9","write:10"])
        XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: originals, backup: { throw NagaDPIButtonError.recovery }, write: { _ in XCTFail("No write without backup") }))
    }
    func testFailedOrPossiblyLandedWriteRollsBackBothSlotsInReverseOrder() {
        var actual = Dictionary(uniqueKeysWithValues: originals.map { ($0.slot, $0) })
        var writes: [NagaDPIButtonBinding] = []
        XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: originals, backup: {}, write: { binding in
            writes.append(binding); actual[binding.slot] = binding
            if writes.count == 2 { throw NagaDPIButtonError.readback }
        }))
        XCTAssertEqual(writes, targets + originals.reversed())
        XCTAssertEqual(actual[9], originals[0]); XCTAssertEqual(actual[10], originals[1])
    }
    func testFirstWriteFailureAlsoRollsBackAndRecoveryFailureIsDistinct() {
        var writes: [UInt8] = []
        XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: originals, backup: {}, write: { binding in
            writes.append(binding.slot)
            throw NagaDPIButtonError.readback
        })) { error in XCTAssertEqual(error as? NagaDPIButtonError, .recovery) }
        XCTAssertEqual(writes, [9,9])
    }
    func testMalformedOrUnjournaledTunnelCannotBeAdopted() {
        for invalid in [[], [originals[0]], [originals[0], originals[0]], targets, [originals[0], targets[1]]] {
            XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: invalid, backup: { XCTFail("Invalid original") }, write: { _ in XCTFail("Invalid original") }))
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
    func testUSBReportHoldsHaveOneDownAndOneUpDespiteRepeatedSnapshots() {
        var reports = NagaBluetoothReportDecoder(); var decoder = NagaKeyboardDecoder(); var router = InputRouter()
        let layout = NagaKeyboardLayout().includingDPIButtons(true)
        let binding = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 8), shortcutBehavior: .hold)
        let profile = MouseProfile(bindings: ["112":binding, "113":binding])
        var emissions: [InputEmission] = []; var token: UInt64 = 0
        for usages: [UInt8] in [[0x68], [0x68], [0x68,0x69], [0x68,0x69], [0x69], []] {
            let raw: [UInt8] = [0,0] + usages + Array(repeating: 0, count: 6-usages.count)
            let canonical = NagaKeyboardReportFormat.usbBoot.canonical(reportID: 0, bytes: raw)!
            for edge in reports.route(reportID: 6, bytes: canonical) {
                token += 1
                let result = decoder.route(NagaKeyboardInput(token: token, keyCode: edge.keyCode, phase: edge.phase, modifiers: [], profile: profile), now: Double(token), layout: layout)
                for input in result.dispatches { emissions += router.route(button: input.button, phase: input.phase, profile: input.profile).emissions }
            }
        }
        XCTAssertEqual(emissions.map(\.button), [112,113,112,113])
        XCTAssertEqual(emissions.map(\.phase), [.down,.down,.up,.up])
        XCTAssertTrue(router.reset().isEmpty)
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
