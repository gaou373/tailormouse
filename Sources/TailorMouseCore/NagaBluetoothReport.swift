import Foundation

public struct NagaRawKeyTransition {
    public let keyCode: UInt16
    public let phase: ButtonPhase
    public let modifiers: ModifierMask
}

/// Tracks only synthetic native keys actually posted by the Bluetooth path.
/// Stop/disconnect consumes this set once, preventing stranded Passthrough keys.
public struct NagaPostedKeyTracker {
    private var held: Set<UInt16> = []
    public init() {}
    public mutating func posted(keyCode: UInt16, phase: ButtonPhase) {
        if phase == .down { held.insert(keyCode) }
        if phase == .up { held.remove(keyCode) }
    }
    public mutating func takeReleases() -> [UInt16] {
        let releases = held.sorted(); held.removeAll(); return releases
    }
}

/// Original decoder for observed original-Naga Bluetooth keyboard report 6.
/// Snapshot differences preserve holds; repeated reports cannot repeat actions.
public struct NagaBluetoothReportDecoder {
    private var held: Set<UInt16> = []
    private var inherited: Set<UInt16> = []
    public init() {}
    public mutating func reset() { held.removeAll(); inherited.removeAll() }
    public mutating func prime(reportID: UInt32, bytes: [UInt8]) {
        guard let snapshot = Self.snapshot(reportID: reportID, bytes: bytes) else { return }
        held = snapshot.keys; inherited = held
    }
    public mutating func route(reportID: UInt32, bytes: [UInt8]) -> [NagaRawKeyTransition] {
        guard let snapshot = Self.snapshot(reportID: reportID, bytes: bytes) else { return [] }
        let released = held.subtracting(snapshot.keys)
        let pressed = snapshot.keys.subtracting(held)
        let output = released.subtracting(inherited).sorted().map {
            NagaRawKeyTransition(keyCode: $0, phase: .up, modifiers: snapshot.modifiers)
        } + pressed.sorted().map {
            NagaRawKeyTransition(keyCode: $0, phase: .down, modifiers: snapshot.modifiers)
        }
        inherited.subtract(released); held = snapshot.keys
        return output
    }
    public static func handles(keyCode: UInt16, layout: NagaKeyboardLayout) -> Bool {
        usageKeys.values.contains(keyCode) && (layout.button(for: keyCode) != nil ||
            layout.sequences.contains { $0.keyCodes.contains(keyCode) })
    }
    private static let usageKeys: [UInt8: UInt16] = [
        0x1e:18, 0x1f:19, 0x20:20, 0x21:21, 0x22:23, 0x23:22,
        0x24:26, 0x25:28, 0x26:25, 0x27:29, 0x2d:27, 0x2e:24, 0x28:36,
        0x59:83, 0x5a:84, 0x5b:85, 0x5c:86, 0x5d:87, 0x5e:88,
        0x5f:89, 0x60:91, 0x61:92, 0x62:82, 0x56:78, 0x57:69
    ]
    private static func snapshot(reportID: UInt32, bytes: [UInt8]) -> (keys: Set<UInt16>, modifiers: ModifierMask)? {
        guard reportID == 6, (8...9).contains(bytes.count), bytes[0] == 6 else { return nil }
        let usages = bytes.dropFirst(2)
        // Error/rollover reports are not empty snapshots: retain held keys
        // until the next valid report rather than manufacture releases.
        guard !usages.contains(where: { (1...3).contains($0) }) else { return nil }
        var modifiers = ModifierMask()
        if bytes[1] & 0x11 != 0 { modifiers.insert(.control) }
        if bytes[1] & 0x22 != 0 { modifiers.insert(.shift) }
        if bytes[1] & 0x44 != 0 { modifiers.insert(.option) }
        if bytes[1] & 0x88 != 0 { modifiers.insert(.command) }
        return (Set(usages.compactMap { usageKeys[$0] }), modifiers)
    }
}
