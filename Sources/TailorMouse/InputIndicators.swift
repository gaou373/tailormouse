import AppKit
import ApplicationServices
import TailorMouseCore

/// UI-only modifier observation and a temporary, read-only button inspector.
/// No remapping or synthetic input is activated by hovering over the diagram.
final class InputIndicators: ObservableObject {
    @Published var modifiers = ModifierMask()
    @Published var detectedButton: Int?
    @Published private(set) var observedOrdinaryButtons: Set<Int> = []
    @Published var detectionGeneration = 0
    @Published var inspectionMessage = "Hover here, then press a mouse button to identify it."
    @Published private(set) var recording = false
    @Published private(set) var recordingMessage = ""
    var devices: () -> [DetectedDevice] = { [] }
    var family: () -> String? = { "razer.naga.pro" }
    private var monitors: [Any] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let rawKeyboard = NagaKeyboardHIDInput()
    private var reports: [UInt64: NagaBluetoothReportDecoder] = [:]
    private var hovering = false
    private var recorder = MouseButtonRecording()
    private var recorded: ((Int) -> Void)?
    private var recordingTimer: Timer?
    private var escapeMonitor: Any?
    private var recordingGeneration = 0
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
        if phase == .down, (0...31).contains(button) { observedOrdinaryButtons.insert(button) }
        if hovering && phase == .down { detected(button) }
    }
    func resetDetectedButtons() { observedOrdinaryButtons.removeAll(); detectedButton = nil }
    private func detected(_ button: Int) {
        if (0...31).contains(button) { observedOrdinaryButtons.insert(button) }
        detectedButton = button; detectionGeneration += 1
    }
    func hover(_ entered: Bool) {
        hovering = entered
        if !recording { stopInspector(); if entered { startInspector() } }
    }
    func recordButton(completed: @escaping (Int) -> Void) {
        cancelRecording()
        guard monitoringEnabled else { return }
        guard CGPreflightListenEventAccess() else { recordingMessage = "Enable Input Monitoring before recording a mouse button."; return }
        recordingGeneration += 1; recorder.begin(); recorded = completed; recording = true
        recordingMessage = "Press and release a button, or scroll, on your selected mouse. Escape cancels."
        stopInspector(); startInspector()
        guard tap != nil else { cancelRecording(); recordingMessage = "Mouse recording could not start. Check Input Monitoring and reopen the app."; return }
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.cancelRecording(); self?.recordingMessage = "Recording timed out. Press Record to try again."
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancelRecording(); return nil
        }
    }
    func cancelRecording() {
        if recording { recordingMessage = "Recording cancelled." }
        recordingGeneration += 1; recording = false; recorder.cancel(); recorded = nil
        recordingTimer?.invalidate(); recordingTimer = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }; escapeMonitor = nil
        stopInspector()
        if hovering { startInspector() }
    }
    private func record(_ button: Int, phase: ButtonPhase, source: String) {
        guard recording, let captured = recorder.route(button: button, phase: phase, source: source) else { return }
        finishRecording(captured)
    }
    private func finishRecording(_ captured: Int) {
        let generation = recordingGeneration
        // Defer beyond the release so a click on Cancel can cancel instead of
        // assigning itself to the chord or activating the next editor control.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.recording, generation == self.recordingGeneration else { return }
            let completed = self.recorded
            self.cancelRecording()
            self.recordingMessage = "Recorded \(ChordButtonChoices.title(captured))."
            if WheelDirection(chordInput: captured) == nil { self.detected(captured) }; completed?(captured)
        }
    }
    private func startInspector() {
        guard monitoringEnabled else { return }
        guard CGPreflightListenEventAccess() else { inspectionMessage = "Input Monitoring approval is needed to identify buttons."; return }
        inspectionMessage = "Press a button on your mouse."
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .keyDown, .keyUp, .scrollWheel]
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
        rawKeyboard.report = { [weak self] id, reportID, bytes in
            guard let self, self.family() == nil || self.family() == "razer.naga.pro" else { return }
            var decoder = self.reports[id] ?? NagaBluetoothReportDecoder()
            for edge in decoder.route(reportID: reportID, bytes: bytes) {
                if let button = NagaKeyMap.button(for: edge.keyCode) {
                    if self.hovering && edge.phase == .down { self.detected(button) }
                    self.record(button, phase: edge.phase, source: "hid:\(id)")
                }
            }
            self.reports[id] = decoder
        }
        rawKeyboard.baseline = { [weak self] id, bytes in
            var decoder = NagaBluetoothReportDecoder(); decoder.prime(reportID: 6, bytes: bytes)
            self?.reports[id] = decoder
        }
        rawKeyboard.removed = { [weak self] id in self?.reports.removeValue(forKey: id) }
        rawKeyboard.failed = { [weak self] value in self?.inspectionMessage = value }
        if family() == nil || family() == "razer.naga.pro" { rawKeyboard.refresh() }
    }
    private func observe(_ type: CGEventType, _ event: CGEvent) {
        guard [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .keyDown, .keyUp, .scrollWheel].contains(type) else { return }
        // SteerMouse output retains the Naga sender ID. Ignore both edges before
        // hover detection or recording; the shared raw reader still identifies
        // the original Bluetooth side button. Resolve live PIDs across restarts.
        guard InputInspectionOrigin.acceptsQuartz(
            processID: event.getIntegerValueField(.eventSourceUnixProcessID),
            userData: event.getIntegerValueField(.eventSourceUserData),
            remapperProcessIDs: MouseInterceptor.steerMouseProcessIDs) else { return }
        let sender = UInt64(bitPattern: event.getIntegerValueField(CGEventField(rawValue: 87)!))
        guard let device = DeviceEndpoint.matching(senderID: sender, in: devices()),
              family() == nil || family() == device.identity.canonicalFamily else { return }
        if type == .scrollWheel {
            guard recording, event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else { return }
            let fields: [[CGEventField]] = [[.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1],
                                          [.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2]]
            for axis in 0..<2 {
                let delta = fields[axis].map { event.getDoubleValueField($0) }.first { $0 != 0 } ?? 0
                guard delta != 0 else { continue }
                if let captured = recorder.scroll(direction: .direction(axis: axis, delta: delta > 0 ? 1 : -1), source: "quartz:\(sender)") {
                    finishRecording(captured)
                }
                break
            }
            return
        }
        let phase: ButtonPhase = [.leftMouseUp, .rightMouseUp, .otherMouseUp, .keyUp].contains(type) ? .up : .down
        let button: Int?
        if type == .keyDown || type == .keyUp {
            guard device.identity.canonicalFamily == "razer.naga.pro", !rawKeyboard.owns(device) else { return }
            button = NagaKeyMap.button(for: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)))
        } else if type == .leftMouseDown || type == .leftMouseUp { button = 0 }
        else if type == .rightMouseDown || type == .rightMouseUp { button = 1 }
        else { button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) }
        if let button {
            if hovering && phase == .down { detected(button) }
            record(button, phase: phase, source: "quartz:\(sender)")
        }
    }
    private func stopInspector() {
        rawKeyboard.stop(); reports.removeAll()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit {
        recordingTimer?.invalidate(); if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        stopInspector(); for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }
}
