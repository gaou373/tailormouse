import Combine
import Foundation
import IOKit
import IOKit.hid
import TailorMouseCore

typealias DetectedDevice = DeviceEndpoint

/// Discovers metadata without opening devices or registering input callbacks.
/// The timer also removes disconnected devices and discovers replacement IDs.
final class DeviceCatalog: ObservableObject {
    @Published private(set) var devices: [DetectedDevice] = []
    @Published private(set) var connections: [DeviceConnection] = []
    private let matches: [[String: Int]] = [
        [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 2],
        [kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: 1],
        // Naga side buttons may be exposed on a separate HID interface.
        [kIOHIDVendorIDKey: 0x1532]
    ]
    private var refreshTimer: Timer?

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { refreshTimer?.invalidate() }

    func refresh() {
        // A fresh, unscheduled manager makes each poll a current enumeration;
        // no input run-loop sources or device-arrival callbacks are needed.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let connected = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        var seenRegistryIDs: Set<UInt64> = []
        devices = connected.compactMap { device in
            let vendorID = integerProperty(device, kIOHIDVendorIDKey)
            let isPointing = IOHIDDeviceConformsTo(device, 1, 2) || IOHIDDeviceConformsTo(device, 1, 1)
            // No unrelated keyboard interface is admitted or monitored.
            guard isPointing || vendorID == 0x1532 else { return nil }
            let service = IOHIDDeviceGetService(device)
            guard let id = registryID(service) else { return nil }
            // Matching several usage dictionaries can return distinct wrapper
            // objects for one registry service. They are one endpoint.
            guard seenRegistryIDs.insert(id).inserted else { return nil }
            let routing = senderIDs(for: service)
            let identity = DeviceIdentity(
                vendorID: vendorID,
                productID: integerProperty(device, kIOHIDProductIDKey),
                transport: stringProperty(device, kIOHIDTransportKey, fallback: "Unknown"),
                product: stringProperty(device, kIOHIDProductKey, fallback: "HID device"),
                registryID: id
            )
            let location = integerProperty(device, kIOHIDLocationIDKey)
            let connection = DeviceEndpoint.connectionID(identity: identity, locationID: location)
            return DetectedDevice(id: id, identity: identity, senderIDs: routing.ids, connectionID: connection,
                                  canIdentifyEvents: routing.hasEventService)
        }.sorted {
            if $0.identity.product == $1.identity.product { return $0.id < $1.id }
            return $0.identity.product.localizedStandardCompare($1.identity.product) == .orderedAscending
        }
        connections = DeviceConnection.grouping(devices)
    }

    func device(forSenderID senderID: UInt64) -> DetectedDevice? {
        DeviceEndpoint.matching(senderID: senderID, in: devices)
    }

    private func integerProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    private func stringProperty(_ device: IOHIDDevice, _ key: String, fallback: String) -> String {
        IOHIDDeviceGetProperty(device, key as CFString) as? String ?? fallback
    }

    private func registryID(_ service: io_registry_entry_t) -> UInt64? {
        guard service != 0 else { return nil }
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS, id != 0 else { return nil }
        return id
    }

    private func isEventService(_ service: io_registry_entry_t) -> Bool {
        IOObjectConformsTo(service, "IOHIDEventService") != 0 ||
        IOObjectConformsTo(service, "IOHIDEventServiceFastPath") != 0 ||
        IOObjectConformsTo(service, "AppleUserHIDEventService") != 0
    }

    /// Independent public-IOKit traversal informed by the observed device-to-
    /// event-service relationship. Registry IDs are candidate sender identities;
    /// the CGEvent sender field used by the interceptor is undocumented.
    private func senderIDs(for service: io_registry_entry_t) -> (ids: Set<UInt64>, hasEventService: Bool) {
        var ids: Set<UInt64> = []
        if let ownID = registryID(service) { ids.insert(ownID) }
        var foundEventService = isEventService(service)

        // Usually the HID service is the device root. For an interface handle,
        // accept only its immediate IOHIDDevice parent. Never ascend a bus,
        // Bluetooth controller, or shared IOResources node.
        var root = service
        var retainedParent: io_registry_entry_t = 0
        if IOObjectConformsTo(service, "IOHIDInterface") != 0 {
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
                if IOObjectConformsTo(parent, "IOHIDDevice") != 0 {
                    root = parent
                    retainedParent = parent
                } else {
                    IOObjectRelease(parent)
                }
            }
        }
        defer { if retainedParent != 0 { IOObjectRelease(retainedParent) } }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS
        else { return (ids, foundEventService) }
        defer { IOObjectRelease(iterator) }
        while true {
            let child = IOIteratorNext(iterator)
            guard child != 0 else { break }
            let eventService = isEventService(child)
            if eventService || IOObjectConformsTo(child, "IOHIDInterface") != 0 {
                if let id = registryID(child) { ids.insert(id) }
                foundEventService = foundEventService || eventService
            }
            IOObjectRelease(child)
        }
        return (ids, foundEventService)
    }
}
