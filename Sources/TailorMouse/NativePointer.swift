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
    private struct Saved { let service: IOHIDServiceClient; let values: NativePointerValues }
    private var saved: [UInt64: Saved] = [:]
    private var active = false
    var configuration: () -> ProfileConfiguration = { ProfileConfiguration() }
    var profile: () -> MouseProfile = { MouseProfile() }
    var failed: (String) -> Void = { _ in }
    private var pending: DispatchWorkItem?
    private var timer: Timer?
    private var signature: [UInt64: NativePointerValues] = [:]

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
    static func read(_ s: IOHIDServiceClient) throws -> NativePointerValues {
        func property(_ key: String) -> Int64? {
            if let n = IOHIDServiceClientCopyProperty(s, key as CFString) as? NSNumber { return n.int64Value }
            let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id(s)))
            guard entry != 0 else { return nil }; defer { IOObjectRelease(entry) }
            return (IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.int64Value
        }
        guard let resolution = property("HIDPointerResolution"), resolution > 0,
              let acceleration = property("HIDMouseAcceleration") else { throw NativePointerError.invalid }
        return NativePointerValues(resolution: resolution, acceleration: acceleration)
    }
    static func write(_ s: IOHIDServiceClient, property: NativePointerProperty, value: Int64) throws {
        let key = property == .resolution ? "HIDPointerResolution" : "HIDMouseAcceleration"
        guard IOHIDServiceClientSetProperty(s, key as CFString, NSNumber(value: value)) else { throw NativePointerError.writeFailed }
    }
    func inspect() {
        let available = services().compactMap { try? Self.read($0) }
        supported = !available.isEmpty
        if let first = available.first, !active { systemAcceleration = max(0, Double(first.acceleration) / 65536) }
        if !active { message = supported ? "Changes take effect while Running. Stop restores your original tracking." : "Connect a supported mouse to adjust tracking." }
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
            let connected = Set(((client.flatMap { IOHIDEventSystemClientCopyServices($0) } as? [IOHIDServiceClient]) ?? []).map(Self.id))
            for id in Array(saved.keys) where !present.contains(id) {
                if connected.contains(id), let original = saved[id] {
                    try NativePointerTransaction.apply(before: Self.read(original.service), target: original.values,
                        write: { try Self.write(original.service, property: $0, value: $1) }, read: { try Self.read(original.service) })
                }
                saved.removeValue(forKey: id); signature.removeValue(forKey: id)
            }
            for service in available {
                let id = Self.id(service)
                if saved[id] == nil {
                    let values = try Self.read(service)
                    saved[id] = Saved(service: service, values: values)
                    systemAcceleration = max(0, Double(values.acceleration) / 65536)
                }
                guard let original = saved[id] else { continue }
                let target = try original.values.target(profile: profile())
                guard signature[id] != target else { continue }
                let before = try Self.read(service)
                try NativePointerTransaction.apply(before: before, target: target,
                    write: { try Self.write(service, property: $0, value: $1) }, read: { try Self.read(service) })
                signature[id] = target
            }
            message = supported ? "Live tracking enabled. Stop restores your original tracking." : "Waiting for a supported mouse."
        } catch {
            stop(); message = "Tracking could not be verified. Original settings were restored where available."
            failed(message)
        }
    }
    func stop() {
        active = false; pending?.cancel(); pending = nil; timer?.invalidate(); timer = nil
        var restoreFailed = false
        for original in saved.values {
            do {
                let before = try Self.read(original.service)
                try NativePointerTransaction.apply(before: before, target: original.values,
                    write: { try Self.write(original.service, property: $0, value: $1) }, read: { try Self.read(original.service) })
            } catch { restoreFailed = true }
        }
        saved.removeAll(); signature.removeAll()
        message = restoreFailed ? "Some tracking settings could not be restored; reconnect the mouse." : "Original tracking restored."
    }
}
