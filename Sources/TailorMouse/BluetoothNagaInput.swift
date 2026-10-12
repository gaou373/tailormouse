import Foundation
import IOKit
import IOKit.hid
import TailorMouseCore

/// Reads only original Naga Pro Bluetooth interfaces, while handling is active.
/// Shared opens; no device seizure, feature writes, unrelated keyboard access
/// or cursor manipulation. Polling handles reconnects without stale pointers.
final class BluetoothNagaInput {
    private final class Endpoint {
        let device: IOHIDDevice
        let id: UInt64
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        weak var owner: BluetoothNagaInput?
        init(device: IOHIDDevice, id: UInt64, owner: BluetoothNagaInput) {
            self.device = device; self.id = id; self.owner = owner
        }
        deinit { buffer.deallocate() }
    }
    private var endpoints: [UInt64: Endpoint] = [:]
    var report: (UInt64, UInt32, [UInt8]) -> Void = { _, _, _ in }
    var baseline: (UInt64, [UInt8]) -> Void = { _, _ in }
    var removed: (UInt64) -> Void = { _ in }
    var failed: (String) -> Void = { _ in }
    func owns(_ id: UInt64) -> Bool { endpoints[id] != nil }
    var endpointCount: Int { endpoints.count }
    func identity(_ id: UInt64) -> DeviceEndpoint? {
        guard let endpoint = endpoints[id] else { return nil }
        let d = endpoint.device
        let identity = DeviceIdentity(vendorID: 0x1532, productID: 0x0092,
            transport: IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? "Bluetooth Low Energy",
            product: "Naga Pro", registryID: id)
        let location = (IOHIDDeviceGetProperty(d, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue ?? 0
        return DeviceEndpoint(id: id, identity: identity, senderIDs: [id],
            connectionID: DeviceEndpoint.connectionID(identity: identity, locationID: location), canIdentifyEvents: false)
    }

    func refresh() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x1532, kIOHIDProductIDKey: 0x0092] as CFDictionary)
        let connected = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        var current: [UInt64: IOHIDDevice] = [:]
        for device in connected {
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
            guard transport.lowercased().contains("bluetooth") else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id) == KERN_SUCCESS, id != 0 else { continue }
            current[id] = device
        }
        for id in Array(endpoints.keys) where current[id] == nil {
            detach(id); removed(id)
        }
        for (id, device) in current where endpoints[id] == nil {
            guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else {
                failed("Bluetooth side-button reports could not be opened. Handling stopped; check Input Monitoring and reconnect the mouse.")
                return
            }
            let endpoint = Endpoint(device: device, id: id, owner: self)
            endpoints[id] = endpoint
            // When supported, the current input snapshot prevents a button
            // already held before Start/reconnect from becoming a new press.
            var bytes = [UInt8](repeating: 0, count: 64); var length = bytes.count
            let read = bytes.withUnsafeMutableBufferPointer {
                IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 6, $0.baseAddress!, &length)
            }
            if read == kIOReturnSuccess, (8...9).contains(length) { baseline(id, Array(bytes.prefix(length))) }
            IOHIDDeviceRegisterInputReportCallback(device, endpoint.buffer, 64, { context, result, _, _, reportID, bytes, length in
                guard let context, result == kIOReturnSuccess, reportID == 6, (8...9).contains(length) else { return }
                let endpoint = Unmanaged<Endpoint>.fromOpaque(context).takeUnretainedValue()
                endpoint.owner?.report(endpoint.id, reportID, Array(UnsafeBufferPointer(start: bytes, count: length)))
            }, Unmanaged.passUnretained(endpoint).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
    }
    private func detach(_ id: UInt64) {
        guard let endpoint = endpoints.removeValue(forKey: id) else { return }
        IOHIDDeviceUnscheduleFromRunLoop(endpoint.device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceRegisterInputReportCallback(endpoint.device, endpoint.buffer, 64, nil, nil)
        IOHIDDeviceClose(endpoint.device, 0)
    }
    func stop() { for id in Array(endpoints.keys) { detach(id) } }
    deinit { stop() }
}
