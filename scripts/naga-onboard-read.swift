// Read-only vendor queries for the original wired Razer Naga Pro (1532:008f).
// IOHIDDeviceSetReport transports GET requests; no configuration SET command is allowed.
// Protocol reference: OpenSnek 1af99c711035842e2896cd2d0b666b41dc022a1d,
// docs/protocol/USB_PROTOCOL.md. Independently written diagnostic, not app startup code.
import Foundation
import ApplicationServices
import IOKit
import IOKit.hid

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
func crc(_ bytes: [UInt8]) -> UInt8 { bytes[2..<88].reduce(0, ^) }
func request(_ commandClass: UInt8, _ command: UInt8, _ arguments: [UInt8]) -> [UInt8] {
    // Closed allowlist, including exact argument lengths and query targets.
    let valid = (commandClass == 0 && command == 0x84 && arguments == [0, 0]) ||
        (commandClass == 4 && command == 0x85 && arguments == [0, 0, 0, 0, 0, 0, 0]) ||
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

func query(_ device: IOHIDDevice, _ commandClass: UInt8, _ command: UInt8, _ arguments: [UInt8]) throws -> [UInt8] {
    let packet = request(commandClass, command, arguments)
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

if CommandLine.arguments.contains("--self-test") {
    let active = request(5, 0x84, [0])
    assert(active.count == 90 && active[5] == 1 && active[88] == 0x80)
    let binding = request(2, 0x8c, [0, 0x49, 0, 0, 0, 0, 0, 0, 0, 0])
    assert(binding[9] == 0x49 && binding[88] == 0xcd)
    print("Read-request framing checks passed; no devices opened.")
    exit(0)
}

guard CGPreflightListenEventAccess() else {
    print("Existing input-listen approval unavailable; no permission requested.")
    exit(2)
}
let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x1532, kIOHIDProductIDKey: 0x008f] as CFDictionary)
let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
guard !devices.isEmpty, Set(devices.map { property($0, kIOHIDLocationIDKey) }).count == 1 else {
    print("Expected exactly one wired Naga Pro connection; no request sent.")
    exit(2)
}
let candidates = devices.filter { property($0, kIOHIDMaxFeatureReportSizeKey) >= 90 }
guard candidates.count == 1, let device = candidates.first else {
    print("Expected one 90-byte control interface; found \(candidates.count). No request sent.")
    for d in devices { print("INTERFACE usage=\(property(d, kIOHIDPrimaryUsagePageKey)):\(property(d, kIOHIDPrimaryUsageKey)) feature=\(property(d, kIOHIDMaxFeatureReportSizeKey))") }
    exit(2)
}
let opened = IOHIDDeviceOpen(device, 0) // Shared; never seize input.
guard opened == kIOReturnSuccess else { print("Shared open failed: \(opened). No request sent."); exit(2) }
defer { IOHIDDeviceClose(device, 0) }
do {
    let dpi = try query(device, 4, 0x85, [0, 0, 0, 0, 0, 0, 0])
    print("LIVE_DPI x=\(Int(dpi[9]) << 8 | Int(dpi[10])) y=\(Int(dpi[11]) << 8 | Int(dpi[12]))")
    let mode = try query(device, 0, 0x84, [0, 0])
    print("MODE args=\(hex(Array(mode[8..<10])))")
    let active = try query(device, 5, 0x84, [0])
    let profile = active[8]
    guard (1...5).contains(profile) else { throw NSError(domain: "UnexpectedActiveProfile", code: Int(profile)) }
    print("ACTIVE_PROFILE \(profile)")
    // Compare effective assignments with the currently selected persistent bank.
    for bank: UInt8 in [0, profile] {
        for slot: UInt8 in [0x40, 0x49, 0x4a, 0x4b] {
            let response = try query(device, 2, 0x8c, [bank, slot, 0, 0, 0, 0, 0, 0, 0, 0])
            guard response[5] >= 10, response[8] == bank, response[9] == slot else {
                throw NSError(domain: "BindingEchoMismatch", code: Int(slot))
            }
            // Naga Pro's stored layer byte does not necessarily echo the requested layer.
            print("BINDING profile=\(bank) side=\(Int(slot)-0x40+1) storedLayer=\(response[10]) block=\(hex(Array(response[11..<18])))")
        }
    }
    print("FINISHED: only live DPI, device-mode, active-profile and button GET queries sent.")
} catch {
    print("STOPPED: \(error). No settings write or profile selection attempted.")
    exit(3)
}
