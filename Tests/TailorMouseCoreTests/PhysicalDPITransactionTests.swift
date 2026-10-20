import XCTest
@testable import TailorMouseCore

final class PhysicalDPITransactionTests: XCTestCase {
    private let originals = [NagaDPIButtonBinding(slot: 12, block: [6,1,2,0,0,0,0]), NagaDPIButtonBinding(slot: 11, block: [6,1,1,0,0,0,0])]
    func testBackupPrecedesOnlyPhysicalSlotWrites() throws {
        var calls = [String]()
        try NagaDPIButtonTransaction.apply(originals: originals, backup: { calls.append("backup") }, write: { calls.append("write:\($0.slot)") })
        XCTAssertEqual(calls, ["backup","write:12","write:11"])
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
        XCTAssertEqual(actual[12], originals[0]); XCTAssertEqual(actual[11], originals[1])
    }
    func testRecoveryFailureRetainsARecoverableErrorAndRejectsUnjournaledTunnels() {
        var writes = [UInt8]()
        XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: originals, backup: {}, write: { b in
            writes.append(b.slot); throw NagaDPIButtonError.readback
        })) { XCTAssertEqual($0 as? NagaDPIButtonError, .recovery) }
        XCTAssertEqual(writes, [12,12])
        for invalid in [[], [originals[0]], [originals[0], originals[0]], NagaDPIButtonBinding.targets,
                        [NagaDPIButtonBinding(slot: 9, block: [1,1,9,0,0,0,0]), NagaDPIButtonBinding(slot: 10, block: [1,1,10,0,0,0,0])]] {
            XCTAssertThrowsError(try NagaDPIButtonTransaction.apply(originals: invalid, backup: { XCTFail("No backup for invalid apply") }, write: { _ in XCTFail("No invalid write") }))
        }
    }
    func testPhysicalRestorePreservesExternalChangesAndAttemptsOtherSlot() {
        let external = NagaDPIButtonBinding(slot: 12, block: [2,2,0,0x1e,0,0,0])
        var actual = [UInt8(12):external, 11:NagaDPIButtonBinding.targets[1]]
        XCTAssertThrowsError(try NagaDPIButtonTransaction.restore(originals: originals, read: { actual[$0]! }, write: { actual[$0.slot] = $0 })) { XCTAssertEqual($0 as? NagaDPIButtonError, .conflict) }
        XCTAssertEqual(actual[12], external); XCTAssertEqual(actual[11], originals[1])
    }
    func testPhysicalHeldAliasesHaveMatchedReleaseAndResetWithoutRepeats() {
        var reports = NagaBluetoothReportDecoder(); var decoder = NagaKeyboardDecoder(); var router = InputRouter()
        let layout = NagaKeyboardLayout().includingDPIButtons(true)
        let binding = ActionBinding(action: .modifierKey, modifierKey: .command)
        let profile = MouseProfile(bindings: ["112":binding,"113":binding])
        var emissions = [InputEmission](); var token: UInt64 = 0
        for usages: [UInt8] in [[0x68], [0x68], [0x68,0x69], [0x69], []] {
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
