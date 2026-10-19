import Foundation

/// One HID interface, retained separately for exact event attribution.
public struct DeviceEndpoint: Identifiable, Equatable {
    public let id: UInt64
    public let identity: DeviceIdentity
    public let senderIDs: Set<UInt64>
    public let connectionID: String
    public let canIdentifyEvents: Bool

    public init(id: UInt64, identity: DeviceIdentity, senderIDs: Set<UInt64>, connectionID: String, canIdentifyEvents: Bool) {
        self.id = id; self.identity = identity; self.senderIDs = senderIDs
        self.connectionID = connectionID; self.canIdentifyEvents = canIdentifyEvents
    }

    public static func matching(senderID: UInt64, in endpoints: [DeviceEndpoint]) -> DeviceEndpoint? {
        guard senderID != 0 else { return nil }
        let matches = endpoints.filter { $0.senderIDs.contains(senderID) }
        // Never attribute a shared virtual keyboard or an ambiguous sender.
        return matches.count == 1 ? matches[0] : nil
    }

    public static func connectionID(identity: DeviceIdentity, locationID: Int) -> String {
        "\(identity.canonicalFamily):\(identity.transport):\(locationID == 0 ? String(identity.registryID) : String(locationID))"
    }
}

/// UI representation of a physical connection, rather than one row per interface.
public struct DeviceConnection: Identifiable, Equatable {
    public let id: String
    public let identity: DeviceIdentity
    public let endpointIDs: Set<UInt64>
    public let canIdentifyEvents: Bool

    public static func grouping(_ endpoints: [DeviceEndpoint]) -> [DeviceConnection] {
        Dictionary(grouping: endpoints, by: \.connectionID).map { id, members in
            let first = members.min { $0.id < $1.id }!
            return DeviceConnection(id: id, identity: first.identity,
                endpointIDs: Set(members.map(\.id)), canIdentifyEvents: members.contains { $0.canIdentifyEvents })
        }.sorted {
            if $0.identity.product == $1.identity.product { return $0.id < $1.id }
            return $0.identity.product.localizedStandardCompare($1.identity.product) == .orderedAscending
        }
    }
}
