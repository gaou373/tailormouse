import Foundation

public struct DeviceIdentity: Equatable, Codable {
    public var vendorID: Int
    public var productID: Int
    public var transport: String
    public var product: String
    public var registryID: UInt64
    public init(vendorID: Int, productID: Int, transport: String, product: String, registryID: UInt64 = 0) {
        self.vendorID = vendorID; self.productID = productID; self.transport = transport; self.product = product; self.registryID = registryID
    }
    /// Original Naga Pro transport aliases. Names alone never identify a supported device.
    public var canonicalFamily: String {
        if vendorID == 0x1532 && [0x008f, 0x0090, 0x0092].contains(productID) { return "razer.naga.pro" }
        return String(format: "hid.%04x.%04x", vendorID, productID)
    }
}

public enum NagaKeyMap {
    /// macOS virtual keycodes for the numbered bank and common onboard keypad assignments.
    private static let topRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]
    private static let keypad: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92, 82, 78, 69]
    public static func button(for keyCode: UInt16) -> Int? {
        if let offset = topRow.firstIndex(of: keyCode) { return 100 + offset }
        if let offset = keypad.firstIndex(of: keyCode) { return 100 + offset }
        return nil
    }
    public static func keyCode(for button: Int) -> UInt16? {
        guard (100...111).contains(button) else { return nil }
        return topRow[button - 100]
    }
}
