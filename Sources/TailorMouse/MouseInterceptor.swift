import AppKit
import ApplicationServices
import TailorMouseCore

/// Original event processor. Field 87 is an observed, undocumented macOS sender
/// convention. Device mode always passes through unrecognized senders.
final class MouseInterceptor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var states: [String: InputState] = [:]
    private let generatedTag: Int64 = 0x5441494c4f52
    private let senderField = CGEventField(rawValue: 87)!
    var configuration: () -> ProfileConfiguration = { ProfileConfiguration() }
    var devices: () -> [DetectedDevice] = { [] }
    var stopped: (String) -> Void = { _ in }
    var observed: (String) -> Void = { _ in }

    private final class InputState {
        var router = InputRouter()
        var wheel = WheelTransformer()
        var pointer = PointerTransformer()
        var origins: [Int: CGEvent] = [:]
    }

    static var steerMouseIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "jp.plentycom.boa.SteerMouse" ||
            ($0.localizedName?.localizedCaseInsensitiveContains("SteerMouse Manager") ?? false)
        }
    }

    func start() -> String? {
        guard tap == nil else { return nil }
        guard !Self.steerMouseIsRunning else {
            return "SteerMouse Manager is running. Quit it before starting TailorMouse."
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return "Allow TailorMouse in Privacy & Security → Accessibility, then press Start again."
        }
        guard CGPreflightListenEventAccess() else {
            return "Allow TailorMouse in Privacy & Security → Input Monitoring, then reopen TailorMouse."
        }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown,
            .otherMouseUp, .otherMouseDragged, .scrollWheel, .mouseMoved, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<MouseInterceptor>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return "macOS could not start mouse handling. Check Accessibility and Input Monitoring."
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            return "macOS could not create the event run loop."
        }
        tap = newTap; source = runLoopSource; states.removeAll()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Self.steerMouseIsRunning {
                self.stop(); self.stopped("Stopped because SteerMouse Manager started.")
            } else if !AXIsProcessTrusted() || !CGPreflightListenEventAccess() {
                self.stop(); self.stopped("Stopped because input permission was removed.")
            } else {
                let present = Set(self.devices().map { $0.connectionID })
                for id in Array(self.states.keys) where !id.hasPrefix("unknown.") && !present.contains(id) {
                    self.states.removeValue(forKey: id)
                }
            }
        }
        return nil
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; states.removeAll()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                self?.stop(); self?.stopped("macOS paused mouse handling. Press Start to resume.")
            }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != generatedTag else {
            return Unmanaged.passUnretained(event)
        }
        let config = configuration()
        let sender = UInt64(bitPattern: event.getIntegerValueField(senderField))
        let matches = devices().filter { sender != 0 && $0.senderIDs.contains(sender) }
        let device = matches.count == 1 ? matches[0] : nil
        let keyboard = type == .keyDown || type == .keyUp
        if keyboard {
            // Keyboard translation is confined to positively identified original Naga endpoints.
            guard device?.identity.canonicalFamily == "razer.naga.pro" else { return Unmanaged.passUnretained(event) }
        }
        if let family = config.selectedDeviceFamily {
            guard device?.identity.canonicalFamily == family else { return Unmanaged.passUnretained(event) }
        }
        let connection = device?.connectionID ?? "unknown.\(sender)"
        let state = states[connection] ?? InputState(); states[connection] = state
        let profile = config.profile(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        if type == .scrollWheel {
            transformWheel(event, state: state, profile: profile)
            return Unmanaged.passUnretained(event)
        }
        if [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) {
            transformPointer(event, state: state, profile: profile)
            if type == .mouseMoved { return Unmanaged.passUnretained(event) }
        }
        let button: Int
        let phase: ButtonPhase
        if keyboard {
            let key = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            guard let panel = NagaKeyMap.button(for: key) else { return Unmanaged.passUnretained(event) }
            button = panel; phase = type == .keyDown ? .down : .up
        } else {
            switch type {
            case .leftMouseDown: button = 0; phase = .down
            case .leftMouseUp: button = 0; phase = .up
            case .leftMouseDragged: button = 0; phase = .drag
            case .rightMouseDown: button = 1; phase = .down
            case .rightMouseUp: button = 1; phase = .up
            case .rightMouseDragged: button = 1; phase = .drag
            case .otherMouseDown: button = Int(event.getIntegerValueField(.mouseEventButtonNumber)); phase = .down
            case .otherMouseUp: button = Int(event.getIntegerValueField(.mouseEventButtonNumber)); phase = .up
            case .otherMouseDragged: button = Int(event.getIntegerValueField(.mouseEventButtonNumber)); phase = .drag
            default: return Unmanaged.passUnretained(event)
            }
        }
        if phase == .down && state.origins[button] == nil { state.origins[button] = event.copy() }
        let decision = state.router.route(button: button, phase: phase, profile: profile, modifiers: modifierMask(event.flags))
        for emission in decision.emissions { execute(emission.binding, origin: state.origins[emission.button] ?? event) }
        if phase == .up { state.origins.removeValue(forKey: button) }
        if phase != .drag {
            let label = button >= 100 ? "Naga side \(button - 99)" : "Mouse button \(button + 1)"
            let message = "\(label) · \(phase == .down ? "pressed" : "released") · \(device?.identity.transport ?? "mouse")"
            DispatchQueue.main.async { [weak self] in self?.observed(message) }
        }
        return decision.suppress ? nil : Unmanaged.passUnretained(event)
    }

    private func transformWheel(_ event: CGEvent, state: InputState, profile: MouseProfile) {
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return }
        let fields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2, .scrollWheelEventDeltaAxis3]
        let values = state.wheel.transform(fields.map { event.getIntegerValueField($0) }, continuous: false, profile: profile)
        for (field, value) in zip(fields, values) { event.setIntegerValueField(field, value: value) }
        let factors = [profile.safeWheelSpeed * (profile.invertWheel ? -1 : 1),
                       profile.safeHorizontalWheelSpeed * (profile.invertHorizontalWheel ? -1 : 1)]
        let precise: [[CGEventField]] = [
            [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1],
            [.scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2]]
        for axis in 0..<2 {
            for field in precise[axis] { event.setDoubleValueField(field, value: event.getDoubleValueField(field) * factors[axis]) }
        }
    }

    private func transformPointer(_ event: CGEvent, state: InputState, profile: MouseProfile) {
        let dx = event.getIntegerValueField(.mouseEventDeltaX), dy = event.getIntegerValueField(.mouseEventDeltaY)
        let values = state.pointer.transform([dx, dy], profile: profile)
        guard profile.safePointerSpeed != 1 else { return }
        guard values.count == 2 else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: values[0])
        event.setIntegerValueField(.mouseEventDeltaY, value: values[1])
        var point = event.location
        point.x += Double(values[0]) - Double(dx); point.y += Double(values[1]) - Double(dy)
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let displays = screens.map { CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY,
                                            width: $0.frame.width, height: $0.frame.height) }
        if !displays.contains(where: { $0.contains(point) }),
           let nearest = displays.min(by: { distance(point, to: $0) < distance(point, to: $1) }) {
            point.x = min(nearest.maxX - 1, max(nearest.minX, point.x))
            point.y = min(nearest.maxY - 1, max(nearest.minY, point.y))
        }
        event.location = point
    }

    private func distance(_ point: CGPoint, to rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private func execute(_ binding: ActionBinding, origin: CGEvent) {
        switch binding.action {
        case .passthrough: replay(origin)
        case .disabled: break
        case .back: shortcut(33, .command)
        case .forward: shortcut(30, .command)
        case .copy: shortcut(8, .command)
        case .paste: shortcut(9, .command)
        case .cut: shortcut(7, .command)
        case .undo: shortcut(6, .command)
        case .redo: shortcut(6, [.command, .shift])
        case .selectAll: shortcut(0, .command)
        case .escape: shortcut(53, [])
        case .enter: shortcut(36, [])
        case .space: shortcut(49, [])
        case .appSwitcher: shortcut(48, .command)
        case .missionControl: shortcut(126, .control)
        case .shortcut: if let key = binding.shortcut { shortcut(key.keyCode, key.modifiers) }
        case .mouseClick: click(button: binding.mouseButton, location: origin.location, flags: origin.flags)
        case .scroll:
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                wheel1: Int32(clamping: binding.scrollY), wheel2: Int32(clamping: binding.scrollX), wheel3: 0) else { return }
            post(event)
        }
    }

    private func replay(_ origin: CGEvent) {
        if origin.type == .keyDown {
            shortcut(UInt16(clamping: origin.getIntegerValueField(.keyboardEventKeycode)), modifierMask(origin.flags))
        } else {
            click(button: Int(origin.getIntegerValueField(.mouseEventButtonNumber)), location: origin.location, flags: origin.flags)
        }
    }

    private func shortcut(_ code: UInt16, _ modifiers: ModifierMask) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return }
        down.flags = eventFlags(modifiers); up.flags = eventFlags(modifiers)
        post(down); post(up)
    }

    private func click(button: Int, location: CGPoint, flags: CGEventFlags) {
        let raw = UInt32(clamping: min(31, max(0, button)))
        let mouseButton = CGMouseButton(rawValue: raw)!
        let downType: CGEventType = raw == 0 ? .leftMouseDown : raw == 1 ? .rightMouseDown : .otherMouseDown
        let upType: CGEventType = raw == 0 ? .leftMouseUp : raw == 1 ? .rightMouseUp : .otherMouseUp
        guard let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: location, mouseButton: mouseButton),
              let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: location, mouseButton: mouseButton) else { return }
        down.flags = flags; up.flags = flags
        down.setIntegerValueField(.mouseEventClickState, value: 1); up.setIntegerValueField(.mouseEventClickState, value: 1)
        post(down); post(up)
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: generatedTag)
        event.post(tap: .cgSessionEventTap)
    }

    private func modifierMask(_ flags: CGEventFlags) -> ModifierMask {
        var result: ModifierMask = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        return result
    }
    private func eventFlags(_ modifiers: ModifierMask) -> CGEventFlags {
        var result: CGEventFlags = []
        if modifiers.contains(.command) { result.insert(.maskCommand) }
        if modifiers.contains(.shift) { result.insert(.maskShift) }
        if modifiers.contains(.option) { result.insert(.maskAlternate) }
        if modifiers.contains(.control) { result.insert(.maskControl) }
        return result
    }
}
