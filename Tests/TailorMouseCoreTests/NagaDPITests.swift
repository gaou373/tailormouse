import XCTest
@testable import TailorMouseCore

final class NagaDPITests: XCTestCase {
    private let original = try! NagaDPI(x: 3200, y: 1600)
    private let target = try! NagaDPI(x: 800, y: 800)

    func testLiveWriteFramingAndIndependentAxes() throws {
        let bytes = try NagaDPIProtocol.write(original)
        XCTAssertEqual(bytes.count, 90)
        XCTAssertEqual(Array(bytes[5..<15]), [7, 4, 5, 0, 0x0c, 0x80, 6, 0x40, 0, 0])
        XCTAssertEqual(bytes[88], NagaDPIProtocol.checksum(bytes))
        XCTAssertEqual(bytes[89], 0)
    }
    func testValidatedReadAndWrongResponseRejection() throws {
        var bytes = try NagaDPIProtocol.write(original)
        bytes[0] = 2; bytes[7] = 0x85; bytes[88] = NagaDPIProtocol.checksum(bytes)
        XCTAssertEqual(try NagaDPIProtocol.parse(bytes), original)
        let mutations: [(Int, UInt8)] = [(0, 1), (1, 0xff), (5, 6), (6, 2), (7, 5), (8, 1), (88, 0), (89, 1)]
        for (index, value) in mutations {
            var changed = bytes; changed[index] = value
            XCTAssertThrowsError(try NagaDPIProtocol.parse(changed))
        }
        XCTAssertThrowsError(try NagaDPIProtocol.parse(Array(bytes.dropLast())))
    }
    func testBoundsAndDecodedInvalidValueCannotWrite() throws {
        XCTAssertThrowsError(try NagaDPI(x: 99, y: 800))
        XCTAssertThrowsError(try NagaDPI(x: 800, y: 20001))
        let invalid = try JSONDecoder().decode(NagaDPI.self, from: Data("{\"x\":-1,\"y\":800}".utf8))
        XCTAssertThrowsError(try NagaDPIProtocol.write(invalid))
    }
    func testBackupPrecedesWriteAndReadback() throws {
        var calls: [String] = []; var actual = original
        try NagaDPITransaction.apply(before: original, target: target,
            backup: { calls.append("backup") }, write: { calls.append("write"); actual = $0 },
            read: { calls.append("read"); return actual })
        XCTAssertEqual(calls, ["backup", "write", "read"])
        XCTAssertEqual(actual, target)
    }
    func testNoopDoesNotBackUpOrWrite() throws {
        try NagaDPITransaction.apply(before: original, target: original,
            backup: { XCTFail("No backup for no-op") }, write: { _ in XCTFail("No write for no-op") },
            read: { XCTFail("No read for no-op"); return self.original })
    }
    func testBackupFailurePreventsMutation() {
        XCTAssertThrowsError(try NagaDPITransaction.apply(before: original, target: target,
            backup: { throw NagaDPIError.invalidResponse }, write: { _ in XCTFail("Must not write") },
            read: { XCTFail("Must not read"); return self.original }))
    }
    func testLandedWriteErrorRestoresAndVerifiesOriginalAxes() {
        var actual = original; var writes: [NagaDPI] = []; var reads = 0
        XCTAssertThrowsError(try NagaDPITransaction.apply(before: original, target: target,
            backup: {}, write: { dpi in
                actual = dpi; writes.append(dpi)
                if writes.count == 1 { throw NagaDPIError.invalidResponse }
            }, read: { reads += 1; return actual }))
        XCTAssertEqual(writes, [target, original]); XCTAssertEqual(reads, 1)
        XCTAssertEqual(actual, original)
    }
    func testReadbackMismatchRestoresPreviousValue() {
        var writes: [NagaDPI] = []
        XCTAssertThrowsError(try NagaDPITransaction.apply(before: original, target: target,
            backup: {}, write: { writes.append($0) }, read: { self.original }))
        XCTAssertEqual(writes, [target, original])
    }
    func testFailedRecoveryIsReported() {
        XCTAssertThrowsError(try NagaDPITransaction.apply(before: original, target: target,
            backup: {}, write: { _ in }, read: { try NagaDPI(x: 400, y: 400) })) { error in
                guard case NagaDPIError.recoveryFailed = error else { return XCTFail("Must report recovery failure") }
            }
    }
}
