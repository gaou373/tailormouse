import Foundation

public struct NagaDPI: Codable, Equatable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) throws {
        guard (100...20000).contains(x), (100...20000).contains(y) else {
            throw NagaDPIError.invalidValue
        }
        self.x = x; self.y = y
    }
}

public enum NagaDPIError: Error, LocalizedError {
    case invalidValue, invalidResponse, readbackMismatch, recoveryFailed
    public var errorDescription: String? {
        switch self {
        case .invalidValue: return "DPI must be between 100 and 20000."
        case .invalidResponse: return "The mouse did not return a valid DPI response."
        case .readbackMismatch: return "The mouse did not confirm the requested DPI. The previous value was restored."
        case .recoveryFailed: return "DPI recovery could not be verified. Reconnect the mouse and read its DPI before continuing."
        }
    }
}

/// Independently written framing for the original wired Naga Pro, based on
/// OpenSnek 1af99c711035842e2896cd2d0b666b41dc022a1d USB_PROTOCOL.md.
/// Writes address only live storage 0; no persisted DPI/stage/button writes.
public enum NagaDPIProtocol {
    public static func checksum(_ bytes: [UInt8]) -> UInt8 {
        guard bytes.count == 90 else { return 0 }
        return bytes[2..<88].reduce(0, ^)
    }
    public static func read(storage: UInt8 = 0) -> [UInt8] {
        precondition(storage <= 1)
        return packet(command: 0x85, args: [storage, 0, 0, 0, 0, 0, 0])
    }
    public static func write(_ dpi: NagaDPI) throws -> [UInt8] {
        // Revalidate decoded values too; synthesized Codable bypasses init.
        _ = try NagaDPI(x: dpi.x, y: dpi.y)
        return packet(command: 0x05, args: [0, UInt8(dpi.x >> 8), UInt8(dpi.x & 255),
            UInt8(dpi.y >> 8), UInt8(dpi.y & 255), 0, 0])
    }
    private static func packet(command: UInt8, args: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 90)
        bytes[1] = 0x1f; bytes[5] = 7; bytes[6] = 4; bytes[7] = command
        bytes.replaceSubrange(8..<15, with: args)
        bytes[88] = checksum(bytes)
        return bytes
    }
    public static func parse(_ bytes: [UInt8], storage: UInt8 = 0) throws -> NagaDPI {
        guard storage <= 1, bytes.count == 90, bytes[0] == 2, bytes[1] == 0x1f,
              bytes[5] == 7, bytes[6] == 4, bytes[7] == 0x85, bytes[8] == storage,
              bytes[88] == checksum(bytes), bytes[89] == 0 else { throw NagaDPIError.invalidResponse }
        return try NagaDPI(x: Int(bytes[9]) << 8 | Int(bytes[10]), y: Int(bytes[11]) << 8 | Int(bytes[12]))
    }
}

/// Back up before any send; errors may follow a landed write. Always read back,
/// including recovery. No retries of the target write and no hidden mutations.
public enum NagaDPITransaction {
    public static func apply(before: NagaDPI, target: NagaDPI,
                             backup: () throws -> Void, write: (NagaDPI) throws -> Void,
                             read: () throws -> NagaDPI) throws {
        _ = try NagaDPI(x: target.x, y: target.y)
        guard target != before else { return }
        try backup()
        do {
            try write(target)
            guard try read() == target else { throw NagaDPIError.readbackMismatch }
        } catch {
            let originalError = error
            do {
                try write(before)
                guard try read() == before else { throw NagaDPIError.recoveryFailed }
            } catch { throw NagaDPIError.recoveryFailed }
            throw originalError
        }
    }
}
