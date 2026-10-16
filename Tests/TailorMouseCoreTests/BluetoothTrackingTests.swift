import XCTest
@testable import TailorMouseCore

final class BluetoothTrackingTests: XCTestCase {
    private let wired = NativePointerValues(resolution: 26214400, acceleration: 98304)
    private let original = NativePointerValues(resolution: 26214400, acceleration: 32768)
    private let device = DeviceIdentity(vendorID: 0x1532, productID: 0x0092, transport: "Bluetooth Low Energy", product: "")

    private func replacing(_ v: NativePointerValues, _ p: NativePointerProperty, _ x: Int64) -> NativePointerValues {
        NativePointerValues(resolution: p == .resolution ? x : v.resolution,
                            acceleration: p == .acceleration ? x : v.acceleration,
                            accelerationMultiplier: p == .accelerationMultiplier ? x : v.accelerationMultiplier)
    }
    private func target(_ profile: MouseProfile = MouseProfile(pointerSensitivity: 0.34)) throws -> NativePointerValues {
        try original.target(profile: profile, reference: wired, device: device, reportInterval: 8000)
    }

    func testVerifiedBluetoothCorrectionPreservesSharedSliderTargets() throws {
        let corrected = try target()
        XCTAssertEqual(corrected.resolution, 77101176)
        XCTAssertEqual(corrected.acceleration, 98304)
        XCTAssertEqual(corrected.accelerationMultiplier, 8192)
        let app = try target(MouseProfile(pointerAcceleration: 0.5, pointerSensitivity: 1.5))
        XCTAssertEqual(app.acceleration, 32768)
        XCTAssertEqual(app.resolution, 17476267)
        XCTAssertEqual(app.accelerationMultiplier, corrected.accelerationMultiplier)
        XCTAssertEqual(try corrected.target(profile: MouseProfile(pointerSensitivity: 0.34), reference: wired,
                                           device: device, reportInterval: 8000), corrected)
    }

    func testCorrectionRequiresExactNagaBluetoothAndObservedInterval() throws {
        let identities = [DeviceIdentity(vendorID: 0x1532, productID: 0x008f, transport: "USB", product: ""),
                          DeviceIdentity(vendorID: 0x1532, productID: 0x0090, transport: "USB", product: ""),
                          DeviceIdentity(vendorID: 123, productID: 0x0092, transport: "Bluetooth", product: ""),
                          DeviceIdentity(vendorID: 0x1532, productID: 0x0092, transport: "USB", product: "")]
        for identity in identities {
            XCTAssertEqual(try original.target(profile: MouseProfile(), reference: wired, device: identity, reportInterval: 8000).accelerationMultiplier, 65536)
        }
        for interval in [nil, 1000, 0, 16000] as [Int?] {
            XCTAssertEqual(try original.target(profile: MouseProfile(), reference: wired, device: device, reportInterval: interval).accelerationMultiplier, 65536)
        }
        let custom = NativePointerValues(resolution: 26214400, acceleration: 32768, accelerationMultiplier: 32768)
        XCTAssertEqual(try custom.target(profile: MouseProfile(), device: device, reportInterval: 8000), custom)
    }

    func testLegacyReferenceDefaultsMultiplierAndNewReferenceRoundTrips() throws {
        let old = Data(#"{"resolution":26214400,"acceleration":98304}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(NativePointerValues.self, from: old), wired)
        let corrected = try target()
        XCTAssertEqual(try JSONDecoder().decode(NativePointerValues.self, from: JSONEncoder().encode(corrected)), corrected)
    }

    func testMultiplierOnlyChangeCommitsCurveAndStopRestoresEffectiveDefault() throws {
        var live = wired
        let corrected = NativePointerValues(resolution: wired.resolution, acceleration: wired.acceleration, accelerationMultiplier: 8192)
        var writes: [NativePointerProperty] = []
        func write(_ p: NativePointerProperty, _ x: Int64) { writes.append(p); live = replacing(live,p,x) }
        try NativePointerTransaction.apply(before: live, target: corrected, write: write, read: {live})
        XCTAssertEqual(writes, [.accelerationMultiplier, .acceleration])
        XCTAssertEqual(live, corrected)
        writes.removeAll()
        try NativePointerTransaction.apply(before: live, target: wired, write: write, read: {live})
        XCTAssertEqual(writes, [.accelerationMultiplier, .acceleration])
        XCTAssertEqual(live, wired)
    }

    func testEveryLandedWriteFailureRestoresConnectionSnapshot() throws {
        let corrected = try target()
        for failureAt in 1...3 {
            var live = original; var attempts = 0
            XCTAssertThrowsError(try NativePointerTransaction.apply(before: live, target: corrected, write: {p,x in
                attempts += 1; live = self.replacing(live,p,x)
                if attempts == failureAt {throw NativePointerError.writeFailed}
            }, read: {live}))
            XCTAssertEqual(live, original)
        }
    }

    func testReadbackFailureRestoresAllThreePropertiesInCommitOrder() throws {
        let corrected = try target()
        var live = original; var reads = 0; var writes: [NativePointerProperty] = []
        XCTAssertThrowsError(try NativePointerTransaction.apply(before: live, target: corrected, write: {p,x in
            writes.append(p); live = self.replacing(live,p,x)
        }, read: {
            reads += 1
            return reads == 1 ? self.original : live
        }))
        XCTAssertEqual(live, original)
        XCTAssertEqual(writes, [.resolution,.accelerationMultiplier,.acceleration,.resolution,.accelerationMultiplier,.acceleration])
    }

    func testInvalidMultiplierRejectsReferenceBeforeApplyingTracking() throws {
        for invalid in [0, -1, Int64.max] as [Int64] {
            let values = NativePointerValues(resolution: wired.resolution, acceleration: wired.acceleration, accelerationMultiplier: invalid)
            XCTAssertThrowsError(try original.target(profile: MouseProfile(), reference: values))
            let config = ProfileConfiguration(nagaWiredTrackingReference: values)
            XCTAssertThrowsError(try JSONDecoder().decode(ProfileConfiguration.self, from: JSONEncoder().encode(config)))
        }
    }
}
