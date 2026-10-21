import XCTest
@testable import TailorMouseCore

final class PhysicalDPITransactionTests: XCTestCase {
    private let originals = [NagaDPIButtonBinding(slot: 11, block: [6,1,1,0,0,0,0]), NagaDPIButtonBinding(slot: 12, block: [6,1,2,0,0,0,0])]
    func testBackupPrecedesOnlyPhysicalSlotWrites() throws {
        var calls = [String]()
        try NagaDPIButtonTransaction.apply(originals: originals, backup: { calls.append("backup") }, write: { calls.append("write:\($0.slot)") })
        XCTAssertEqual(calls, ["backup","write:11","write:12"])
        XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: originals, backup: { throw NagaDPIButtonError.recovery }, write: { _ in XCTFail("No write before backup") }))
    }
    func testLandedFailureRollsBackEveryAttemptedSlotInReverseOrder() {
        var actual = Dictionary(uniqueKeysWithValues: originals.map { ($0.slot,$0) })
        var writes = [NagaDPIButtonBinding]()
        XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: originals, backup: {}, write: { binding in
            writes.append(binding); actual[binding.slot] = binding
            if writes.count == 2 { throw NagaDPIButtonError.readback }
        }))
        XCTAssertEqual(writes, NagaDPIButtonBinding.targets + originals.reversed())
        XCTAssertEqual(actual[11], originals[0]); XCTAssertEqual(actual[12], originals[1])
    }
    func testRecoveryFailureRetainsARecoverableErrorAndRejectsUnjournaledTunnels() {
        var writes = [UInt8]()
        XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: originals, backup: {}, write: { b in
            writes.append(b.slot); throw NagaDPIButtonError.readback
        })) { XCTAssertEqual($0 as? NagaDPIButtonError, .recovery) }
        XCTAssertEqual(writes, [11,11])
        for invalid in [[], [originals[0]], [originals[0], originals[0]], NagaDPIButtonBinding.targets, NagaDPIButtonBinding.previousPhysicalTargets, NagaDPIButtonBinding.brightnessPhysicalTargets,
                        [NagaDPIButtonBinding(slot: 9, block: [1,1,9,0,0,0,0]), NagaDPIButtonBinding(slot: 10, block: [1,1,10,0,0,0,0])]] {
            XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: invalid, backup: { XCTFail("No backup for invalid apply") }, write: { _ in XCTFail("No invalid write") }))
        }
    }
    func testPhysicalRestorePreservesExternalChangesAndAttemptsOtherSlot() {
        let external = NagaDPIButtonBinding(slot: 11, block: [2,2,0,0x1e,0,0,0])
        var actual = [UInt8(11):external, 12:NagaDPIButtonBinding.targets[1]]
        XCTAssertThrowsError(try NagaDPIButtonTransaction.restore(originals: originals, read: { actual[$0]! }, write: { actual[$0.slot] = $0 })) { XCTAssertEqual($0 as? NagaDPIButtonError, .conflict) }
        XCTAssertEqual(actual[11], external); XCTAssertEqual(actual[12], originals[1])
    }
    func testPreviousDirectionLeaseRestoresBeforeCorrectedAssignmentsAreApplied() throws {
        var actual = Dictionary(uniqueKeysWithValues: NagaDPIButtonBinding.previousPhysicalTargets.map { ($0.slot,$0) })
        var writes = [NagaDPIButtonBinding]()
        try NagaDPIButtonTransaction.restore(originals: originals, physicalMappingVersion: 1, read: { actual[$0]! }, write: { actual[$0.slot] = $0; writes.append($0) })
        XCTAssertEqual(actual[11], originals[0]); XCTAssertEqual(actual[12], originals[1])
        XCTAssertEqual(writes.count, 2)
        try NagaDPIButtonTransaction.apply(originals: originals, backup: {}, write: { actual[$0.slot] = $0 })
        XCTAssertEqual(actual[11]?.block, [2,2,0,0x6e,0,0,0])
        XCTAssertEqual(actual[12]?.block, [2,2,0,0x6f,0,0,0])
    }
    func testNewJournalDoesNotMistakeAnExternalOppositeAliasForItsOwnWrite() {
        var actual = Dictionary(uniqueKeysWithValues: NagaDPIButtonBinding.previousPhysicalTargets.map { ($0.slot,$0) })
        var writes = [UInt8]()
        XCTAssertThrowsError(try NagaDPIButtonTransaction.restore(originals: originals, physicalMappingVersion: 2,
            read: { actual[$0]! }, write: { actual[$0.slot] = $0; writes.append($0.slot) })) {
            XCTAssertEqual($0 as? NagaDPIButtonError, .conflict)
        }
        XCTAssertTrue(writes.isEmpty)
        XCTAssertThrowsError(try NagaDPIButtonTransaction.restore(originals: originals, physicalMappingVersion: 99,
            read: { _ in XCTFail("Unknown journal version must not read"); return self.originals[0] }, write: { _ in XCTFail("Unknown journal version must not write") }))
    }
    func testBrightnessAliasJournalRestoresBeforeNonBrightnessSignalsAreApplied() throws {
        var actual = Dictionary(uniqueKeysWithValues: NagaDPIButtonBinding.brightnessPhysicalTargets.map { ($0.slot,$0) })
        try NagaDPIButtonTransaction.restore(originals: originals, physicalMappingVersion: 2,
            read: { actual[$0]! }, write: { actual[$0.slot] = $0 })
        XCTAssertEqual(actual[11], originals[0]); XCTAssertEqual(actual[12], originals[1])
        try NagaDPIButtonTransaction.apply(originals: originals, backup: {}, write: { actual[$0.slot] = $0 })
        XCTAssertEqual(actual[11]?.block, [2,2,0,0x6e,0,0,0])
        XCTAssertEqual(actual[12]?.block, [2,2,0,0x6f,0,0,0])
        try NagaDPIButtonTransaction.restore(originals: originals, physicalMappingVersion: 3,
            read: { actual[$0]! }, write: { actual[$0.slot] = $0 })
        XCTAssertEqual(actual[11], originals[0]); XCTAssertEqual(actual[12], originals[1])
    }
    func testCurrentJournalCannotRestoreOlderSignalsAndBrightnessKeysAreNotActiveDPIAliases() {
        for targets in [NagaDPIButtonBinding.previousPhysicalTargets, NagaDPIButtonBinding.brightnessPhysicalTargets] {
            let actual = Dictionary(uniqueKeysWithValues: targets.map { ($0.slot,$0) })
            XCTAssertThrowsError(try NagaDPIButtonTransaction.restore(originals: originals, physicalMappingVersion: 3,
                read: { actual[$0]! }, write: { _ in XCTFail("Older signal is not owned by the current lease") })) {
                XCTAssertEqual($0 as? NagaDPIButtonError, .conflict)
            }
        }
        let layout = NagaKeyboardLayout().includingDPIButtons(true)
        for key: UInt16 in [105,107,113] { // F13/F14/F15
            XCTAssertNil(layout.button(for: key))
            XCTAssertFalse(NagaBluetoothReportDecoder.handles(keyCode: key, layout: layout))
        }
        XCTAssertEqual(NagaDPIButton.mappingVersion, 3)
    }
    func testNewDPIHeldSignalReleasesOnEndpointRemovalAndCanPressAgainAfterReconnect() {
        var reports = NagaBluetoothReportDecoder()
        let down: [UInt8] = [6,0,0x6f,0,0,0,0,0]
        XCTAssertEqual(reports.route(reportID: 6, bytes: down, sourceID: 1).map(\.phase), [.down])
        XCTAssertTrue(reports.route(reportID: 6, bytes: down, sourceID: 1).isEmpty)
        let released = reports.removeSource(1)
        XCTAssertEqual(released.map(\.keyCode), [90]); XCTAssertEqual(released.map(\.phase), [.up])
        XCTAssertTrue(reports.removeSource(1).isEmpty)
        XCTAssertEqual(reports.route(reportID: 6, bytes: down, sourceID: 2).map(\.phase), [.down])
        XCTAssertEqual(reports.route(reportID: 6, bytes: [6,0,0,0,0,0,0,0], sourceID: 2).map(\.phase), [.up])
    }
    func testCorrectedPhysicalSlotsKeepDistinctSavedActionsAndMatchedEdges() {
        let up = ActionBinding(action: .modifierKey, modifierKey: .command)
        let down = ActionBinding(action: .modifierKey, modifierKey: .option)
        let profile = MouseProfile(bindings: ["112":up,"113":down])
        let layout = NagaKeyboardLayout().includingDPIButtons(true)
        for (slot, usage, keyCode, logical, binding): (UInt8,UInt8,UInt16,Int,ActionBinding) in [(11,0x6e,80,112,up),(12,0x6f,90,113,down)] {
            XCTAssertEqual(NagaDPIButtonBinding.targets.first { $0.slot == slot }?.block, [2,2,0,usage,0,0,0])
            XCTAssertEqual(layout.button(for: keyCode), logical)
            var router = InputRouter()
            XCTAssertEqual(router.route(button: logical, phase: .down, profile: profile).emissions, [InputEmission(button: logical, binding: binding, phase: .down)])
            XCTAssertTrue(router.route(button: logical, phase: .down, profile: profile).emissions.isEmpty)
            XCTAssertEqual(router.route(button: logical, phase: .up, profile: MouseProfile()).emissions, [InputEmission(button: logical, binding: binding, phase: .up)])
            XCTAssertTrue(router.reset().isEmpty)
        }
    }
    private func profileReply(status: UInt8, profile: UInt8 = 1) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 90)
        bytes[0] = status; bytes[1] = 0x1f; bytes[6] = 5; bytes[7] = 0x84; bytes[8] = profile
        bytes[88] = NagaDPIButtonProtocol.checksum(bytes); return bytes
    }
    func testOnlyExplicitReceiverTimeoutCanWaitWithoutProgramming() throws {
        let timeout = profileReply(status: 4)
        XCTAssertThrowsError(try NagaDPIButtonProtocol.activeProfileReply(timeout, product: 0x0090)) { XCTAssertEqual($0 as? NagaDPIButtonError, .receiverUnavailable) }
        XCTAssertNil(try NagaDPIButtonProtocol.activeProfileReply(timeout, product: 0x008f))
        for status: UInt8 in [0,1,3,5] { XCTAssertNil(try NagaDPIButtonProtocol.activeProfileReply(profileReply(status: status), product: 0x0090)) }
        XCTAssertEqual(try NagaDPIButtonProtocol.activeProfileReply(profileReply(status: 2), product: 0x0090), 1)
        XCTAssertNil(try NagaDPIButtonProtocol.activeProfileReply(profileReply(status: 2, profile: 0), product: 0x0090))
    }
    func testUnrelatedOrCorruptReplyCannotBeMisclassifiedAsReceiverTimeout() throws {
        let valid = profileReply(status: 4)
        for index in [1,6,7,88,89] {
            var bytes = valid; bytes[index] ^= 1
            if index != 88 { bytes[88] = NagaDPIButtonProtocol.checksum(bytes) }
            XCTAssertNil(try NagaDPIButtonProtocol.activeProfileReply(bytes, product: 0x0090))
        }
        XCTAssertNil(try NagaDPIButtonProtocol.activeProfileReply(Array(valid.dropLast()), product: 0x0090))
    }
    func testPhysicalHeldAliasesHaveMatchedReleaseAndResetWithoutRepeats() {
        var reports = NagaBluetoothReportDecoder(); var decoder = NagaKeyboardDecoder(); var router = InputRouter()
        let layout = NagaKeyboardLayout().includingDPIButtons(true)
        let binding = ActionBinding(action: .modifierKey, modifierKey: .command)
        let profile = MouseProfile(bindings: ["112":binding,"113":binding])
        var emissions = [InputEmission](); var token: UInt64 = 0
        for usages: [UInt8] in [[0x6e], [0x6e], [0x6e,0x6f], [0x6f], []] {
            let bytes = [UInt8(6),0] + usages + Array(repeating: 0, count: 6-usages.count)
            for edge in reports.route(reportID: 6, bytes: bytes, sourceID: 1) {
                token += 1
                let result = decoder.route(NagaKeyboardInput(token: token, keyCode: edge.keyCode, phase: edge.phase, modifiers: [], profile: profile), now: Double(token), layout: layout)
                for event in result.dispatches { emissions += router.route(button: event.button, phase: event.phase, profile: event.profile).emissions }
            }
        }
        XCTAssertEqual(emissions.map(\.button), [112,113,112,113])
        XCTAssertEqual(emissions.map(\.phase), [.down,.down,.up,.up]); XCTAssertTrue(router.reset().isEmpty)
    }
}
