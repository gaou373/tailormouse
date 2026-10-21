// Explicit diagnostic correction for the original wired Naga Pro (1532:008f).
// --apply changes only side 10/11 in the active bank and effective mirror.
// --restore <backup.json> restores those normal-layer function blocks.
// It backs up the original function blocks before writes and verifies every write.
// This script is never called by the app, builds, tests, or installer.
// Protocol reference: OpenSnek 1af99c711035842e2896cd2d0b666b41dc022a1d,
// docs/protocol/USB_PROTOCOL.md. Independently written diagnostic, not app startup code.
import Foundation
import ApplicationServices
import IOKit
import IOKit.hid

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
func crc(_ bytes: [UInt8]) -> UInt8 { bytes[2..<88].reduce(0, ^) }
func readRequest(_ commandClass: UInt8, _ command: UInt8, _ arguments: [UInt8]) -> [UInt8] {
    // Closed allowlist, including exact argument lengths and query targets.
    let valid = (commandClass == 0 && command == 0x84 && arguments == [0, 0]) ||
        (commandClass == 5 && command == 0x84 && arguments == [0]) ||
        (commandClass == 2 && command == 0x8c && arguments.count == 10 &&
         arguments[0] <= 5 && (0x40...0x4b).contains(arguments[1]) &&
         arguments[2] == 0 && arguments[3...].allSatisfy { $0 == 0 })
    precondition(valid, "Only bounded read commands are supported")
    var packet = [UInt8](repeating: 0, count: 90)
    packet[1] = 0x1f
    packet[5] = UInt8(arguments.count)
    packet[6] = commandClass
    packet[7] = command
    packet.replaceSubrange(8..<(8 + arguments.count), with: arguments)
    packet[88] = crc(packet)
    return packet
}

func property(_ device: IOHIDDevice, _ key: String) -> Int {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
}

func readQuery(_ device: IOHIDDevice, _ commandClass: UInt8, _ command: UInt8, _ arguments: [UInt8]) throws -> [UInt8] {
    let packet = readRequest(commandClass, command, arguments)
    let sent = packet.withUnsafeBufferPointer {
        IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count)
    }
    guard sent == kIOReturnSuccess else { throw NSError(domain: "ReadRequestTransport", code: Int(sent)) }
    for _ in 0..<6 {
        usleep(35_000)
        var response = [UInt8](repeating: 0, count: 90)
        var length = response.count
        let received = response.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &length)
        }
        guard received == kIOReturnSuccess, length == 90,
              response[1] == packet[1], response[6] == commandClass,
              response[7] == command, response[88] == crc(response),
              response[0] != 0, response[0] != 1 else { continue }
        guard response[0] == 2 else { throw NSError(domain: "FirmwareReadRejected", code: Int(response[0])) }
        return response
    }
    throw NSError(domain: "NoValidatedReadResponse", code: 1)
}

struct Binding: Codable, Equatable {
    let bank: UInt8
    let slot: UInt8
    let block: [UInt8]
}
struct Backup: Codable {
    let location: Int
    let active: UInt8
    let bindings: [Binding]
    let createdAt: Date
}
func saveBackup(_ backup: Backup, directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("naga-onboard-10-11-\(UUID().uuidString).json")
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(backup)
    try data.write(to: url, options: [.withoutOverwriting])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    let handle = try FileHandle(forWritingTo: url)
    try handle.synchronize(); try handle.close()
    guard try Data(contentsOf: url) == data else { throw NSError(domain: "BackupVerificationFailed", code: 1) }
    return url
}
func writePacket(_ binding: Binding) -> [UInt8] {
    precondition(binding.bank <= 5 && [UInt8(0x49), 0x4a].contains(binding.slot))
    precondition(binding.block.count == 7)
    var packet = [UInt8](repeating: 0, count: 90)
    packet[1] = 0x1f; packet[5] = 10; packet[6] = 2; packet[7] = 0x0c
    packet.replaceSubrange(8..<18, with: [binding.bank, binding.slot, 0] + binding.block)
    packet[88] = crc(packet)
    return packet
}
func readBinding(_ device: IOHIDDevice, _ bank: UInt8, _ slot: UInt8) throws -> Binding {
    let response = try readQuery(device, 2, 0x8c, [bank, slot, 0, 0, 0, 0, 0, 0, 0, 0])
    guard response[5] >= 10, response[8] == bank, response[9] == slot else {
        throw NSError(domain: "BindingEchoMismatch", code: Int(slot))
    }
    return Binding(bank: bank, slot: slot, block: Array(response[11..<18]))
}
func writeAndVerify(_ device: IOHIDDevice, _ binding: Binding) throws {
    let packet = writePacket(binding)
    let sent = packet.withUnsafeBufferPointer {
        IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count)
    }
    guard sent == kIOReturnSuccess else { throw NSError(domain: "WriteTransport", code: Int(sent)) }
    // Some Naga firmware applies writes without an ACK. Always read back rather than
    // treating an ACK timeout as proof that no mutation occurred.
    for _ in 0..<12 {
        usleep(40_000)
        var response = [UInt8](repeating: 0, count: 90)
        var length = response.count
        let result = response.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &length)
        }
        if result == kIOReturnSuccess, length == 90, response[1] == 0x1f,
           response[6] == 2, response[7] == 0x0c, response[88] == crc(response),
           response[0] != 0, response[0] != 1 { break }
    }
    let actual = try readBinding(device, binding.bank, binding.slot)
    guard actual == binding else { throw NSError(domain: "WriteReadbackMismatch", code: Int(binding.slot)) }
    print("VERIFIED profile=\(binding.bank) side=\(Int(binding.slot)-0x40+1) block=\(hex(binding.block))")
    fflush(stdout)
}
func transaction(_ originals: [Binding], _ desired: [Binding], write: (Binding) throws -> Void) throws {
    precondition(originals.count == desired.count)
    var attempted: [Int] = []
    do {
        for index in desired.indices {
            guard desired[index] != originals[index] else { continue }
            attempted.append(index) // Journal before sending; an error can follow a landed write.
            try write(desired[index])
        }
    } catch {
        var rollbackErrors = [String]()
        for index in attempted.reversed() {
            do { try write(originals[index]) } catch { rollbackErrors.append(String(describing: error)) }
        }
        guard rollbackErrors.isEmpty else {
            throw NSError(domain: "CorrectionAndRollbackFailed: \(rollbackErrors)", code: 1)
        }
        throw error
    }
}

if CommandLine.arguments.contains("--self-test") {
    let original = [Binding(bank: 1, slot: 0x49, block: [3, 3, 0, 0, 0, 0, 0]), Binding(bank: 1, slot: 0x4a, block: [3, 3, 1, 0, 0, 0, 0])]
    let desired = [Binding(bank: 1, slot: 0x49, block: [2, 2, 0, 0x27, 0, 0, 0]), Binding(bank: 1, slot: 0x4a, block: [2, 2, 0, 0x2d, 0, 0, 0])]
    let packet = writePacket(desired[0])
    assert(packet.count == 90 && packet[7] == 0x0c && packet[8] == 1 && packet[9] == 0x49 && packet[13] == 0 && packet[14] == 0x27 && packet[88] == crc(packet))
    var successful = [Binding]()
    try transaction(original, desired) { successful.append($0) }
    assert(successful == desired)
    var recovery = [Binding](); var calls = 0
    do {
        try transaction(original, desired) { binding in
            recovery.append(binding); calls += 1
            if calls == 2 { throw NSError(domain: "Simulated landed-write ACK failure", code: 1) }
        }
        assertionFailure("Expected failure")
    } catch { assert(recovery == desired + original.reversed()) }
    var unchangedWrites = 0
    try transaction(original, original) { _ in unchangedWrites += 1 }
    assert(unchangedWrites == 0)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tailormouse-backup-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try saveBackup(Backup(location: 1234, active: 1, bindings: original, createdAt: Date()), directory: directory)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let restored = try decoder.decode(Backup.self, from: Data(contentsOf: url))
    assert(restored.bindings == original && restored.location == 1234)
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    assert(permissions?.intValue == 0o600)
    print("Framing, correction, landed-write recovery, no-op and private backup checks passed; no devices opened.")
    exit(0)
}

let restoring: Backup?
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--restore" {
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    restoring = try decoder.decode(Backup.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
} else if CommandLine.arguments == [CommandLine.arguments[0], "--apply"] {
    restoring = nil
} else {
    print("Use --apply for single 0/minus assignments, or --restore <backup.json>. Only side 10/11 in the active original wired Naga Pro profile can be changed.")
    exit(2)
}
guard CGPreflightListenEventAccess() else { print("Existing approval unavailable; no permission requested."); exit(2) }
let running = Process(); running.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); running.arguments = ["-x", "TailorMouse"]
running.standardOutput = FileHandle.nullDevice
try running.run(); running.waitUntilExit()
guard running.terminationStatus == 1 else { print("TailorMouse must be closed before correction; no device opened."); exit(2) }
let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x1532, kIOHIDProductIDKey: 0x008f] as CFDictionary)
let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
let locations = Set(devices.map { property($0, kIOHIDLocationIDKey) })
let controls = devices.filter { property($0, kIOHIDMaxFeatureReportSizeKey) >= 90 }
guard locations.count == 1, let location = locations.first, location > 0, controls.count == 1, let device = controls.first else {
    print("Expected exactly one wired Naga Pro control interface; no command sent."); exit(2)
}
guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { print("Shared open failed; no command sent."); exit(2) }
defer { IOHIDDeviceClose(device, 0) }
do {
    let mode = try readQuery(device, 0, 0x84, [0, 0])
    guard Array(mode[8..<10]) == [0, 0] else { throw NSError(domain: "ExpectedNormalOnboardMode", code: 1) }
    let active = try readQuery(device, 5, 0x84, [0])[8]
    guard (1...5).contains(active) else { throw NSError(domain: "UnexpectedActiveProfile", code: Int(active)) }
    let banks: [UInt8] = [active, 0]
    if let restoring {
        let expected = Set(banks.flatMap { bank in [0x49, 0x4a].map { "\(bank):\($0)" } })
        let actual = Set(restoring.bindings.map { "\($0.bank):\($0.slot)" })
        guard restoring.location == location, restoring.active == active,
              restoring.bindings.count == 4, actual == expected,
              restoring.bindings.allSatisfy({ $0.block.count == 7 && $0.block[1] <= 5 }) else {
            throw NSError(domain: "BackupDeviceProfileOrScopeMismatch", code: 1)
        }
    }
    var original = [Binding](); var desired = [Binding](); var controlsBefore = [Binding]()
    for bank in banks {
        for slot: UInt8 in [0x49, 0x4a] {
            original.append(try readBinding(device, bank, slot))
            if let restoring, let target = restoring.bindings.first(where: { $0.bank == bank && $0.slot == slot }) {
                desired.append(target)
            } else {
                desired.append(Binding(bank: bank, slot: slot, block: [2, 2, 0, slot == 0x49 ? 0x27 : 0x2d, 0, 0, 0]))
            }
        }
        for slot: UInt8 in [0x40, 0x4b] { controlsBefore.append(try readBinding(device, bank, slot)) }
    }
    let backup = Backup(location: location, active: active, bindings: original, createdAt: Date())
    let backupURL = try saveBackup(backup, directory: URL(fileURLWithPath: ".local/backups"))
    print("BACKUP \(backupURL.path)"); fflush(stdout)
    guard try readQuery(device, 5, 0x84, [0])[8] == active else { throw NSError(domain: "ActiveProfileChangedBeforeWrite", code: 1) }
    try transaction(original, desired) { try writeAndVerify(device, $0) }
    do {
        guard try readQuery(device, 5, 0x84, [0])[8] == active else { throw NSError(domain: "ActiveProfileChanged", code: 1) }
        guard Array(try readQuery(device, 0, 0x84, [0, 0])[8..<10]) == [0, 0] else { throw NSError(domain: "DeviceModeChanged", code: 1) }
        for control in controlsBefore {
            guard try readBinding(device, control.bank, control.slot) == control else { throw NSError(domain: "UnrelatedBindingChanged", code: Int(control.slot)) }
        }
        for target in desired { guard try readBinding(device, target.bank, target.slot) == target else { throw NSError(domain: "FinalReadbackMismatch", code: Int(target.slot)) } }
    } catch {
        for binding in original.reversed() { try writeAndVerify(device, binding) }
        throw error
    }
    print(restoring == nil ? "CORRECTED: active profile \(active), side 10 single 0, side 11 single minus. Physical-hold test pending." : "RESTORED: backed-up normal-layer side 10/11 function blocks verified in active profile \(active) and effective mirror.")
} catch { print("STOPPED: \(error). See durable backup and VERIFIED recovery lines above."); exit(3) }

