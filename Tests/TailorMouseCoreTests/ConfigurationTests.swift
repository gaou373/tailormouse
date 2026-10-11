import XCTest
@testable import TailorMouseCore

final class ConfigurationTests: XCTestCase {
    func testV1MigrationPreservesMappingsAndOldWheelBehavior() throws {
        let old = #"{"schemaVersion":1,"defaultProfile":{"id":"12345678-1234-1234-1234-123456789ABC","name":"Default","invertWheel":true,"wheelSpeed":2,"button3":"back","button4":"copy"},"appProfiles":[]}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(ProfileConfiguration.self, from: old)
        XCTAssertEqual(config.schemaVersion, 2)
        XCTAssertEqual(config.defaultProfile.actionBinding(for: 3).action, .back)
        XCTAssertEqual(config.defaultProfile.actionBinding(for: 4).action, .copy)
        XCTAssertEqual(config.defaultProfile.horizontalWheelSpeed, 2)
        XCTAssertTrue(config.defaultProfile.invertHorizontalWheel)
        XCTAssertEqual(config.selectedDeviceFamily, "razer.naga.pro")
        XCTAssertEqual(try JSONDecoder().decode(ProfileConfiguration.self, from: JSONEncoder().encode(config)), config)
    }
    func testExplicitAllMiceSelectionSurvivesRoundTripAndFutureSchemaRejected() throws {
        let config = ProfileConfiguration(selectedDeviceFamily: nil)
        XCTAssertNil(try JSONDecoder().decode(ProfileConfiguration.self, from: JSONEncoder().encode(config)).selectedDeviceFamily)
        XCTAssertThrowsError(try JSONDecoder().decode(ProfileConfiguration.self, from: Data(#"{"schemaVersion":99}"#.utf8)))
    }
    func testInheritedApplicationProfileKeepsBindingsButNewIdentity() {
        let base = MouseProfile(wheelSpeed: 2, pointerSpeed: 1.5, bindings: ["111": ActionBinding(action: .redo)], chords: [ChordBinding(buttons: [100,101], binding: ActionBinding(action: .undo))])
        let child = base.inheritedProfile(name: "Safari", bundleIdentifier: "com.apple.Safari")
        XCTAssertNotEqual(base.id, child.id)
        XCTAssertEqual(child.bindings, base.bindings)
        XCTAssertEqual(child.chords, base.chords)
        XCTAssertEqual(child.pointerSpeed, base.pointerSpeed)
        XCTAssertEqual(child.bundleIdentifier, "com.apple.Safari")
    }
    func testNagaTransportAliasesAndUnknownIdentities() {
        for product in [0x8f, 0x90, 0x92] {
            for transport in ["USB", "Bluetooth", "Dongle"] {
                XCTAssertEqual(DeviceIdentity(vendorID: 0x1532, productID: product, transport: transport, product: "Naga Pro").canonicalFamily, "razer.naga.pro")
            }
        }
        XCTAssertEqual(DeviceIdentity(vendorID: 1, productID: 0x90, transport: "USB", product: "Naga Pro").canonicalFamily, "hid.0001.0090")
        XCTAssertEqual(DeviceIdentity(vendorID: 0x1532, productID: 0x9999, transport: "Bluetooth", product: "Naga Pro").canonicalFamily, "hid.1532.9999")
    }
    func testIndependentScrollAxesAndLargeValuesAreSafe() {
        var wheel = WheelTransformer()
        let profile = MouseProfile(invertWheel: true, wheelSpeed: 2, horizontalWheelSpeed: 0.25)
        XCTAssertEqual(wheel.transform([1,1,4], continuous: false, profile: profile), [-2,0,4])
        XCTAssertEqual(wheel.transform([1,3,4], continuous: false, profile: profile), [-2,1,4])
        let extreme = MouseProfile(wheelSpeed: 4, horizontalWheelSpeed: 4)
        XCTAssertEqual(wheel.transform([Int64.max,Int64.min], continuous: false, profile: extreme), [Int64.max,Int64.min])
    }
    func testPointerFractionsSettingsChangeAndNonFiniteInputConfiguration() {
        var pointer = PointerTransformer()
        let slow = MouseProfile(pointerSpeed: 0.25)
        XCTAssertEqual((0..<4).map { _ in pointer.transform([1,-1], profile: slow) }, [[0,0],[0,0],[0,0],[1,-1]])
        _ = pointer.transform([1,1], profile: slow)
        XCTAssertEqual(pointer.transform([1,1], profile: MouseProfile()), [1,1])
        XCTAssertEqual(pointer.transform([1,1], profile: slow), [0,0])
        var otherApp = slow
        otherApp.id = UUID()
        XCTAssertEqual(pointer.transform([1,1], profile: otherApp), [0,0])
        pointer.reset()
        XCTAssertEqual(pointer.transform([1,1], profile: slow), [0,0])
        XCTAssertEqual(MouseProfile(pointerSpeed: .infinity).safePointerSpeed, 1)
        XCTAssertEqual(MouseProfile(horizontalWheelSpeed: .nan).safeHorizontalWheelSpeed, 1)
        XCTAssertEqual(pointer.transform([Int64.max,Int64.min], profile: MouseProfile(pointerSpeed: 4)), [Int64.max,Int64.min])
    }
}
