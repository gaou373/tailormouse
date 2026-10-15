import XCTest
@testable import TailorMouseCore

final class SharedTrackingTests: XCTestCase {
    private let wired = NativePointerValues(resolution: 26214400, acceleration: 98304)
    private let receiver = NativePointerValues(resolution: 90112000, acceleration: 98304)
    private let bluetooth = NativePointerValues(resolution: 26214400, acceleration: 32768)

    func testOneWiredReferenceGivesAllConnectionsTheSameResolutionAndAcceleration() throws {
        let profile = MouseProfile(pointerSensitivity: 0.72)
        let expected = try wired.target(profile: profile)
        XCTAssertEqual(expected, NativePointerValues(resolution: 36408889, acceleration: 98304))
        for original in [wired,receiver,bluetooth] {
            XCTAssertEqual(try original.target(profile: profile, reference: wired), expected)
        }
    }

    func testProfileEditsAndReconnectsDoNotCompoundTheSharedReference() throws {
        let faster = MouseProfile(pointerAcceleration: 0.8, pointerSensitivity: 1.5)
        let slow = MouseProfile(pointerAcceleration: 0.5, pointerSensitivity: 0.5)
        let applied = try receiver.target(profile: faster, reference: wired)
        XCTAssertEqual(try applied.target(profile: faster, reference: wired), applied)
        XCTAssertEqual(try bluetooth.target(profile: faster, reference: wired), applied)
        XCTAssertEqual(try applied.target(profile: slow, reference: wired), try wired.target(profile: slow))
        XCTAssertEqual(try applied.target(profile: MouseProfile(), reference: wired), wired)
    }

    func testSharedTrackingRestoresEachConnectionsOwnOriginalValues() throws {
        let profile = MouseProfile(pointerSensitivity: 0.72)
        for original in [wired,receiver,bluetooth] {
            var live = original
            func write(_ property: NativePointerProperty, _ value: Int64) {
                live = NativePointerValues(resolution: property == .resolution ? value : live.resolution,
                    acceleration: property == .acceleration ? value : live.acceleration)
            }
            let target = try original.target(profile: profile, reference: wired)
            try NativePointerTransaction.apply(before: live, target: target, write: write, read: { live })
            XCTAssertEqual(live, target)
            try NativePointerTransaction.apply(before: live, target: original, write: write, read: { live })
            XCTAssertEqual(live, original)
        }
    }

    func testDriverResetWithSameServiceCanReapplyTheUnchangedTarget() throws {
        let target = try receiver.target(profile: MouseProfile(pointerSensitivity: 0.72), reference: wired)
        var live = receiver; var writes = 0
        func write(_ property: NativePointerProperty, _ value: Int64) {
            writes += 1
            live = NativePointerValues(resolution: property == .resolution ? value : live.resolution,
                acceleration: property == .acceleration ? value : live.acceleration)
        }
        for _ in 0..<3 {
            live = receiver // Driver resets native parameters without replacing its service.
            try NativePointerTransaction.apply(before: live, target: target, write: write, read: { live })
            XCTAssertEqual(live, target)
        }
        XCTAssertEqual(writes, 6)
        try NativePointerTransaction.apply(before: live, target: target, write: write, read: { live })
        XCTAssertEqual(writes, 6)
    }

    func testPersistentReferenceSurvivesRestartAndLegacyConfigurationsStillDecode() throws {
        let config = ProfileConfiguration(defaultProfile: MouseProfile(pointerSensitivity: 0.72),
            appProfiles: [MouseProfile(name: "Editor", bundleIdentifier: "example.editor", pointerSensitivity: 1.5)],
            nagaWiredTrackingReference: wired)
        let restored = try JSONDecoder().decode(ProfileConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored, config)
        let app = restored.profile(for: "example.editor")
        XCTAssertEqual(try receiver.target(profile: app, reference: restored.nagaWiredTrackingReference), try wired.target(profile: app))
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as! [String:Any]
        legacy.removeValue(forKey: "nagaWiredTrackingReference")
        let old = try JSONDecoder().decode(ProfileConfiguration.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.nagaWiredTrackingReference)
        XCTAssertEqual(try receiver.target(profile: MouseProfile()), receiver)
    }

    func testCorruptReferenceIsRejectedBeforeAnyTrackingWrite() throws {
        for invalid in [NativePointerValues(resolution: 0, acceleration: 0),
                        NativePointerValues(resolution: Int64.max, acceleration: 0),
                        NativePointerValues(resolution: 1, acceleration: Int64.max)] {
            XCTAssertThrowsError(try wired.target(profile: MouseProfile(), reference: invalid))
            let config = ProfileConfiguration(nagaWiredTrackingReference: invalid)
            XCTAssertThrowsError(try JSONDecoder().decode(ProfileConfiguration.self, from: JSONEncoder().encode(config)))
        }
    }

    func testFailedSharedWriteRecoversTheActualConnectionRatherThanTheReference() throws {
        let target = try bluetooth.target(profile: MouseProfile(pointerSensitivity: 0.72), reference: wired)
        var live = bluetooth; var attempts = 0
        XCTAssertThrowsError(try NativePointerTransaction.apply(before: bluetooth, target: target, write: { property, value in
            attempts += 1
            live = NativePointerValues(resolution: property == .resolution ? value : live.resolution,
                acceleration: property == .acceleration ? value : live.acceleration)
            if attempts == 1 { throw NativePointerError.writeFailed }
        }, read: { live }))
        XCTAssertEqual(live, bluetooth)
    }
}
