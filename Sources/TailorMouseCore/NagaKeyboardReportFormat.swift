import Foundation

/// Original Naga Pro and descriptor-backed HyperSpeed receiver formats. Normalizes only
/// their side-key snapshots; other devices and report formats are excluded.
public enum NagaKeyboardReportFormat: Equatable {
    case usbBoot, usbExtended, bluetooth
    public init?(identity: DeviceIdentity) {
        guard identity.vendorID == 0x1532 else { return nil }
        let transport = identity.transport.lowercased()
        if [0x008f, 0x0090, 0x00b4].contains(identity.productID), transport == "usb" { self = .usbBoot }
        else if identity.productID == 0x0092, transport.contains("bluetooth") { self = .bluetooth }
        else { return nil }
    }
    /// HyperSpeed exposes both an eight-byte boot interface and a separate
    /// report-1 keyboard with fourteen key slots (16 bytes including report ID).
    public static func select(identity: DeviceIdentity, keyboardReportIDs: Set<UInt32>) -> Self? {
        guard let standard = Self(identity: identity) else { return nil }
        if keyboardReportIDs.contains(standard.reportID) { return standard }
        if identity.productID == 0x00b4, keyboardReportIDs.contains(1) { return .usbExtended }
        return nil
    }
    public var reportID: UInt32 {
        switch self { case .usbBoot: return 0; case .usbExtended: return 1; case .bluetooth: return 6 }
    }
    /// The existing snapshot decoder uses the observed Bluetooth report marker.
    public func canonical(reportID: UInt32, bytes: [UInt8]) -> [UInt8]? {
        guard reportID == self.reportID else { return nil }
        switch self {
        case .usbBoot:
            guard bytes.count == 8, bytes[1] == 0 else { return nil }
            return [6, bytes[0]] + bytes.dropFirst(2)
        case .usbExtended:
            guard bytes.count == 16, bytes[0] == 1 else { return nil }
            return [6] + bytes.dropFirst()
        case .bluetooth:
            guard (8...9).contains(bytes.count), bytes[0] == 6 else { return nil }
            return bytes
        }
    }
    /// Read-only fallback for nested IORegistry input element metadata.
    public static func keyboardReportIDs(in elements: [[String: Any]]) -> Set<UInt32> {
        var result: Set<UInt32> = []
        for element in elements {
            if let page = element["UsagePage"] as? NSNumber, page.intValue == 7,
               let type = element["Type"] as? NSNumber, (1...4).contains(type.intValue),
               let report = element["ReportID"] as? NSNumber {
                result.insert(report.uint32Value)
            }
            result.formUnion(keyboardReportIDs(in: element["Elements"] as? [[String: Any]] ?? []))
        }
        return result
    }
    /// Ownership is per physical connection, covering separate composite
    /// interfaces without treating an unrelated keyboard as part of the mouse.
    public static func owns(_ device: DeviceEndpoint, endpoints: [DeviceEndpoint]) -> Bool {
        guard device.identity.supportsNagaKeyboard else { return false }
        return endpoints.contains { $0.connectionID == device.connectionID }
    }
}
