import Foundation
import IOKit
import IOKit.hid
import TailorMouseCore

/// Reads only supported Naga keyboard interfaces while handling is active.
/// Shared opens; no device seizure, feature writes, unrelated keyboard access
/// or cursor manipulation. Polling handles reconnects without stale pointers.
final class NagaKeyboardHIDInput {
    private final class Endpoint {
        let device: IOHIDDevice
        let id: UInt64
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        let format: NagaKeyboardReportFormat
        let identity: DeviceEndpoint
        weak var owner: NagaKeyboardHIDInput?
        init(device: IOHIDDevice, id: UInt64, format: NagaKeyboardReportFormat, owner: NagaKeyboardHIDInput) {
            self.device = device; self.id = id; self.format = format; self.owner = owner
            let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let info = DeviceIdentity(vendorID: 0x1532, productID: product,
                transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "Bluetooth Low Energy",
                product: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Naga", registryID: id)
            let location = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue ?? 0
            identity = DeviceEndpoint(id: id, identity: info, senderIDs: [id],
                connectionID: DeviceEndpoint.connectionID(identity: info, locationID: location), canIdentifyEvents: false)
        }
        deinit { buffer.deallocate() }
    }
    private var endpoints: [UInt64: Endpoint] = [:]
    var report: (UInt64, UInt32, [UInt8]) -> Void = { _, _, _ in }
    var baseline: (UInt64, [UInt8]) -> Void = { _, _ in }
    var removed: (UInt64) -> Void = { _ in }
    var failed: (String) -> Void = { _ in }
    func owns(_ device: DeviceEndpoint) -> Bool {
        NagaKeyboardReportFormat.owns(device, endpoints: endpoints.keys.compactMap { identity($0) })
    }
    var bluetoothEndpointCount: Int { endpoints.values.filter { $0.format == .bluetooth }.count }
    var endpointCount: Int { endpoints.count }
    var connectionIDs: Set<String> { Set(endpoints.keys.compactMap { identity($0)?.connectionID }) }
    func identity(_ id: UInt64) -> DeviceEndpoint? { endpoints[id]?.identity }
    private let scanQueue = DispatchQueue(label: "dev.tailormouse.naga-scan", qos: .utility)
    private var scanning = false
    private var generation = 0

    func refresh(family: String? = nil, wait: Bool = false) {
        if wait {
            generation += 1
            let current = scanQueue.sync { autoreleasepool { Self.scan(family: family) } }
            scanning = false; attach(current); return
        }
        guard !scanning else { return }
        scanning = true; let token = generation
        scanQueue.async { [weak self] in
            let current = autoreleasepool { Self.scan(family: family) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.scanning = false; self.attach(current)
            }
        }
    }
    private static func scan(family: String?) -> [UInt64: (IOHIDDevice, NagaKeyboardReportFormat)] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(manager, [0x008f,0x0090,0x0092,0x00b4].map {
            [kIOHIDVendorIDKey: 0x1532, kIOHIDProductIDKey: $0]
        } as CFArray)
        let connected = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        var current: [UInt64: (IOHIDDevice, NagaKeyboardReportFormat)] = [:]
        for device in connected {
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
            let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let identity = DeviceIdentity(vendorID: 0x1532, productID: product, transport: transport, product: "")
            guard family == nil || family == identity.canonicalFamily else { continue }
            let elements = (IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement]) ?? []
            var reportIDs = Set(elements.filter { IOHIDElementGetUsagePage($0) == 7 }.map { IOHIDElementGetReportID($0) })
            // On macOS 27 the element API can be empty before Input Monitoring
            // approval. Registry descriptors remain available without opening
            // the device; attach still requires a successful shared HID open.
            if reportIDs.isEmpty {
                let property = IORegistryEntryCreateCFProperty(IOHIDDeviceGetService(device), "Elements" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                reportIDs = NagaKeyboardReportFormat.keyboardReportIDs(in: property as? [[String: Any]] ?? [])
            }
            guard let format = NagaKeyboardReportFormat.select(identity: identity, keyboardReportIDs: reportIDs) else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id) == KERN_SUCCESS, id != 0 else { continue }
            current[id] = (device, format)
        }
        return current
    }
    private func attach(_ current: [UInt64: (IOHIDDevice, NagaKeyboardReportFormat)]) {
        for id in Array(endpoints.keys) where current[id] == nil {
            detach(id); removed(id)
        }
        for (id, pair) in current where endpoints[id] == nil {
            let (device, format) = pair
            guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else {
                failed("Naga side-button reports could not be opened. Handling stopped; check Input Monitoring and reconnect the mouse.")
                return
            }
            let endpoint = Endpoint(device: device, id: id, format: format, owner: self)
            endpoints[id] = endpoint
            // When supported, the current input snapshot prevents a button
            // already held before Start/reconnect from becoming a new press.
            var bytes = [UInt8](repeating: 0, count: 64); var length = bytes.count
            let read = bytes.withUnsafeMutableBufferPointer {
                IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, CFIndex(format.reportID), $0.baseAddress!, &length)
            }
            if read == kIOReturnSuccess, let normalized = format.canonical(reportID: format.reportID, bytes: Array(bytes.prefix(length))) {
                baseline(id, normalized)
            }
            IOHIDDeviceRegisterInputReportCallback(device, endpoint.buffer, 64, { context, result, _, _, reportID, bytes, length in
                guard let context, result == kIOReturnSuccess, (8...16).contains(length) else { return }
                let endpoint = Unmanaged<Endpoint>.fromOpaque(context).takeUnretainedValue()
                guard let normalized = endpoint.format.canonical(reportID: reportID, bytes: Array(UnsafeBufferPointer(start: bytes, count: length))) else { return }
                endpoint.owner?.report(endpoint.id, 6, normalized)
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
    func stop() { generation += 1; scanning = false; for id in Array(endpoints.keys) { detach(id) } }
    deinit { stop() }
}
