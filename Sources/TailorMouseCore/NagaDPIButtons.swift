import Foundation

/// Logical inputs separate from side-panel numbers and ordinary mouse clicks.
public enum NagaDPIButton: Int, CaseIterable {
    case up = 112, down = 113
    public var title: String { self == .up ? "DPI Up" : "DPI Down" }
    public var slot: UInt8 { self == .up ? 12 : 11 }
    public var usage: UInt8 { self == .up ? 0x68 : 0x69 }
    public var keyCode: UInt16 { self == .up ? 105 : 107 }
    /// Original-Naga physical slot writes/readbacks are verified; Bluetooth is excluded.
    public static let remappingAvailable = true
    public static func supports(_ identity: DeviceIdentity) -> Bool {
        identity.vendorID == 0x1532 && [0x008f, 0x0090].contains(identity.productID) && identity.transport.lowercased() == "usb"
    }
}

public extension NagaKeyboardLayout {
    var hasDPIButtonAliasConflict: Bool {
        let keys = Set(NagaDPIButton.allCases.map(\.keyCode))
        return keyOverrides.keys.contains { UInt16($0).map { keys.contains($0) } ?? false } ||
            sequences.contains { !keys.isDisjoint(with: $0.keyCodes) }
    }
    /// Runtime-only aliases. Do not overwrite the user's side-panel calibration.
    func includingDPIButtons(_ enabled: Bool) -> Self {
        guard NagaDPIButton.remappingAvailable, enabled, !hasDPIButtonAliasConflict else { return self }
        var result = self
        for button in NagaDPIButton.allCases { result.keyOverrides[String(button.keyCode)] = button.rawValue }
        return result
    }
}

public struct NagaDPIButtonBinding: Codable, Equatable {
    public let slot: UInt8
    public let block: [UInt8]
    public init(slot: UInt8, block: [UInt8]) { self.slot = slot; self.block = block }
    public var isValid: Bool { [UInt8(9), 10, 11, 12].contains(slot) && block.count == 7 && block[1] <= 5 }
    /// Verified physical top slots. These must never use the scroll-wheel slots.
    public static var targets: [Self] {
        NagaDPIButton.allCases.map { Self(slot: $0.slot, block: [2,2,0,$0.usage,0,0,0]) }
    }
    /// Historical 0.4.3/0.4.4 wheel assignments, used only to recognize recovery ownership.
    public static var legacyTargets: [Self] {
        [Self(slot: 9, block: [2,2,0,0x68,0,0,0]), Self(slot: 10, block: [2,2,0,0x69,0,0,0])]
    }
}
public enum NagaDPIButtonError: Error, LocalizedError {
    case invalid, readback, conflict, recovery
    public var errorDescription: String? {
        switch self {
        case .invalid: return "Invalid DPI-button request or response."
        case .readback: return "DPI-button assignment did not match its readback."
        case .conflict: return "DPI-button assignments changed outside TailorMouse. They were left untouched; the recovery backup is retained."
        case .recovery: return "DPI-button recovery is incomplete. Reconnect the same mouse and use Restore DPI Buttons before remapping again."
        }
    }
}

/// Original framing based on OpenSnek's published Naga USB protocol. Only the
/// normal live layer (bank 0) and physical DPI slots may be programmed.
/// Legacy wheel slots remain accessible for ownership-checked recovery only.
public enum NagaDPIButtonProtocol {
    public static func checksum(_ bytes: [UInt8]) -> UInt8 { bytes[2..<88].reduce(0, ^) }
    public static func read(slot: UInt8) throws -> [UInt8] {
        guard [UInt8(9), 10, 11, 12].contains(slot) else { throw NagaDPIButtonError.invalid }
        return packet(command: 0x8c, arguments: [0, slot, 0, 0, 0, 0, 0, 0, 0, 0])
    }
    public static func write(_ binding: NagaDPIButtonBinding) throws -> [UInt8] {
        guard binding.isValid, !NagaDPIButtonBinding.legacyTargets.contains(binding) else { throw NagaDPIButtonError.invalid }
        return packet(command: 0x0c, arguments: [0, binding.slot, 0] + binding.block)
    }
    private static func packet(command: UInt8, arguments: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 90)
        bytes[1] = 0x1f; bytes[5] = 10; bytes[6] = 2; bytes[7] = command
        bytes.replaceSubrange(8..<18, with: arguments); bytes[88] = checksum(bytes)
        return bytes
    }
    public static func parse(_ bytes: [UInt8], slot: UInt8) throws -> NagaDPIButtonBinding {
        guard [UInt8(9), 10, 11, 12].contains(slot), bytes.count == 90,
              bytes[0] == 2, bytes[1] == 0x1f, bytes[5] == 10, bytes[6] == 2, bytes[7] == 0x8c,
              bytes[8] == 0, bytes[9] == slot, bytes[88] == checksum(bytes), bytes[89] == 0 else { throw NagaDPIButtonError.invalid }
        // Byte 10 is the stored layer flag, not a requested-layer echo on Naga.
        let binding = NagaDPIButtonBinding(slot: slot, block: Array(bytes[11..<18]))
        guard binding.isValid else { throw NagaDPIButtonError.invalid }
        return binding
    }
}

/// Journal before the first write, include a failed/possibly-landed write in
/// rollback, and compare ownership before normal restoration.
public enum NagaDPIButtonTransaction {
    public static func validOriginals(_ originals: [NagaDPIButtonBinding]) -> Bool {
        originals.count == 2 && [[UInt8(9),10], [11,12]].contains { Set(originals.map(\.slot)) == Set($0) } && originals.allSatisfy(\.isValid)
    }
    public static func apply(originals: [NagaDPIButtonBinding], backup: () throws -> Void,
                             write: (NagaDPIButtonBinding) throws -> Void) throws {
        guard validOriginals(originals), Set(originals.map(\.slot)) == [11,12] else { throw NagaDPIButtonError.invalid }
        guard originals.allSatisfy({ !NagaDPIButtonBinding.targets.contains($0) }) else { throw NagaDPIButtonError.recovery }
        try backup()
        var attempted: [UInt8] = []
        do {
            for target in NagaDPIButtonBinding.targets {
                attempted.append(target.slot); try write(target)
            }
        } catch {
            let originalError = error
            var failed = false
            for slot in attempted.reversed() {
                do { try write(originals.first { $0.slot == slot }!) } catch { failed = true }
            }
            if failed { throw NagaDPIButtonError.recovery }
            throw originalError
        }
    }
    public static func restore(originals: [NagaDPIButtonBinding], read: (UInt8) throws -> NagaDPIButtonBinding,
                               write: (NagaDPIButtonBinding) throws -> Void) throws {
        guard validOriginals(originals) else { throw NagaDPIButtonError.invalid }
        var conflict = false; var failed = false
        for original in originals.reversed() {
            do {
                let current = try read(original.slot)
                if current == original { continue }
                guard (NagaDPIButtonBinding.targets + NagaDPIButtonBinding.legacyTargets).contains(current) else { conflict = true; continue }
                try write(original)
            } catch { failed = true }
        }
        if failed { throw NagaDPIButtonError.recovery }
        if conflict { throw NagaDPIButtonError.conflict }
    }
}
