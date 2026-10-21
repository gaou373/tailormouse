import XCTest
@testable import TailorMouseCore

final class NagaHyperSpeedTests: XCTestCase {
    private let mouse = DeviceIdentity(vendorID: 0x1532, productID: 0x00b4, transport: "USB", product: "Razer Naga V2 HyperSpeed")
    private func extended(_ keys: [UInt8] = [], modifiers: UInt8 = 0) -> [UInt8] {
        [1, modifiers] + keys + Array(repeating: 0, count: 14 - keys.count)
    }
    private func canonical(_ keys: [UInt8] = [], modifiers: UInt8 = 0) -> [UInt8] {
        NagaKeyboardReportFormat.usbExtended.canonical(reportID: 1, bytes: extended(keys, modifiers: modifiers))!
    }
    func testIdentityIsSeparateFromProAndRequiresVendorAndProduct() {
        XCTAssertEqual(mouse.canonicalFamily, "razer.naga.v2.hyperspeed")
        XCTAssertTrue(mouse.supportsNagaKeyboard)
        XCTAssertTrue(DeviceIdentity.supportsNagaKeyboard(family: mouse.canonicalFamily))
        for identity in [DeviceIdentity(vendorID: 1, productID: 0x00b4, transport: "USB", product: mouse.product),
                         DeviceIdentity(vendorID: 0x1532, productID: 0x0091, transport: "USB", product: mouse.product)] {
            XCTAssertFalse(identity.supportsNagaKeyboard)
            XCTAssertNil(NagaKeyboardReportFormat(identity: identity))
        }
        XCTAssertTrue(NagaDPIButton.supports(mouse))
        XCTAssertTrue(NagaDPIButton.supports(family: mouse.canonicalFamily))
        XCTAssertFalse(NagaDPIButton.reportsActiveProfile(product: 0x00b4))
        var bluetooth = mouse; bluetooth.transport = "Bluetooth Low Energy"
        XCTAssertNil(NagaKeyboardReportFormat(identity: bluetooth))
        XCTAssertFalse(NagaDPIButton.supports(bluetooth))
    }
    func testBothDescriptorBackedInterfacesAreRecognizedAndMalformedReportsRejected() {
        XCTAssertEqual(NagaKeyboardReportFormat.select(identity: mouse, keyboardReportIDs: [0]), .usbBoot)
        XCTAssertEqual(NagaKeyboardReportFormat.select(identity: mouse, keyboardReportIDs: [1]), .usbExtended)
        XCTAssertNil(NagaKeyboardReportFormat.select(identity: mouse, keyboardReportIDs: [2, 10]))
        let format = NagaKeyboardReportFormat.usbExtended
        XCTAssertEqual(format.canonical(reportID: 1, bytes: extended([0x1e]))?.count, 16)
        XCTAssertNil(format.canonical(reportID: 0, bytes: extended()))
        XCTAssertNil(format.canonical(reportID: 1, bytes: [UInt8](repeating: 0, count: 16)))
        XCTAssertNil(format.canonical(reportID: 1, bytes: Array(extended().dropLast())))
    }
    func testNestedRegistryFallbackIgnoresMouseAndOutputElements() {
        let elements: [[String: Any]] = [["Elements": [
            ["UsagePage": 7, "Type": 2, "ReportID": 1],
            ["UsagePage": 7, "Type": 129, "ReportID": 2],
            ["UsagePage": 9, "Type": 2, "ReportID": 10]
        ]]]
        XCTAssertEqual(NagaKeyboardReportFormat.keyboardReportIDs(in: elements), [1])
        XCTAssertTrue(NagaKeyboardReportFormat.keyboardReportIDs(in: []).isEmpty)
    }
    func testAllTwelveExtendedSlotsPreserveHoldsAndReleaseAfterProfileSwitch() {
        let usages: [UInt8] = Array(0x1e...0x27) + [0x2d, 0x2e]
        var raw = NagaBluetoothReportDecoder()
        var router = InputRouter()
        let profile = MouseProfile(bindings: Dictionary(uniqueKeysWithValues: (100...111).map { (String($0), ActionBinding(action: .copy)) }))
        let down = raw.route(reportID: 6, bytes: canonical(usages, modifiers: 4), sourceID: 1)
        XCTAssertEqual(down.count, 12)
        for edge in down {
            XCTAssertEqual(edge.modifiers, .option)
            let button = NagaKeyMap.button(for: edge.keyCode)!
            XCTAssertTrue(router.route(button: button, phase: edge.phase, profile: profile).suppress)
        }
        XCTAssertTrue(raw.route(reportID: 6, bytes: canonical(usages), sourceID: 1).isEmpty)
        let up = raw.route(reportID: 6, bytes: canonical(), sourceID: 1)
        XCTAssertEqual(up.count, 12)
        for edge in up {
            XCTAssertEqual(edge.phase, .up)
            XCTAssertTrue(router.route(button: NagaKeyMap.button(for: edge.keyCode)!, phase: edge.phase, profile: MouseProfile()).suppress)
        }
    }
    func testCompositeSnapshotsDoNotReleaseOrDuplicateAnotherInterfaceHold() {
        var raw = NagaBluetoothReportDecoder()
        let boot = NagaKeyboardReportFormat.usbBoot.canonical(reportID: 0, bytes: [0, 0, 0x1e, 0, 0, 0, 0, 0])!
        XCTAssertEqual(raw.route(reportID: 6, bytes: boot, sourceID: 10).map(\.phase), [.down])
        XCTAssertTrue(raw.route(reportID: 6, bytes: canonical([0x1e]), sourceID: 11).isEmpty)
        XCTAssertTrue(raw.route(reportID: 6, bytes: canonical(), sourceID: 11).isEmpty)
        XCTAssertEqual(raw.route(reportID: 6, bytes: [6,0,0,0,0,0,0,0], sourceID: 10).map(\.phase), [.up])
    }
    func testRolloverBaselineAndResetRecovery() {
        var raw = NagaBluetoothReportDecoder()
        raw.prime(reportID: 6, bytes: canonical([0x1e]), sourceID: 10)
        raw.prime(reportID: 6, bytes: canonical(), sourceID: 11)
        XCTAssertTrue(raw.route(reportID: 6, bytes: canonical([0x1e]), sourceID: 10).isEmpty)
        XCTAssertTrue(raw.route(reportID: 6, bytes: canonical(), sourceID: 10).isEmpty)
        XCTAssertEqual(raw.route(reportID: 6, bytes: canonical([0x2e]), sourceID: 10).map(\.phase), [.down])
        XCTAssertTrue(raw.route(reportID: 6, bytes: canonical([1]), sourceID: 10).isEmpty)
        XCTAssertEqual(raw.route(reportID: 6, bytes: canonical(), sourceID: 10).map(\.phase), [.up])
        _ = raw.route(reportID: 6, bytes: canonical([0x1e]), sourceID: 10)
        raw.reset()
        XCTAssertTrue(raw.route(reportID: 6, bytes: canonical(), sourceID: 10).isEmpty)
        XCTAssertEqual(raw.route(reportID: 6, bytes: canonical([0x1e]), sourceID: 10).map(\.phase), [.down])
    }
}
