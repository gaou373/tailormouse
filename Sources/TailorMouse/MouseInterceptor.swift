import AppKit
import ApplicationServices
import TailorMouseCore

final class MouseInterceptor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var guardTimer: Timer?
    private var router = ButtonPairRouter()
    private var wheel = WheelTransformer()
    var configuration: () -> ProfileConfiguration = { ProfileConfiguration() }
    var stopped: (String) -> Void = { _ in }

    static var steerMouseIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "jp.plentycom.boa.SteerMouse" ||
            ($0.localizedName?.localizedCaseInsensitiveContains("SteerMouse Manager") ?? false)
        }
    }

    func start() -> String? {
        guard tap == nil else { return nil }
        guard !Self.steerMouseIsRunning else {
            return "SteerMouse Manager is running. Quit it yourself before starting TailorMouse."
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return "Allow TailorMouse in System Settings → Privacy & Security → Accessibility, then press Start again."
        }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                             options: .defaultTap, eventsOfInterest: mask,
                                             callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let interceptor = Unmanaged<MouseInterceptor>.fromOpaque(context).takeUnretainedValue()
            return interceptor.handle(type: type, event: event)
        }, userInfo: context) else {
            return "macOS could not create the mouse event tap. Check Accessibility access and try again."
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            return "macOS could not create the event run loop."
        }
        tap = newTap
        runLoopSource = source
        router.reset()
        wheel.reset()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        guardTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Self.steerMouseIsRunning {
                self.stop()
                self.stopped("Stopped because SteerMouse Manager started.")
            } else if !AXIsProcessTrusted() {
                self.stop()
                self.stopped("Stopped because Accessibility access was removed.")
            }
        }
        return nil
    }

    func stop() {
        guardTimer?.invalidate()
        guardTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        router.reset()
        wheel.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Do not silently restart a tap macOS disabled.
            DispatchQueue.main.async { [weak self] in
                self?.stop()
                self?.stopped("macOS paused mouse handling. Press Start to resume.")
            }
            return Unmanaged.passUnretained(event)
        }
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let profile = configuration().profile(for: bundleID)
        if type == .scrollWheel {
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return Unmanaged.passUnretained(event) }
            let fields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2, .scrollWheelEventDeltaAxis3]
            let values = wheel.transform(fields.map { event.getIntegerValueField($0) }, continuous: false, profile: profile)
            for (field, value) in zip(fields, values) { event.setIntegerValueField(field, value: value) }
            let factor = profile.safeWheelSpeed * (profile.invertWheel ? -1 : 1)
            let precise: [CGEventField] = [
                .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis3,
                .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis3
            ]
            for field in precise { event.setDoubleValueField(field, value: event.getDoubleValueField(field) * factor) }
            return Unmanaged.passUnretained(event)
        }
        let phase: ButtonPhase
        switch type {
        case .otherMouseDown: phase = .down
        case .otherMouseUp: phase = .up
        case .otherMouseDragged: phase = .drag
        default: return Unmanaged.passUnretained(event)
        }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let decision = router.route(button: button, phase: phase, profile: profile)
        if let action = decision.emit { emitShortcut(action, originalFlags: event.flags) }
        return decision.suppress ? nil : Unmanaged.passUnretained(event)
    }

    private func emitShortcut(_ action: ButtonAction, originalFlags: CGEventFlags) {
        let keyCode: CGKeyCode
        switch action {
        case .back: keyCode = 33 // Command-[ (application-dependent)
        case .forward: keyCode = 30 // Command-]
        case .copy: keyCode = 8 // Command-C
        case .paste: keyCode = 9 // Command-V
        case .passthrough: return
        }
        let source = CGEventSource(stateID: .privateState)
        // Build every event first; allocation failure never leaves a modifier or key held.
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else { return }
        let flags = originalFlags.union(.maskCommand)
        keyDown.flags = flags
        keyUp.flags = flags
        commandDown.type = .flagsChanged
        commandDown.flags = flags
        commandUp.type = .flagsChanged
        commandUp.flags = originalFlags
        let synthesizeCommand = !originalFlags.contains(.maskCommand)
        if synthesizeCommand { commandDown.post(tap: .cgSessionEventTap) }
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        if synthesizeCommand { commandUp.post(tap: .cgSessionEventTap) }
    }
}
