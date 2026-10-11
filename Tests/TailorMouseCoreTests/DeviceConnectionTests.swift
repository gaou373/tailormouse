import XCTest
@testable import TailorMouseCore

final class DeviceConnectionTests: XCTestCase {
    private func endpoint(_ id: UInt64, location: Int = 1122608, transport: String = "USB", eventService: Bool = true, senders: Set<UInt64>? = nil) -> DeviceEndpoint {
        let identity = DeviceIdentity(vendorID: 0x1532, productID: 0x008f, transport: transport, product: "Razer Naga Pro", registryID: id)
        return DeviceEndpoint(id: id, identity: identity, senderIDs: senders ?? [id + 100],
            connectionID: DeviceEndpoint.connectionID(identity: identity, locationID: location), canIdentifyEvents: eventService)
    }

    func testFourUSBInterfacesBecomeOnePhysicalRowAndRetainAllSenders() {
        let endpoints = [endpoint(1), endpoint(2), endpoint(3, eventService: false), endpoint(4)]
        let connections = DeviceConnection.grouping(endpoints)
        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections[0].endpointIDs, [1,2,3,4])
        XCTAssertTrue(connections[0].canIdentifyEvents)
        for endpoint in endpoints {
            XCTAssertEqual(DeviceEndpoint.matching(senderID: endpoint.id + 100, in: endpoints)?.id, endpoint.id)
        }
    }

    func testDifferentPhysicalMiceAndTransportsStaySeparate() {
        XCTAssertEqual(DeviceConnection.grouping([endpoint(1), endpoint(2, location: 200), endpoint(3, transport: "Bluetooth")]).count, 3)
        XCTAssertEqual(DeviceConnection.grouping([endpoint(1, location: 0), endpoint(2, location: 0)]).count, 2)
    }

    func testVirtualKeyboardUnknownZeroAndAmbiguousSourcesPassThrough() {
        let endpoints = [endpoint(1, senders: [101,999]), endpoint(2, senders: [102,999])]
        XCTAssertNil(DeviceEndpoint.matching(senderID: 0, in: endpoints))
        XCTAssertNil(DeviceEndpoint.matching(senderID: 4296084967, in: endpoints))
        XCTAssertNil(DeviceEndpoint.matching(senderID: 999, in: endpoints))
        XCTAssertEqual(DeviceEndpoint.matching(senderID: 101, in: endpoints)?.id, 1)
    }
}
