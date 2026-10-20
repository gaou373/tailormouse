import Foundation
import Combine
import ApplicationServices
import IOKit
import IOKit.hid
import TailorMouseCore

/// Live-only USB/receiver control. Never selects a profile or writes a stored bank.
private final class NagaDPIButtonSession {
    let device: IOHIDDevice
    let registryID: UInt64
    let product: Int
    let location: Int
    let serial: String
    static func number(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }
    static func discover(existing: [UInt64: NagaDPIButtonSession] = [:]) throws -> [NagaDPIButtonSession] {
        guard CGPreflightListenEventAccess() else { throw error("Input Monitoring approval is needed for DPI-button remapping.") }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(manager, [0x008f, 0x0090].map {
            [kIOHIDVendorIDKey: 0x1532, kIOHIDProductIDKey: $0]
        } as CFArray)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        return try devices.filter {
            number($0, kIOHIDMaxFeatureReportSizeKey) == 90 &&
            (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String)?.lowercased() == "usb"
        }.map { device in
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
            return try existing[id] ?? NagaDPIButtonSession(device)
        }
    }
    private init(_ device: IOHIDDevice) throws {
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id) == KERN_SUCCESS,
              id != 0, Self.number(device, kIOHIDLocationIDKey) != 0,
              IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { throw Self.error("The Naga DPI-button interface could not be opened.") }
        self.device = device; registryID = id
        product = Self.number(device, kIOHIDProductIDKey); location = Self.number(device, kIOHIDLocationIDKey)
        serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
    }
    deinit { IOHIDDeviceClose(device, 0) }
    static func error(_ message: String) -> NSError { NSError(domain: "TailorMouse.DPIButtons", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    private func send(_ bytes: [UInt8]) throws {
        let result = bytes.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count) }
        guard result == kIOReturnSuccess else { throw Self.error("The DPI-button request failed (\(result)).") }
    }
    private func get() -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: 90); var length = 90
        let result = bytes.withUnsafeMutableBufferPointer { IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &length) }
        return result == kIOReturnSuccess && length == 90 ? bytes : nil
    }
    private func requireNormalMode() throws {
        var request = [UInt8](repeating: 0, count: 90)
        request[1] = 0x1f; request[5] = 2; request[7] = 0x84
        request[88] = NagaDPIButtonProtocol.checksum(request)
        try send(request)
        for _ in 0..<6 {
            usleep(35_000)
            if let b = get(), b[0] == 2, b[1] == 0x1f, b[5] == 2, b[6] == 0, b[7] == 0x84,
               b[88] == NagaDPIButtonProtocol.checksum(b), b[89] == 0 {
                guard b[8] == 0, b[9] == 0 else { throw Self.error("DPI-button remapping requires the mouse's normal onboard mode. No mode change was made.") }
                return
            }
        }
        throw Self.error("The Naga onboard mode could not be verified.")
    }
    func activeProfile() throws -> UInt8 {
        var request = [UInt8](repeating: 0, count: 90)
        request[1] = 0x1f; request[5] = 1; request[6] = 5; request[7] = 0x84
        request[88] = NagaDPIButtonProtocol.checksum(request)
        try send(request)
        for _ in 0..<6 {
            usleep(35_000)
            if let bytes = get(), let profile = try NagaDPIButtonProtocol.activeProfileReply(bytes, product: product) { return profile }
        }
        throw Self.error("The active Naga onboard profile could not be verified.")
    }
    func read(_ slot: UInt8) throws -> NagaDPIButtonBinding {
        try send(NagaDPIButtonProtocol.read(slot: slot))
        for _ in 0..<6 {
            usleep(35_000)
            if let bytes = get(), let binding = try? NagaDPIButtonProtocol.parse(bytes, slot: slot) { return binding }
        }
        throw NagaDPIButtonError.invalid
    }
    func write(_ binding: NagaDPIButtonBinding, profile: UInt8) throws {
        try requireNormalMode()
        guard try activeProfile() == profile else { throw NagaDPIButtonError.recovery }
        try send(NagaDPIButtonProtocol.write(binding))
        usleep(100_000)
        guard try read(binding.slot) == binding else { throw NagaDPIButtonError.readback }
        guard try activeProfile() == profile else { throw NagaDPIButtonError.recovery }
    }
}

/// A private durable lease survives a crash or unplug. Recovery checks the same
/// product/location/serial/profile and restores only blocks still owned by us.
final class NagaDPIButtons: ObservableObject {
    var hardwareEnabled = true
    @Published private(set) var message = "Enable while stopped, then start handling. Physical DPI Up/Down use your mappings over USB cable or receiver."
    @Published private(set) var busy = false
    var failed: (String) -> Void = { _ in }
    private struct Journal: Codable {
        let product: Int; let location: Int; let serial: String; let profile: UInt8
        let originals: [NagaDPIButtonBinding]
        let mappingVersion: Int?
        func matches(_ session: NagaDPIButtonSession) -> Bool {
            product == session.product && location == session.location && serial == session.serial &&
            (1...5).contains(profile) && [1,2].contains(mappingVersion ?? 1) && NagaDPIButtonTransaction.validOriginals(originals)
        }
    }
    private struct Lease { let session: NagaDPIButtonSession; let journal: Journal; let url: URL }
    private let queue = NagaControlQueue.shared
    private var leases: [UInt64: Lease] = [:] // queue confined
    private var timer: Timer?
    private var active = false
    private var generation = 0
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TailorMouse/DPI Button Recovery", isDirectory: true)

    private func journalURL(_ session: NagaDPIButtonSession) -> URL {
        directory.appendingPathComponent("\(session.product)-\(session.location).json")
    }
    private func recover(_ session: NagaDPIButtonSession, journal: Journal, url: URL) throws {
        guard journal.matches(session), try session.activeProfile() == journal.profile else { throw NagaDPIButtonError.recovery }
        try NagaDPIButtonTransaction.restore(originals: journal.originals, physicalMappingVersion: journal.mappingVersion ?? 1, read: session.read, write: { try session.write($0, profile: journal.profile) })
        try FileManager.default.removeItem(at: url)
    }
    private func recoverExisting(_ session: NagaDPIButtonSession) throws {
        let url = journalURL(session)
        if FileManager.default.fileExists(atPath: url.path) {
            let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
            try recover(session, journal: journal, url: url)
        }
    }
    private func prepare(_ session: NagaDPIButtonSession) throws -> Lease {
        try recoverExisting(session)
        let profile = try session.activeProfile()
        let originals = try NagaDPIButton.allCases.map { try session.read($0.slot) }
        let journal = Journal(product: session.product, location: session.location, serial: session.serial, profile: profile, originals: originals, mappingVersion: 2)
        let url = journalURL(session)
        do {
            try NagaDPIButtonTransaction.apply(originals: originals, backup: {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                guard !FileManager.default.fileExists(atPath: url.path),
                      FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw NagaDPIButtonError.recovery }
                let data = try JSONEncoder().encode(journal)
                let file = try FileHandle(forWritingTo: url)
                try file.write(contentsOf: data); try file.synchronize(); try file.close()
                guard try Data(contentsOf: url) == data, try session.activeProfile() == profile else { throw NagaDPIButtonError.recovery }
            }, write: { try session.write($0, profile: profile) })
            guard try session.activeProfile() == profile else { throw NagaDPIButtonError.recovery }
        } catch {
            // Includes failed/landed writes and process interruption during setup.
            // Keep the journal if recovery cannot prove the original state.
            if FileManager.default.fileExists(atPath: url.path) { try? recover(session, journal: journal, url: url) }
            throw error
        }
        return Lease(session: session, journal: journal, url: url)
    }
    func start() {
        guard hardwareEnabled, !active, !busy else { return }
        active = true; generation += 1
        message = "Preparing and verifying DPI Up / DPI Down…"
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
    }
    private func poll() {
        guard active, !busy else { return }
        busy = true; let token = generation
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let sessions = try NagaDPIButtonSession.discover(existing: self.leases.mapValues(\.session))
                let present = Set(sessions.map(\.registryID))
                // An unplug leaves the durable recovery record for the next
                // connection; never send a restore to another interface.
                self.leases = self.leases.filter { present.contains($0.key) }
                var waitingReceivers = 0
                for session in sessions {
                    if let lease = self.leases[session.registryID] {
                        guard try session.activeProfile() == lease.journal.profile else { throw NagaDPIButtonError.recovery }
                    } else {
                        // A cabled mouse can leave its plugged-in receiver offline.
                        // Never suppress failures on an already-owned lease.
                        do { _ = try session.activeProfile() }
                        catch NagaDPIButtonError.receiverUnavailable { waitingReceivers += 1; continue }
                        self.leases[session.registryID] = try self.prepare(session)
                    }
                }
                let message: String
                if self.leases.isEmpty {
                    message = waitingReceivers > 0 ? "Receiver connected; waiting for its mouse. DPI mappings will resume when it reconnects." : "Connect a Naga Pro by USB cable or receiver. Bluetooth DPI-button remapping is unavailable."
                } else {
                    message = "DPI Up and DPI Down are ready. Stop restores the original assignments." + (waitingReceivers > 0 ? " The idle receiver is waiting for its mouse." : "")
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.busy = false; self.message = message
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.busy = false; self.message = message; self.failed(message)
                }
            }
        }
    }
    @discardableResult func stop() -> String? {
        guard hardwareEnabled else { return nil }
        active = false; generation += 1; timer?.invalidate(); timer = nil
        var failure: String?
        queue.sync {
            for lease in leases.values {
                do { try recover(lease.session, journal: lease.journal, url: lease.url) }
                catch { failure = error.localizedDescription }
            }
            leases.removeAll()
        }
        busy = false
        let pending = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).contains { $0.hasSuffix(".json") }
        if failure == nil && pending { failure = "Button recovery is pending. Reconnect the same mouse/profile and choose Restore Button Assignments." }
        message = failure ?? "Stopped. Original button assignments restored for connected mice."
        return failure
    }
    func restoreWhileStopped() {
        guard hardwareEnabled, !active, !busy else { return }
        busy = true; let token = generation
        queue.async { [weak self] in
            guard let self else { return }
            var message = "No connected USB/receiver wheel recovery was needed."
            do {
                for session in try NagaDPIButtonSession.discover() {
                    if FileManager.default.fileExists(atPath: self.journalURL(session).path) {
                        try self.recoverExisting(session); message = "Original button assignments restored and verified."
                    }
                }
            } catch { message = error.localizedDescription }
            let result = message
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.busy = false; self.message = result
            }
        }
    }
}
