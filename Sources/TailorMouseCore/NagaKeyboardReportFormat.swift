import Foundation

/// Exact original-Naga keyboard formats observed on this Mac. Normalizes only
/// their side-key snapshots; other devices and report formats are excluded.
public enum NagaKeyboardReportFormat: Equatable {
    case usbBoot, bluetooth
    public init?(identity: DeviceIdentity) {
        guard identity.vendorID == 0x1532 else { return nil }
        let transport = identity.transport.lowercased()
        if [0x008f, 0x0090].contains(identity.productID), transport == "usb" { self = .usbBoot }
        else if identity.productID == 0x0092, transport.contains("bluetooth") { self = .bluetooth }
        else { return nil }
    }
    public var reportID: UInt32 { self == .usbBoot ? 0 : 6 }
    /// The existing snapshot decoder uses the observed Bluetooth report marker.
    public func canonical(reportID: UInt32, bytes: [UInt8]) -> [UInt8]? {
        guard reportID == self.reportID else { return nil }
        switch self {
        case .usbBoot:
            guard bytes.count == 8, bytes[1] == 0 else { return nil }
            return [6, bytes[0]] + bytes.dropFirst(2)
        case .bluetooth:
            guard (8...9).contains(bytes.count), bytes[0] == 6 else { return nil }
            return bytes
        }
    }
    /// Ownership is per physical connection, covering separate composite
    /// interfaces without treating an unrelated keyboard as part of the mouse.
    public static func owns(_ device: DeviceEndpoint, endpoints: [DeviceEndpoint]) -> Bool {
        guard device.identity.canonicalFamily == "razer.naga.pro" else { return false }
        return endpoints.contains { $0.connectionID == device.connectionID }
    }
}
