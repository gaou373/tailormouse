import XCTest
@testable import TailorMouseCore

final class InputInspectionOriginTests: XCTestCase {
    func testRawSidePressRemainsSelectedAcrossGeneratedMousePair() {
        var raw = NagaBluetoothReportDecoder()
        var recorder = MouseButtonRecording(); recorder.begin()
        var selected: Int?; var ordinary: Set<Int> = []; var captured: [Int] = []
        func inspect(_ button: Int, _ phase: ButtonPhase, _ source: String) {
            if phase == .down {
                selected = button
                if button < 32 { ordinary.insert(button) }
            }
            if let value = recorder.route(button: button, phase: phase, source: source) { captured.append(value) }
        }
        // Replay the observed order: raw report 6 identifies side 1, then
        // SteerMouse posts Button 4 with the same physical sender identity.
        for edge in raw.route(reportID: 6, bytes: [6,0,0,0x1e,0,0,0,0]) {
            inspect(NagaKeyMap.button(for: edge.keyCode)!, edge.phase, "hid:naga")
        }
        for phase in [ButtonPhase.down, .up] {
            if InputInspectionOrigin.acceptsQuartz(processID: 6095, userData: 0, remapperProcessIDs: [6095]) {
                inspect(3, phase, "quartz:naga")
            }
        }
        XCTAssertEqual(selected, 100); XCTAssertTrue(ordinary.isEmpty); XCTAssertTrue(captured.isEmpty)
        for edge in raw.route(reportID: 6, bytes: [6,0,0,0,0,0,0,0]) {
            inspect(NagaKeyMap.button(for: edge.keyCode)!, edge.phase, "hid:naga")
        }
        XCTAssertEqual(captured, [100]); XCTAssertFalse(recorder.active)
    }

    func testGeneratedPairCannotArmRecordingAndNativeExtraButtonStillWorks() {
        var recorder = MouseButtonRecording(); recorder.begin()
        for phase in [ButtonPhase.down, .up] {
            if InputInspectionOrigin.acceptsQuartz(processID: 6095, userData: 0, remapperProcessIDs: [6095]) {
                XCTFail("Generated edge reached the recorder")
                _ = recorder.route(button: 3, phase: phase, source: "quartz:naga")
            }
        }
        XCTAssertTrue(recorder.active)
        XCTAssertTrue(InputInspectionOrigin.acceptsQuartz(processID: 0, userData: 0, remapperProcessIDs: [6095]))
        XCTAssertNil(recorder.route(button: 3, phase: .down, source: "quartz:naga"))
        XCTAssertEqual(recorder.route(button: 3, phase: .up, source: "quartz:naga"), 3)
    }

    func testRestartedManagerUsesCurrentProcessIDsAndOwnOutputIsAlwaysIgnored() {
        XCTAssertFalse(InputInspectionOrigin.acceptsQuartz(processID: 7000, userData: 0, remapperProcessIDs: [7000]))
        XCTAssertTrue(InputInspectionOrigin.acceptsQuartz(processID: 6095, userData: 0, remapperProcessIDs: [7000]))
        XCTAssertTrue(InputInspectionOrigin.acceptsQuartz(processID: 7000, userData: 0, remapperProcessIDs: []))
        XCTAssertFalse(InputInspectionOrigin.acceptsQuartz(processID: 0, userData: InputInspectionOrigin.tailorMouseTag, remapperProcessIDs: []))
    }

    func testCancelledRawHoldCannotCompleteNextRecording() {
        var recorder = MouseButtonRecording(); recorder.begin()
        _ = recorder.route(button: 100, phase: .down, source: "hid:naga")
        recorder.cancel(); recorder.begin()
        XCTAssertNil(recorder.route(button: 100, phase: .up, source: "hid:naga"))
        XCTAssertNil(recorder.route(button: 101, phase: .down, source: "hid:naga"))
        XCTAssertEqual(recorder.route(button: 101, phase: .up, source: "hid:naga"), 101)
    }
}
