import Foundation
import Combine
import ApplicationServices
import IOKit
import IOKit.hid
import TailorMouseCore

/// A single shared control-interface session. No input callbacks, seizure,
/// keyboard programming, permission prompts or cursor-position manipulation.
final class NagaDPISession {
    let device: IOHIDDevice
    let registryID: UInt64
    let location: Int
    init() throws {
        guard CGPreflightListenEventAccess() else {
            throw Self.error("Input Monitoring approval is needed to read the mouse. Reopen TailorMouse after approving it.")
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x1532, kIOHIDProductIDKey: 0x008f] as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        func property(_ d: IOHIDDevice, _ key: String) -> Int {
            (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        let locations = Set(devices.map { property($0, kIOHIDLocationIDKey) })
        let controls = devices.filter { property($0, kIOHIDMaxFeatureReportSizeKey) == 90 }
        guard locations.count == 1, controls.count == 1, let control = controls.first else {
            throw Self.error("Connect one original Naga Pro by USB, then click Read from mouse. Bluetooth and receiver DPI control is unavailable.")
        }
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(control), &id) == KERN_SUCCESS,
              id != 0 else { throw Self.error("The USB control interface could not be identified.") }
        guard IOHIDDeviceOpen(control, 0) == kIOReturnSuccess else { throw Self.error("The USB control interface could not be opened.") }
        device = control; registryID = id; location = property(control, kIOHIDLocationIDKey)
    }
    deinit { IOHIDDeviceClose(device, 0) }
    static func error(_ message: String) -> NSError {
        NSError(domain: "TailorMouse.DPI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func send(_ bytes: [UInt8]) throws {
        let result = bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { throw Self.error("The DPI request failed (\(result)).") }
    }
    func read(storage: UInt8 = 0) throws -> NagaDPI {
        try send(NagaDPIProtocol.read(storage: storage))
        for _ in 0..<8 {
            usleep(35_000)
            var bytes = [UInt8](repeating: 0, count: 90); var length = 90
            let result = bytes.withUnsafeMutableBufferPointer {
                IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &length)
            }
            if result == kIOReturnSuccess, length == 90,
               let dpi = try? NagaDPIProtocol.parse(bytes, storage: storage) { return dpi }
        }
        throw NagaDPIError.invalidResponse
    }
    func write(_ dpi: NagaDPI) throws {
        try send(NagaDPIProtocol.write(dpi))
        // The Naga can apply a command without returning its ACK. A separate
        // validated GET, performed by the transaction, is the success criterion.
        usleep(80_000)
    }
    func backup(_ dpi: NagaDPI, directory: URL) throws -> URL {
        struct Record: Codable { let registryID: UInt64; let location: Int; let dpi: NagaDPI; let createdAt: Date }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("naga-live-dpi-\(UUID().uuidString).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Record(registryID: registryID, location: location, dpi: dpi, createdAt: Date()))
        // Create privately before writing any device data; a backup failure
        // aborts the transaction before its first hardware write.
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw Self.error("The previous DPI could not be backed up.")
        }
        let file = try FileHandle(forWritingTo: url)
        try file.write(contentsOf: data); try file.synchronize(); try file.close()
        guard try Data(contentsOf: url) == data else { throw Self.error("DPI backup verification failed.") }
        return url
    }
}

final class NagaSensitivity: ObservableObject {
    var hardwareEnabled = true
    @Published var requestedDPI = 3200.0
    @Published private(set) var current: NagaDPI?
    @Published private(set) var busy = false
    @Published private(set) var message = "Read the wired mouse's current sensitivity before applying a change."
    @Published private(set) var canRestore = false
    private let queue = DispatchQueue(label: "dev.tailormouse.dpi")
    private var deviceID: UInt64?
    private var previous: NagaDPI?
    private var applied: NagaDPI?
    private let backups = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TailorMouse/Hardware Backups", isDirectory: true)

    func refresh() {
        guard hardwareEnabled, !busy else { return }
        busy = true; message = "Reading USB sensitivity…"
        queue.async { [weak self] in
            do {
                let session = try NagaDPISession(); let dpi = try session.read(); let id = session.registryID
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.deviceID != id { self.previous = nil; self.applied = nil }
                    self.deviceID = id; self.current = dpi; self.requestedDPI = Double(dpi.x)
                    self.canRestore = self.previous != nil && self.applied == dpi
                    self.busy = false; self.message = "Current mouse sensitivity: X \(dpi.x), Y \(dpi.y) DPI."
                }
            } catch {
                DispatchQueue.main.async {
                    self?.busy = false; self?.current = nil; self?.deviceID = nil; self?.canRestore = false
                    self?.message = error.localizedDescription
                }
            }
        }
    }
    func apply() {
        guard requestedDPI.isFinite, (100...20000).contains(requestedDPI),
              let target = try? NagaDPI(x: Int(requestedDPI.rounded()), y: Int(requestedDPI.rounded())) else {
            message = "Enter a DPI between 100 and 20000."; return
        }
        change(to: target, restoring: false)
    }
    func restore() {
        guard let previous else { return }
        change(to: previous, restoring: true)
    }
    private func change(to target: NagaDPI, restoring: Bool) {
        guard hardwareEnabled, !busy, current != nil, let expectedID = deviceID else { return }
        let expectedApplied = applied
        busy = true; message = "Applying and verifying USB sensitivity…"
        let backups = backups
        queue.async { [weak self] in
            do {
                let session = try NagaDPISession()
                guard session.registryID == expectedID else {
                    throw NagaDPISession.error("The mouse reconnected. Read from mouse before applying a change.")
                }
                let before = try session.read()
                guard !restoring || before == expectedApplied else {
                    throw NagaDPISession.error("Sensitivity changed since the last Apply. Read from mouse before making another change.")
                }
                try NagaDPITransaction.apply(before: before, target: target,
                    backup: { _ = try session.backup(before, directory: backups) },
                    write: session.write, read: { try session.read() })
                DispatchQueue.main.async {
                    guard let self else { return }
                    if before != target { self.previous = restoring ? nil : before; self.applied = restoring ? nil : target }
                    self.current = target; self.requestedDPI = Double(target.x)
                    self.canRestore = self.previous != nil && self.applied == target
                    self.busy = false; self.message = "Verified on mouse: X \(target.x), Y \(target.y) DPI."
                }
            } catch {
                DispatchQueue.main.async {
                    self?.busy = false; self?.current = nil; self?.canRestore = false
                    self?.message = error.localizedDescription
                }
            }
        }
    }
}
