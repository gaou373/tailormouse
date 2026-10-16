import Foundation
import Combine
import IOKit
import IOKit.hidsystem
import TailorMouseCore
import NativeHIDBridge

/// Uses HID service properties through a dynamically resolved SPI client.
/// Parameters are per service and restored when handling stops.
final class NativePointer: ObservableObject {
    @Published private(set) var message = "Changes take effect while Running."
    @Published private(set) var systemAcceleration = 0.8
    @Published private(set) var supported = false
    private var client: IOHIDEventSystemClient?
    private struct Saved { let values: NativePointerValues }
    private var saved: [UInt64: Saved] = [:]
    private var active = false
    var configuration: () -> ProfileConfiguration = { ProfileConfiguration() }
    var profile: () -> MouseProfile = { MouseProfile() }
    var captureWiredReference: (NativePointerValues) -> Void = { _ in }
    var failed: (String) -> Void = { _ in }
    private var pending: DispatchWorkItem?
    private var timer: Timer?

    private func identity(_ service: IOHIDServiceClient) -> DeviceIdentity {
        let vendor = (IOHIDServiceClientCopyProperty(service, "VendorID" as CFString) as? NSNumber)?.intValue ?? 0
        let product = (IOHIDServiceClientCopyProperty(service, "ProductID" as CFString) as? NSNumber)?.intValue ?? 0
        let transport = IOHIDServiceClientCopyProperty(service, "Transport" as CFString) as? String ?? ""
        return DeviceIdentity(vendorID: vendor, productID: product, transport: transport, product: "")
    }
    private var usingNagaReference: Bool {
        configuration().selectedDeviceFamily == "razer.naga.pro" && configuration().nagaWiredTrackingReference != nil
    }
    private func currentServices() -> [UInt64: IOHIDServiceClient] {
        var result: [UInt64: IOHIDServiceClient] = [:]
        for service in (client.flatMap { IOHIDEventSystemClientCopyServices($0) } as? [IOHIDServiceClient]) ?? [] {
            result[Self.id(service)] = service
        }
        return result
    }

    func services() -> [IOHIDServiceClient] {
        // An unscheduled long-lived client can retain the pre-reconnect service
        // inventory. Obtain a fresh read-only snapshot before resolving devices.
        client = TMCreatePointerClient()
        guard let client else { return [] }
        let family = configuration().selectedDeviceFamily
        return ((IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? []).filter { service in
            guard IOHIDServiceClientConformsTo(service, 1, 2) != 0,
                  IOHIDServiceClientCopyProperty(service, "HIDPointerAccelerationType" as CFString) as? String == "HIDMouseAcceleration" else { return false }
            let vendor = (IOHIDServiceClientCopyProperty(service, "VendorID" as CFString) as? NSNumber)?.intValue ?? 0
            let product = (IOHIDServiceClientCopyProperty(service, "ProductID" as CFString) as? NSNumber)?.intValue ?? 0
            return (family == nil || DeviceIdentity(vendorID: vendor, productID: product, transport: "", product: "").canonicalFamily == family) && (try? Self.read(service)) != nil
        }
    }
    static func id(_ s: IOHIDServiceClient) -> UInt64 { (IOHIDServiceClientGetRegistryID(s) as? NSNumber)?.uint64Value ?? 0 }
    static func integerProperty(_ service: IOHIDServiceClient, _ key: String) -> Int64? {
        if let n = IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber { return n.int64Value }
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id(service)))
        guard entry != 0 else { return nil }; defer { IOObjectRelease(entry) }
        return (IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.int64Value
    }
    static func read(_ s: IOHIDServiceClient) throws -> NativePointerValues {
        func property(_ key: String) -> Int64? { integerProperty(s, key) }
        guard let resolution = property("HIDPointerResolution"), resolution > 0,
              let acceleration = property("HIDMouseAcceleration") else { throw NativePointerError.invalid }
        let multiplier = property("HIDPointerAccelerationMultiplier") ?? 65536
        return NativePointerValues(resolution: resolution, acceleration: acceleration, accelerationMultiplier: multiplier == 0 ? 65536 : multiplier)
    }
    static func write(_ s: IOHIDServiceClient, property: NativePointerProperty, value: Int64) throws {
        let key: String
        switch property {
        case .resolution: key = "HIDPointerResolution"
        case .accelerationMultiplier: key = "HIDPointerAccelerationMultiplier"
        case .acceleration: key = "HIDMouseAcceleration"
        }
        guard IOHIDServiceClientSetProperty(s, key as CFString, NSNumber(value: value)) else { throw NativePointerError.writeFailed }
    }
    func inspect() {
        let available = services().compactMap { try? Self.read($0) }
        supported = !available.isEmpty
        let displayed = usingNagaReference ? configuration().nagaWiredTrackingReference : available.first
        if let displayed, !active { systemAcceleration = max(0, Double(displayed.acceleration) / 65536) }
        if !active {
            message = supported ? (usingNagaReference ? "Shared tracking uses your wired USB reference. Press Start to apply it." : "Changes take effect while Running. Connect by USB cable once to establish shared Naga tracking.") : "Connect a supported mouse to adjust tracking."
        }
    }
    func start() {
        active = true; update()
        guard active else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
    }
    func edited() {
        guard active else { inspect(); return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.update() }
        pending = item; DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }
    private func update() {
        guard active else { return }
        do {
            let available = services(); supported = !available.isEmpty
            let present = Set(available.map(Self.id))
            // Restore connected devices excluded by a changed family selection.
            let connected = currentServices()
            for id in Array(saved.keys) where !present.contains(id) {
                if let service = connected[id], let original = saved[id] {
                    try NativePointerTransaction.apply(before: Self.read(service), target: original.values,
                        write: { try Self.write(service, property: $0, value: $1) }, read: { try Self.read(service) })
                }
                saved.removeValue(forKey: id)
            }
            for service in available {
                let id = Self.id(service)
                if saved[id] == nil {
                    let values = try Self.read(service)
                    saved[id] = Saved(values: values)
                    systemAcceleration = max(0, Double(values.acceleration) / 65536)
                }
            }
            // Capture once from the preferred wired connection before scaling
            // any service. Restoration snapshots stay separate per service.
            if configuration().nagaWiredTrackingReference == nil {
                let wired = available.filter {
                    let device = identity($0)
                    return device.vendorID == 0x1532 && device.productID == 0x008f && device.transport.lowercased() == "usb"
                }
                if wired.count == 1, let original = saved[Self.id(wired[0])], original.values.isValidReference {
                    captureWiredReference(original.values)
                }
            }
            let selectedProfile = profile()
            let reference = configuration().nagaWiredTrackingReference
            for service in available {
                let id = Self.id(service)
                guard let original = saved[id] else { continue }
                let shared = identity(service).canonicalFamily == "razer.naga.pro" ? reference : nil
                let interval = Self.integerProperty(service, "ReportInterval").flatMap { Int(exactly: $0) }
                let target = try original.values.target(profile: selectedProfile, reference: shared, device: identity(service), reportInterval: interval)
                if let shared { systemAcceleration = max(0, Double(shared.acceleration) / 65536) }
                // Receiver services may survive a physical transport switch.
                // Read current values even if the desired target is unchanged.
                let before = try Self.read(service)
                guard before != target else { continue }
                try NativePointerTransaction.apply(before: before, target: target,
                    write: { try Self.write(service, property: $0, value: $1) }, read: { try Self.read(service) })
            }
            message = supported ? (usingNagaReference ? "Shared tracking enabled for USB, receiver and Bluetooth. Stop restores each connection's original tracking." : "Live tracking enabled. Connect by USB cable once to establish shared Naga tracking.") : "Waiting for a supported mouse."
        } catch {
            stop(); message = "Tracking could not be verified. Original settings were restored where available."
            failed(message)
        }
    }
    func stop() {
        active = false; pending?.cancel(); pending = nil; timer?.invalidate(); timer = nil
        // Retained clients can report pre-write values. Restore and verify on
        // a fresh service snapshot; disconnected services need no writes.
        client = TMCreatePointerClient()
        let connected = currentServices()
        var restoreFailed = client == nil && !saved.isEmpty
        for (id, original) in saved {
            guard let service = connected[id] else { continue }
            do {
                let before = try Self.read(service)
                try NativePointerTransaction.apply(before: before, target: original.values,
                    write: { try Self.write(service, property: $0, value: $1) }, read: { try Self.read(service) })
            } catch { restoreFailed = true }
        }
        saved.removeAll()
        message = restoreFailed ? "Some tracking settings could not be restored; reconnect the mouse." : "Original tracking restored."
    }
}
