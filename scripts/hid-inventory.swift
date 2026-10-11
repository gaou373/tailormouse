#!/usr/bin/env swift
// Read-only metadata and input element descriptors. No device opens, reports,
// callbacks, keyboard monitoring, or exclusive ownership.
import Foundation
import IOKit
import IOKit.hid

let showAll = CommandLine.arguments.contains("--all")
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: CFDictionary? = showAll ? nil : [kIOHIDVendorIDKey: 0x1532] as CFDictionary
IOHIDManagerSetDeviceMatching(manager, matching)
let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []

func jsonValue(_ value: Any) -> Any {
    if let data = value as? Data { return ["byteCount": data.count, "hex": data.map { String(format: "%02x", $0) }.joined()] }
    if let dict = value as? [String: Any] { return dict.mapValues(jsonValue) }
    if let array = value as? [Any] { return array.map(jsonValue) }
    if value is String || value is NSNumber || value is NSNull { return value }
    return String(describing: value)
}

let rows: [[String: Any]] = devices.map { device in
    let service = IOHIDDeviceGetService(device)
    var registryID: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(service, &registryID)
    var properties: Unmanaged<CFMutableDictionary>?
    IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
    let rawProperties = properties?.takeRetainedValue() as? [String: Any] ?? [:]
    let elements = (IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement]) ?? []
    let inputs: [[String: Any]] = elements.compactMap { element in
        let type = IOHIDElementGetType(element).rawValue
        guard (1...4).contains(type) else { return nil }
        return [
            "cookie": IOHIDElementGetCookie(element),
            "type": type,
            "usagePage": IOHIDElementGetUsagePage(element),
            "usage": IOHIDElementGetUsage(element),
            "reportID": IOHIDElementGetReportID(element),
            "reportSize": IOHIDElementGetReportSize(element),
            "reportCount": IOHIDElementGetReportCount(element),
            "logicalMin": IOHIDElementGetLogicalMin(element),
            "logicalMax": IOHIDElementGetLogicalMax(element),
            "isRelative": IOHIDElementIsRelative(element),
            "isArray": IOHIDElementIsArray(element)
        ]
    }.sorted {
        let lhs = ($0["reportID"] as? UInt32 ?? 0, $0["usagePage"] as? UInt32 ?? 0, $0["usage"] as? UInt32 ?? 0)
        let rhs = ($1["reportID"] as? UInt32 ?? 0, $1["usagePage"] as? UInt32 ?? 0, $1["usage"] as? UInt32 ?? 0)
        return lhs < rhs
    }
    let identityKeys = [kIOHIDProductKey, kIOHIDManufacturerKey, kIOHIDVendorIDKey, kIOHIDProductIDKey,
                        kIOHIDTransportKey, kIOHIDLocationIDKey, kIOHIDPrimaryUsagePageKey, kIOHIDPrimaryUsageKey]
    var identity: [String: Any] = [:]
    for key in identityKeys {
        if let value = IOHIDDeviceGetProperty(device, key as CFString) { identity[key] = jsonValue(value) }
    }
    return ["registryID": String(registryID), "identity": identity,
            "properties": jsonValue(rawProperties), "inputElements": inputs]
}.sorted { ($0["registryID"] as? String ?? "") < ($1["registryID"] as? String ?? "") }

let output: [String: Any] = [
    "schemaVersion": 1,
    "capturedAt": ISO8601DateFormatter().string(from: Date()),
    "scope": showAll ? "all HID metadata" : "Razer vendor 0x1532 HID metadata",
    "deviceCount": rows.count,
    "devices": rows
]
do {
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
} catch {
    FileHandle.standardError.write(Data("Inventory failed: \(error)\n".utf8))
    exit(1)
}
