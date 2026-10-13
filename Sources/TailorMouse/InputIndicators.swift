import AppKit
import ApplicationServices
import TailorMouseCore

/// UI-only modifier observation and a temporary, read-only button inspector.
/// No remapping or synthetic input is activated by hovering over the diagram.
final class InputIndicators: ObservableObject {
    @Published var modifiers = ModifierMask()
    @Published var detectedButton: Int?
    @Published var detectionGeneration = 0
    @Published var inspectionMessage = "Hover here, then press a mouse button to identify it."
    var devices: () -> [DetectedDevice] = { [] }
    var family: () -> String? = { "razer.naga.pro" }
    private var monitors: [Any] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let bluetooth = BluetoothNagaInput()
    private var reports: [UInt64: NagaBluetoothReportDecoder] = [:]
    private var hovering = false
    var monitoringEnabled = true
    func beginModifiers() {
        guard monitoringEnabled else { return }
        func mask(_ flags: NSEvent.ModifierFlags) -> ModifierMask {
            var result = ModifierMask()
            if flags.contains(.command) { result.insert(.command) }
            if flags.contains(.shift) { result.insert(.shift) }
            if flags.contains(.option) { result.insert(.option) }
            if flags.contains(.control) { result.insert(.control) }
            return result
        }
        modifiers = mask(NSEvent.modifierFlags)
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.modifiers = mask(event.modifierFlags); return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            DispatchQueue.main.async { self?.modifiers = mask(event.modifierFlags) }
        }) { monitors.append(global) }
    }
    func observed(button: Int, phase: ButtonPhase) {
        if hovering && phase == .down { detected(button) }
    }
    private func detected(_ button: Int) { detectedButton = button; detectionGeneration += 1 }
    func hover(_ entered: Bool) {
        stopInspector(); hovering = entered
        guard entered && monitoringEnabled else { return }
        guard CGPreflightListenEventAccess() else { inspectionMessage = "Input Monitoring approval is needed to identify buttons."; return }
        inspectionMessage = "Press a button on your mouse."
        let types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<InputIndicators>.fromOpaque(context).takeUnretainedValue()
                owner.observe(type, event)
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
            self.source = source; CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        bluetooth.report = { [weak self] id, reportID, bytes in
            guard let self, self.family() == nil || self.family() == "razer.naga.pro" else { return }
            var decoder = self.reports[id] ?? NagaBluetoothReportDecoder()
            for edge in decoder.route(reportID: reportID, bytes: bytes) where edge.phase == .down {
                if let button = NagaKeyMap.button(for: edge.keyCode) { self.detected(button) }
            }
            self.reports[id] = decoder
        }
        bluetooth.failed = { [weak self] value in self?.inspectionMessage = value }
        if family() == nil || family() == "razer.naga.pro" { bluetooth.refresh() }
    }
    private func observe(_ type: CGEventType, _ event: CGEvent) {
        guard event.getIntegerValueField(.eventSourceUserData) != 0x5441494c4f52 else { return }
        let sender = UInt64(bitPattern: event.getIntegerValueField(CGEventField(rawValue: 87)!))
        guard let device = DeviceEndpoint.matching(senderID: sender, in: devices()),
              family() == nil || family() == device.identity.canonicalFamily else { return }
        if type == .keyDown {
            guard device.identity.canonicalFamily == "razer.naga.pro" else { return }
            if let button = NagaKeyMap.button(for: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))) { detected(button) }
        } else if type == .leftMouseDown { detected(0) }
        else if type == .rightMouseDown { detected(1) }
        else if type == .otherMouseDown { detected(Int(event.getIntegerValueField(.mouseEventButtonNumber))) }
    }
    private func stopInspector() {
        bluetooth.stop(); reports.removeAll()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stopInspector(); for monitor in monitors { NSEvent.removeMonitor(monitor) } }
}
