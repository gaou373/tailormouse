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
    private var keyboardToken: UInt64 = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var competingManagers: Set<Int32> = []
    private var requestedAccessibilityApproval = false
    private var heldShortcuts = HeldShortcuts()
    private var shortcutRepeatWork: DispatchWorkItem?
    private var modifierState = NagaModifierState()
    private let nagaInput = NagaKeyboardHIDInput()
    var bluetoothEndpointCount: Int { nagaInput.bluetoothEndpointCount }
    var rawKeyboardEndpointCount: Int { nagaInput.endpointCount }
    var configuration: () -> ProfileConfiguration = { ProfileConfiguration() }
    var devices: () -> [DetectedDevice] = { [] }
    var keyboardModifiers: () -> ModifierMask = { [] }
    var stopped: (String) -> Void = { _ in }
    var observed: (String) -> Void = { _ in }
    var observedButton: (Int, ButtonPhase) -> Void = { _, _ in }

    private struct RecordedMouseInput {
        let event: CGEvent
        let profile: MouseProfile
    }
    private struct MousePrelude {
        let events: [RecordedMouseInput]
        let keySequences: [[UInt16]]
    }
    private final class InputState {
        let shortcutSource = UUID().uuidString
        var router = InputRouter()
        var wheel = WheelTransformer()
        var mappedWheel = WheelTransformer()
        var origins: [Int: CGEvent] = [:]
        var keyboard = NagaKeyboardDecoder()
        var bluetoothReports = NagaBluetoothReportDecoder()
        var rawKeyboardTokens: Set<UInt64> = []
        var rawPassthroughKeys = NagaPostedKeyTracker()
        var keyboardEvents: [UInt64: CGEvent] = [:]
        var keyboardReplayKeys: [Int: [UInt16]] = [:]
        var keyboardWork: DispatchWorkItem?
        var mousePrelude = NagaMousePreludeDecoder()
        var mousePreludeEvents: [UInt64: RecordedMouseInput] = [:]
        var mousePreludeWork: DispatchWorkItem?
        var keyboardPreludes: [UInt64: MousePrelude] = [:]
        var keyboardMouseReplay: [Int: [RecordedMouseInput]] = [:]
        deinit { keyboardWork?.cancel(); mousePreludeWork?.cancel() }
    }

    static var steerMouseProcessIDs: Set<Int32> {
        Set(NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "jp.plentycom.boa.SteerMouse" ||
            ($0.localizedName?.localizedCaseInsensitiveContains("SteerMouse Manager") ?? false)
        }.map(\.processIdentifier))
    }

    static var steerMouseIsRunning: Bool { !steerMouseProcessIDs.isEmpty }

    func start() -> String? {
        guard tap == nil else { return nil }
        guard !Self.steerMouseIsRunning else {
            return "SteerMouse Manager is running. Quit it before starting TailorMouse."
        }
        if !AXIsProcessTrusted() {
            // One native prompt per launch; repeated Start clicks must not loop
            // the permission dialog when macOS retains an old build's entry.
            if !requestedAccessibilityApproval {
                requestedAccessibilityApproval = true
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            return "macOS has not approved this build. In Accessibility, remove the old TailorMouse entry and add /Applications/TailorMouse.app, then quit and reopen the app."
        }
        guard CGPreflightListenEventAccess() else {
            return "Allow TailorMouse in Privacy & Security → Input Monitoring, then reopen TailorMouse."
        }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown,
            .otherMouseUp, .otherMouseDragged, .scrollWheel, .mouseMoved, .keyDown, .keyUp, .flagsChanged]
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
        modifierState.begin(snapshot: keyboardModifiers().union(modifierMask(CGEventSource.flagsState(.hidSystemState))))
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        competingManagers = Self.steerMouseProcessIDs
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if note.name == NSWorkspace.didTerminateApplicationNotification { self.competingManagers.remove(app.processIdentifier) }
                else if app.bundleIdentifier == "jp.plentycom.boa.SteerMouse" || (app.localizedName?.localizedCaseInsensitiveContains("SteerMouse Manager") ?? false) {
                    self.competingManagers.insert(app.processIdentifier)
                }
                if !self.competingManagers.isEmpty {
                    self.stop(); self.stopped("Stopped because SteerMouse Manager started.")
                }
            }
        }
        if !competingManagers.isEmpty { stop(); return "SteerMouse Manager is running. Quit it before starting TailorMouse." }
        nagaInput.report = { [weak self] id, reportID, bytes in self?.handleRawKeyboard(id, reportID: reportID, bytes: bytes) }
        nagaInput.baseline = { [weak self] id, bytes in
            guard let self, let device = self.devices().first(where: { $0.id == id }) ?? self.nagaInput.identity(id) else { return }
            let state = self.states[device.connectionID] ?? InputState()
            self.states[device.connectionID] = state
            state.bluetoothReports.prime(reportID: 6, bytes: bytes, alreadyOwned: state.keyboard.ownedKeys)
        }
        nagaInput.removed = { [weak self] id in
            guard let self else { return }
            // The catalog may already have refreshed; connection IDs are
            // retained independently for exact endpoint removal.
            if let connection = self.rawKeyboardConnections.removeValue(forKey: id), let state = self.states.removeValue(forKey: connection) {
                self.releaseRawPassthrough(state)
            }
        }
        nagaInput.failed = { [weak self] message in
            DispatchQueue.main.async { self?.stop(); self?.stopped(message) }
        }
        if configuration().selectedDeviceFamily == nil || configuration().selectedDeviceFamily == "razer.naga.pro" { nagaInput.refresh(wait: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.competingManagers.isEmpty {
                self.stop(); self.stopped("Stopped because SteerMouse Manager started.")
            } else if !AXIsProcessTrusted() || !CGPreflightListenEventAccess() {
                self.stop(); self.stopped("Stopped because input permission was removed.")
            } else {
                let present = Set(self.devices().map { $0.connectionID }).union(self.nagaInput.connectionIDs)
                for id in Array(self.states.keys) where !id.hasPrefix("unknown.") && !present.contains(id) {
                    if let state = self.states.removeValue(forKey: id) { self.releaseRawPassthrough(state) }
                }
                if self.configuration().selectedDeviceFamily == nil || self.configuration().selectedDeviceFamily == "razer.naga.pro" { self.nagaInput.refresh() }
            }
        }
        return nil
    }

    func stop() {
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll(); competingManagers.removeAll()
        timer?.invalidate(); timer = nil
        shortcutRepeatWork?.cancel(); shortcutRepeatWork = nil
        for event in heldShortcuts.releaseAll() { postHeldShortcut(event) }
        nagaInput.stop(); rawKeyboardConnections.removeAll()
        for state in states.values { releaseRawPassthrough(state) }
        modifierState.reset()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; states.removeAll()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent, allowMousePrelude: Bool = true, replayProfile: MouseProfile? = nil) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                self?.stop(); self?.stopped("macOS paused mouse handling. Press Start to resume.")
            }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != generatedTag else {
            return Unmanaged.passUnretained(event)
        }
        if type == .mouseMoved {
            // Raw/locked-cursor apps can deliver thousands of these per second.
            // Preserve the original event and deltas without HID/app lookups.
            let held = heldShortcuts.heldModifiers
            if !held.isEmpty { event.flags.formUnion(eventFlags(held, includeDeviceFlags: true)) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
            let held = heldShortcuts.heldModifiers
            if !held.isEmpty { event.flags.formUnion(eventFlags(held, includeDeviceFlags: true)) }
            let sender = UInt64(bitPattern: event.getIntegerValueField(senderField))
            let device = DeviceEndpoint.matching(senderID: sender, in: devices())
            let connection = device?.connectionID ?? "unknown.\(sender)"
            guard let state = states[connection] else { return Unmanaged.passUnretained(event) }
            // A real drag must still release a delayed calibrated click prefix
            // before consulting that press's captured suppression decision.
            if state.mousePrelude.pendingDeadline != nil {
                replayMousePrelude(state.mousePrelude.flush(), state: state)
                scheduleMousePreludeExpiry(state: state, connection: connection)
            }
            let button = type == .leftMouseDragged ? 0 : type == .rightMouseDragged ? 1 : Int(event.getIntegerValueField(.mouseEventButtonNumber))
            return state.router.suppressesDrag(button: button) ? nil : Unmanaged.passUnretained(event)
        }
        let config = configuration()
        let sender = UInt64(bitPattern: event.getIntegerValueField(senderField))
        let device = DeviceEndpoint.matching(senderID: sender, in: devices())
        if type == .flagsChanged {
            // Mouse-generated modifier reports must not clear modifiers held on
            // the user's separate keyboard. No ordinary keyboard keys are read.
            if device?.identity.canonicalFamily != "razer.naga.pro" {
                modifierState.changed(modifierMask(event.flags))
            }
            event.flags.formUnion(eventFlags(heldShortcuts.heldModifiers, includeDeviceFlags: true))
            return Unmanaged.passUnretained(event)
        }
        // A held modifier key must compose with ordinary keyboard, mouse and
        // wheel input, including devices outside the remapped mouse family.
        event.flags.formUnion(eventFlags(heldShortcuts.heldModifiers, includeDeviceFlags: true))
        let modifiers = device?.identity.canonicalFamily == "razer.naga.pro"
            ? modifierState.resolve(event: modifierMask(event.flags), hardware: modifierMask(CGEventSource.flagsState(.hidSystemState)))
            : modifierMask(event.flags)
        let keyboard = type == .keyDown || type == .keyUp
        let movement = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type)
        if keyboard {
            // Keyboard translation is confined to positively identified original Naga endpoints.
            guard device?.identity.canonicalFamily == "razer.naga.pro" else { return Unmanaged.passUnretained(event) }
            if let device, nagaInput.owns(device) {
                let layout = config.nagaInputLayout(for: device.identity)
                let key = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
                // Raw reports own these keys on this exact Naga connection. If macOS resumes
                // emitting their Quartz events, consume them to avoid a second
                // action or duplicate native Passthrough output.
                if NagaBluetoothReportDecoder.handles(keyCode: key, layout: layout) { return nil }
            }
        }
        if let family = config.selectedDeviceFamily {
            guard device?.identity.canonicalFamily == family else {
                return Unmanaged.passUnretained(event)
            }
        }
        let connection = device?.connectionID ?? "unknown.\(sender)"
        let state = states[connection] ?? InputState(); states[connection] = state
        let profile = replayProfile ?? config.profile(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        let layout = device.map { config.nagaInputLayout(for: $0.identity) } ?? NagaKeyboardLayout()
        var prelude: MousePrelude?
        if allowMousePrelude, device?.identity.canonicalFamily == "razer.naga.pro", !layout.doubleClickPrefixes.isEmpty {
            if type == .leftMouseDown || type == .leftMouseUp {
                keyboardToken &+= 1
                let token = keyboardToken
                guard let copy = event.copy() else {
                    replayMousePrelude(state.mousePrelude.flush(), state: state)
                    scheduleMousePreludeExpiry(state: state, connection: connection)
                    return handle(type, event, allowMousePrelude: false, replayProfile: profile)
                }
                state.mousePreludeEvents[token] = RecordedMouseInput(event: copy, profile: profile)
                let result = state.mousePrelude.mouse(token: token, phase: type == .leftMouseDown ? .down : .up,
                    now: ProcessInfo.processInfo.systemUptime)
                replayMousePrelude(result.replayTokens, state: state)
                scheduleMousePreludeExpiry(state: state, connection: connection)
                if result.consume { return nil }
                state.mousePreludeEvents.removeValue(forKey: token)
            } else if type == .keyDown {
                let key = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
                prelude = takeMousePrelude(key: key, state: state, connection: connection, layout: layout)
            } else if type != .mouseMoved {
                replayMousePrelude(state.mousePrelude.flush(), state: state)
                scheduleMousePreludeExpiry(state: state, connection: connection)
            }
        }
        if keyboard, let device {
            return handleKeyboard(type, event, state: state, device: device, profile: profile,
                layout: layout, prelude: prelude)
        }
        if type == .scrollWheel {
            var wheelMapped = false
            let axisFields: [[CGEventField]] = [
                [.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1],
                [.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2],
                [.scrollWheelEventDeltaAxis3, .scrollWheelEventFixedPtDeltaAxis3, .scrollWheelEventPointDeltaAxis3]]
            // Chords use physical direction before Wheel speed/reversal. Ignore
            // momentum: an inertial tail is not a fresh wheel input.
            if event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 {
                for axis in 0..<2 {
                    let delta = axisFields[axis].map { event.getDoubleValueField($0) }.first { $0 != 0 } ?? 0
                    guard delta != 0, let origin = event.copy() else { continue }
                    for other in 0..<3 where other != axis {
                        for field in axisFields[other] { origin.setDoubleValueField(field, value: 0) }
                    }
                    let direction = WheelDirection.direction(axis: axis, delta: delta > 0 ? 1 : -1)
                    let decision = state.router.routeScroll(direction: direction, modifiers: modifiers)
                    guard decision.suppress else { continue }
                    for emission in decision.emissions { execute(emission, state: state, fallback: origin) }
                    for field in axisFields[axis] { event.setDoubleValueField(field, value: 0) }
                    wheelMapped = true
                }
            }
            if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
                let mapped = WheelActionRouter.route(deltas: [event.getIntegerValueField(.scrollWheelEventDeltaAxis1), event.getIntegerValueField(.scrollWheelEventDeltaAxis2)],
                    continuous: false, profile: profile, modifiers: modifiers)
                for action in mapped {
                    let axis = action.axis
                    var binding = action.binding
                    wheelMapped = true
                    if binding.action == .scroll {
                        let values = state.mappedWheel.transform([Int64(binding.scrollY), Int64(binding.scrollX), 0], continuous: false, profile: profile)
                        binding.scrollY = Int(clamping: values[0]); binding.scrollX = Int(clamping: values[1])
                    }
                    execute(binding, origin: event)
                    let fields: [CGEventField] = axis == 0 ? [.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1] : [.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2]
                    for field in fields { event.setIntegerValueField(field, value: 0) }
                }
            }
            if wheelMapped && axisFields.joined().allSatisfy({ event.getDoubleValueField($0) == 0 }) { return nil }
            transformWheel(event, state: state, profile: profile)
            return Unmanaged.passUnretained(event)
        }
        if movement {
            // Native cursor positions and relative deltas must remain untouched.
            // Sensitivity is an explicit hardware DPI setting, outside this tap.
            if type == .mouseMoved { return Unmanaged.passUnretained(event) }
        }
        let button: Int
        let phase: ButtonPhase
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
        if phase == .down && state.origins[button] == nil { state.origins[button] = event.copy() }
        let decision = state.router.route(button: button, phase: phase, profile: profile, modifiers: modifiers)
        for emission in decision.emissions { execute(emission, state: state, fallback: event) }
        if phase == .up { state.origins.removeValue(forKey: button) }
        if phase != .drag {
            let label = NagaDPIButton(rawValue: button)?.title ?? (button >= 100 ? "Naga side \(button - 99)" : "Mouse button \(button + 1)")
            let detail = decision.suppress ? "handled" : "passthrough"
            let message = "\(label) · \(phase == .down ? "pressed" : "released") · \(detail) · \(device?.identity.transport ?? "mouse")"
            DispatchQueue.main.async { [weak self] in self?.observedButton(button, phase); self?.observed(message) }
        }
        return decision.suppress ? nil : Unmanaged.passUnretained(event)
    }

    private func handleKeyboard(_ type: CGEventType, _ event: CGEvent, state: InputState,
        device: DetectedDevice, profile: MouseProfile, layout: NagaKeyboardLayout, prelude: MousePrelude?, fromRaw: Bool = false) -> Unmanaged<CGEvent>? {
        keyboardToken &+= 1
        let token = keyboardToken
        state.keyboardEvents[token] = event.copy()
        if fromRaw { state.rawKeyboardTokens.insert(token) }
        if let prelude { state.keyboardPreludes[token] = prelude }
        // The stable keyboard transition snapshot survives mouse reports that
        // clear the polled hardware table. Releases retain down-time modifiers.
        let modifiers = modifierState.resolve(event: modifierMask(event.flags),
            hardware: modifierMask(CGEventSource.flagsState(.hidSystemState)))
        let input = NagaKeyboardInput(token: token, keyCode: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)),
            phase: type == .keyDown ? .down : .up, modifiers: modifiers, profile: profile)
        let result = state.keyboard.route(input, now: ProcessInfo.processInfo.systemUptime, layout: layout)
        processKeyboard(result.dispatches, state: state, transport: device.identity.transport)
        scheduleKeyboardExpiry(state: state, connection: device.connectionID, transport: device.identity.transport)
        return result.consume ? nil : Unmanaged.passUnretained(event)
    }

    private func processKeyboard(_ dispatches: [NagaKeyboardDispatch], state: InputState, transport: String) {
        for input in dispatches {
            guard let origin = state.keyboardEvents[input.originToken] ?? state.origins[input.button]
                ?? input.nativeTokens.compactMap({ state.keyboardEvents[$0] }).first else { continue }
            let firstDown = input.phase == .down && state.origins[input.button] == nil
            if let prelude = state.keyboardPreludes.removeValue(forKey: input.originToken) {
                if prelude.keySequences.contains(input.replayKeys) {
                    state.keyboardMouseReplay[input.button] = prelude.events
                } else {
                    // A partial/nonmatching macro must not eat ordinary clicks.
                    replayMouseInputs(prelude.events)
                }
            }
            if firstDown {
                state.origins[input.button] = origin
                state.keyboardReplayKeys[input.button] = input.replayKeys
            }
            let decision = state.router.route(button: input.button, phase: input.phase,
                profile: input.profile, modifiers: input.modifiers)
            for emission in decision.emissions {
                execute(emission, state: state, fallback: origin)
            }
            if !decision.suppress {
                if firstDown { for original in state.keyboardMouseReplay[input.button] ?? [] { post(original.event) } }
                for token in input.nativeTokens {
                    if let native = state.keyboardEvents[token] {
                        if state.rawKeyboardTokens.contains(token) {
                            let key = UInt16(clamping: native.getIntegerValueField(.keyboardEventKeycode))
                            state.rawPassthroughKeys.posted(keyCode: key, phase: native.type == .keyDown ? .down : .up)
                        }
                        post(native)
                    }
                }
            }
            let detail = decision.suppress ? "handled" : "passthrough"
            let flags = input.modifiers.isEmpty ? "" : "\(input.modifiers.title) · "
            let label = NagaDPIButton(rawValue: input.button)?.title ?? "Naga side \(input.button - 99)"
            let message = "\(label) · \(input.phase == .down ? "pressed" : "released") · \(flags)\(detail) · \(transport)"
            DispatchQueue.main.async { [weak self] in self?.observedButton(input.button, input.phase); self?.observed(message) }
            if input.phase == .up {
                state.origins.removeValue(forKey: input.button)
                state.keyboardReplayKeys.removeValue(forKey: input.button)
                state.keyboardMouseReplay.removeValue(forKey: input.button)
            }
        }
        let retained = state.keyboard.retainedTokens
        state.keyboardEvents = state.keyboardEvents.filter { retained.contains($0.key) }
        state.rawKeyboardTokens.formIntersection(retained)
        state.keyboardPreludes = state.keyboardPreludes.filter { retained.contains($0.key) }
    }

    private var rawKeyboardConnections: [UInt64: String] = [:]
    private func handleRawKeyboard(_ id: UInt64, reportID: UInt32, bytes: [UInt8]) {
        guard tap != nil, let device = devices().first(where: { $0.id == id }) ?? nagaInput.identity(id),
              device.identity.canonicalFamily == "razer.naga.pro" else { return }
        let config = configuration()
        guard config.selectedDeviceFamily == nil || config.selectedDeviceFamily == device.identity.canonicalFamily else { return }
        rawKeyboardConnections[id] = device.connectionID
        let state = states[device.connectionID] ?? InputState(); states[device.connectionID] = state
        let layout = config.nagaInputLayout(for: device.identity)
        let transitions = state.bluetoothReports.route(reportID: reportID, bytes: bytes)
        guard !transitions.isEmpty else { return }
        let profile = config.profile(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        for input in transitions {
            guard NagaBluetoothReportDecoder.handles(keyCode: input.keyCode, layout: layout),
                  let event = CGEvent(keyboardEventSource: nil, virtualKey: input.keyCode, keyDown: input.phase == .down) else { continue }
            var flags = eventFlags(modifierState.resolve(event: [], hardware: modifierMask(CGEventSource.flagsState(.hidSystemState))).union(heldShortcuts.heldModifiers))
            flags.formUnion(eventFlags(heldShortcuts.heldModifiers, includeDeviceFlags: true))
            if input.modifiers.contains(.command) { flags.insert(.maskCommand) }
            if input.modifiers.contains(.shift) { flags.insert(.maskShift) }
            if input.modifiers.contains(.option) { flags.insert(.maskAlternate) }
            if input.modifiers.contains(.control) { flags.insert(.maskControl) }
            event.flags = flags
            event.location = CGEvent(source: nil)?.location ?? .zero
            let prelude = input.phase == .down && !layout.doubleClickPrefixes.isEmpty
                ? takeMousePrelude(key: input.keyCode, state: state, connection: device.connectionID, layout: layout) : nil
            _ = handleKeyboard(input.phase == .down ? .keyDown : .keyUp, event, state: state,
                device: device, profile: profile, layout: layout, prelude: prelude, fromRaw: true)
        }
    }
    private func releaseRawPassthrough(_ state: InputState) {
        for event in heldShortcuts.release(source: state.shortcutSource) { postHeldShortcut(event) }
        scheduleShortcutRepeats()
        state.router.reset()
        for key in state.rawPassthroughKeys.takeReleases() {
            guard let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else { continue }
            up.flags = CGEventSource.flagsState(.combinedSessionState); post(up)
        }
    }

    private func takeMousePrelude(key: UInt16, state: InputState, connection: String, layout: NagaKeyboardLayout) -> MousePrelude? {
        let result = state.mousePrelude.key(key, now: ProcessInfo.processInfo.systemUptime,
            allowedPrefixes: Set(layout.doubleClickPrefixes))
        replayMousePrelude(result.replayTokens, state: state)
        let events = result.matchedTokens.compactMap { state.mousePreludeEvents.removeValue(forKey: $0) }
        scheduleMousePreludeExpiry(state: state, connection: connection)
        return events.isEmpty ? nil : MousePrelude(events: events,
            keySequences: layout.sequences.filter { $0.keyCodes.first == key }.map(\.keyCodes))
    }

    private func replayMouseInputs(_ events: [RecordedMouseInput]) {
        for input in events {
            if handle(input.event.type, input.event, allowMousePrelude: false, replayProfile: input.profile) != nil {
                post(input.event)
            }
        }
    }

    private func replayMousePrelude(_ tokens: [UInt64], state: InputState) {
        replayMouseInputs(tokens.compactMap { state.mousePreludeEvents.removeValue(forKey: $0) })
    }

    private func scheduleMousePreludeExpiry(state: InputState, connection: String) {
        state.mousePreludeWork?.cancel(); state.mousePreludeWork = nil
        guard let deadline = state.mousePrelude.pendingDeadline else { return }
        let work = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state, self.tap != nil, self.states[connection] === state else { return }
            self.replayMousePrelude(state.mousePrelude.expire(now: ProcessInfo.processInfo.systemUptime), state: state)
            self.scheduleMousePreludeExpiry(state: state, connection: connection)
        }
        state.mousePreludeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, deadline - ProcessInfo.processInfo.systemUptime), execute: work)
    }

    private func scheduleKeyboardExpiry(state: InputState, connection: String, transport: String) {
        state.keyboardWork?.cancel(); state.keyboardWork = nil
        guard let deadline = state.keyboard.pendingDeadline else { return }
        let work = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state, self.tap != nil, self.states[connection] === state else { return }
            self.processKeyboard(state.keyboard.expire(now: ProcessInfo.processInfo.systemUptime), state: state, transport: transport)
            self.scheduleKeyboardExpiry(state: state, connection: connection, transport: transport)
        }
        state.keyboardWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, deadline - ProcessInfo.processInfo.systemUptime), execute: work)
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

    private func execute(_ emission: InputEmission, state: InputState, fallback: CGEvent) {
        let owner = ShortcutHoldOwner(source: state.shortcutSource, button: emission.button)
        if emission.phase == .up {
            for event in heldShortcuts.release(owner: owner) { postHeldShortcut(event) }
            scheduleShortcutRepeats(); return
        }
        if emission.phase == .down, let shortcut = emission.binding.heldShortcut {
            let events = heldShortcuts.press(owner: owner, shortcut: shortcut,
                repeating: emission.binding.shortcutBehavior == .repeatWhileHeld,
                now: ProcessInfo.processInfo.systemUptime, delay: NSEvent.keyRepeatDelay, interval: NSEvent.keyRepeatInterval)
            for event in events { postHeldShortcut(event) }
            scheduleShortcutRepeats(); return
        }
        let origin = state.origins[emission.button] ?? fallback
        if emission.binding.action == .passthrough, let keys = state.keyboardReplayKeys[emission.button] {
            for original in state.keyboardMouseReplay[emission.button] ?? [] { post(original.event) }
            for key in keys { shortcut(key, modifierMask(origin.flags)) }
        } else { execute(emission.binding, origin: origin) }
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
        case .zoomIn: shortcut(24, .command)
        case .zoomOut: shortcut(27, .command)
        case .playPause: mediaKey(16)
        case .nextTrack: mediaKey(17)
        case .previousTrack: mediaKey(18)
        case .volumeUp: mediaKey(0)
        case .volumeDown: mediaKey(1)
        case .mute: mediaKey(7)
        case .open:
            if let target = binding.openTarget {
                DispatchQueue.main.async {
                    let url = target.hasPrefix("/") ? URL(fileURLWithPath: target) : URL(string: target)
                    if let url, url.isFileURL || ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
                }
            }
        case .cursorSnap:
            // An explicit one-shot mapped action; never used for sensitivity.
            let point = snapPoint(destination: binding.snapDestination, cursor: origin.location)
            _ = CGWarpMouseCursorPosition(point)
        case .modifierKey:
            guard let shortcut = binding.heldShortcut else { return }
            // Wheel and unresolved-prefix outputs have no lasting physical
            // hold, so complete this modifier-only tap in the same dispatch.
            let owner = ShortcutHoldOwner(source: UUID().uuidString, button: 0)
            for output in heldShortcuts.press(owner: owner, shortcut: shortcut, repeating: false,
                now: ProcessInfo.processInfo.systemUptime, delay: 0, interval: 1) { postHeldShortcut(output) }
            for output in heldShortcuts.release(owner: owner) { postHeldShortcut(output) }
        case .shortcut: if let key = binding.shortcut { shortcut(key) }
        case .mouseClick: click(button: binding.mouseButton, location: origin.location, flags: origin.flags)
        case .scroll:
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                wheel1: Int32(clamping: binding.scrollY), wheel2: Int32(clamping: binding.scrollX), wheel3: 0) else { return }
            post(event)
        }
    }

    private func mediaKey(_ code: Int) {
        for state in [0xA, 0xB] {
            if let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: (code << 16) | (state << 8), data2: -1)?.cgEvent { post(event) }
        }
    }
    private func snapPoint(destination: String?, cursor: CGPoint) -> CGPoint {
        if destination == "window", let app = NSWorkspace.shared.frontmostApplication,
           let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] {
            for window in windows where (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier &&
                (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 {
                if let bounds = window[kCGWindowBounds as String] as? [String: Any],
                   let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) { return CGPoint(x: frame.midX, y: frame.midY) }
            }
        }
        let frames = NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: (NSScreen.screens.first?.frame.height ?? 0) - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
        }
        let frame = frames.first { $0.contains(cursor) } ?? frames.first ?? CGRect(origin: cursor, size: .zero)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func replay(_ origin: CGEvent) {
        if origin.type == .keyDown {
            shortcut(UInt16(clamping: origin.getIntegerValueField(.keyboardEventKeycode)), modifierMask(origin.flags))
        } else {
            click(button: Int(origin.getIntegerValueField(.mouseEventButtonNumber)), location: origin.location, flags: origin.flags)
        }
    }

    private func shortcut(_ code: UInt16, _ modifiers: ModifierMask) {
        shortcut(Shortcut(keyCode: code, modifiers: modifiers))
    }
    private func shortcut(_ shortcut: Shortcut) {
        let edges = shortcut.edges
        let events = edges.compactMap { edge -> CGEvent? in
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: edge.keyCode, keyDown: edge.phase == .down) else { return nil }
            event.flags = eventFlags(edge.modifiers)
            if shortcut.functionNumber != nil { event.flags.insert(.maskSecondaryFn) }
            if var character = edge.unicode { event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character) }
            return event
        }
        guard events.count == 2 else { return }
        for event in events { post(event) }
    }

    private func postHeldShortcut(_ output: HeldShortcutEvent) {
        let edge = output.edge
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: edge.keyCode, keyDown: edge.phase == .down) else { return }
        if ModifierKey.allCases.contains(where: { $0.keyCode == edge.keyCode }) {
            let physical = modifierState.resolve(event: [], hardware: modifierMask(CGEventSource.flagsState(.hidSystemState)))
            // A real keyboard still owning this key must not get a synthetic
            // release. Its normal flagsChanged release will arrive separately.
            guard let flags = output.modifierOutputFlags(physical: physical) else { return }
            event.type = .flagsChanged
            let hardware = CGEventSource.flagsState(.hidSystemState)
            let tracked: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            event.flags = eventFlags(flags).union(eventFlags(edge.modifiers, includeDeviceFlags: true)).union(hardware.subtracting(tracked))
        } else { event.flags = eventFlags(edge.modifiers) }
        if edge.unicode != nil || ShortcutKeyChoice.nativeFunctionCodes.contains(edge.keyCode) { event.flags.insert(.maskSecondaryFn) }
        if var character = edge.unicode { event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character) }
        event.setIntegerValueField(.keyboardEventAutorepeat, value: output.isRepeat ? 1 : 0)
        event.location = CGEvent(source: nil)?.location ?? .zero
        post(event)
    }

    private func scheduleShortcutRepeats() {
        shortcutRepeatWork?.cancel(); shortcutRepeatWork = nil
        guard tap != nil, let deadline = heldShortcuts.nextDeadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.tap != nil else { return }
            for event in self.heldShortcuts.repeats(now: ProcessInfo.processInfo.systemUptime) { self.postHeldShortcut(event) }
            self.scheduleShortcutRepeats()
        }
        shortcutRepeatWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, deadline - ProcessInfo.processInfo.systemUptime), execute: work)
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
    private func eventFlags(_ modifiers: ModifierMask, includeDeviceFlags: Bool = false) -> CGEventFlags {
        var result: CGEventFlags = []
        if modifiers.contains(.command) { result.insert(.maskCommand) }
        if modifiers.contains(.shift) { result.insert(.maskShift) }
        if modifiers.contains(.option) { result.insert(.maskAlternate) }
        if modifiers.contains(.control) { result.insert(.maskControl) }
        if includeDeviceFlags {
            for key in ModifierKey.allCases where modifiers.contains(key.mask) { result.formUnion(CGEventFlags(rawValue: key.deviceFlag)) }
        }
        return result
    }
}
