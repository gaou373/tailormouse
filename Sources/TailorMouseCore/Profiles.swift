import Foundation

public enum ButtonAction: String, Codable, CaseIterable, Identifiable {
    case passthrough, disabled, back, forward, copy, paste, cut, undo, redo, selectAll
    case escape, enter, space, appSwitcher, missionControl, shortcut, mouseClick, scroll
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .selectAll: return "Select All"
        case .appSwitcher: return "App Switcher"
        case .missionControl: return "Mission Control"
        case .mouseClick: return "Mouse Click"
        default: return rawValue.capitalized
        }
    }
}

public struct ModifierMask: OptionSet, Codable, Equatable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let command = ModifierMask(rawValue: 1)
    public static let shift = ModifierMask(rawValue: 2)
    public static let option = ModifierMask(rawValue: 4)
    public static let control = ModifierMask(rawValue: 8)
    public var title: String {
        let labels: [(ModifierMask, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return labels.filter { contains($0.0) }.map { $0.1 }.joined()
    }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(UInt.self) }
    public func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
}

public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt16
    public var modifiers: ModifierMask
    public init(keyCode: UInt16, modifiers: ModifierMask = []) { self.keyCode = keyCode; self.modifiers = modifiers }
}

public struct ActionBinding: Codable, Equatable {
    public var action: ButtonAction
    public var shortcut: Shortcut?
    public var mouseButton: Int
    public var scrollX: Int
    public var scrollY: Int
    public init(action: ButtonAction = .passthrough, shortcut: Shortcut? = nil, mouseButton: Int = 0, scrollX: Int = 0, scrollY: Int = 3) {
        self.action = action; self.shortcut = shortcut; self.mouseButton = mouseButton; self.scrollX = scrollX; self.scrollY = scrollY
    }
}

public struct ChordBinding: Codable, Equatable, Identifiable {
    public var id: UUID
    public var buttons: [Int]
    public var modifiers: ModifierMask
    public var binding: ActionBinding
    public init(id: UUID = UUID(), buttons: [Int], modifiers: ModifierMask = [], binding: ActionBinding) {
        self.id = id; self.buttons = buttons; self.modifiers = modifiers; self.binding = binding
    }
    public var isValid: Bool {
        buttons.count >= 2 && Set(buttons).count == buttons.count && buttons.allSatisfy { (3...31).contains($0) || (100...111).contains($0) }
    }
}

public struct MouseProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleIdentifier: String?
    public var invertWheel: Bool
    public var wheelSpeed: Double
    public var button3: ButtonAction
    public var button4: ButtonAction
    public var horizontalWheelSpeed: Double
    public var invertHorizontalWheel: Bool
    public var pointerSpeed: Double
    public var bindings: [String: ActionBinding]
    public var modifierBindings: [String: ActionBinding]
    public var chords: [ChordBinding]

    public init(id: UUID = UUID(), name: String = "Default", bundleIdentifier: String? = nil,
                invertWheel: Bool = false, wheelSpeed: Double = 1,
                button3: ButtonAction = .passthrough, button4: ButtonAction = .passthrough,
                horizontalWheelSpeed: Double = 1, invertHorizontalWheel: Bool = false,
                pointerSpeed: Double = 1, bindings: [String: ActionBinding] = [:],
                modifierBindings: [String: ActionBinding] = [:], chords: [ChordBinding] = []) {
        self.id = id; self.name = name; self.bundleIdentifier = bundleIdentifier
        self.invertWheel = invertWheel; self.wheelSpeed = wheelSpeed
        self.button3 = button3; self.button4 = button4
        self.horizontalWheelSpeed = horizontalWheelSpeed; self.invertHorizontalWheel = invertHorizontalWheel
        self.pointerSpeed = pointerSpeed; self.bindings = bindings; self.modifierBindings = modifierBindings; self.chords = chords
    }
    private enum CodingKeys: String, CodingKey {
        case id, name, bundleIdentifier, invertWheel, wheelSpeed, button3, button4
        case horizontalWheelSpeed, invertHorizontalWheel, pointerSpeed, bindings, modifierBindings, chords
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Default",
                  bundleIdentifier: try c.decodeIfPresent(String.self, forKey: .bundleIdentifier),
                  invertWheel: try c.decodeIfPresent(Bool.self, forKey: .invertWheel) ?? false,
                  wheelSpeed: try c.decodeIfPresent(Double.self, forKey: .wheelSpeed) ?? 1,
                  button3: try c.decodeIfPresent(ButtonAction.self, forKey: .button3) ?? .passthrough,
                  button4: try c.decodeIfPresent(ButtonAction.self, forKey: .button4) ?? .passthrough,
                  horizontalWheelSpeed: try c.decodeIfPresent(Double.self, forKey: .horizontalWheelSpeed) ?? c.decodeIfPresent(Double.self, forKey: .wheelSpeed) ?? 1,
                  invertHorizontalWheel: try c.decodeIfPresent(Bool.self, forKey: .invertHorizontalWheel) ?? c.decodeIfPresent(Bool.self, forKey: .invertWheel) ?? false,
                  pointerSpeed: try c.decodeIfPresent(Double.self, forKey: .pointerSpeed) ?? 1,
                  bindings: try c.decodeIfPresent([String: ActionBinding].self, forKey: .bindings) ?? [:],
                  modifierBindings: try c.decodeIfPresent([String: ActionBinding].self, forKey: .modifierBindings) ?? [:],
                  chords: try c.decodeIfPresent([ChordBinding].self, forKey: .chords) ?? [])
    }
    private func safeSpeed(_ value: Double) -> Double { value.isFinite ? min(4, max(0.25, value)) : 1 }
    public var safeWheelSpeed: Double { safeSpeed(wheelSpeed) }
    public var safeHorizontalWheelSpeed: Double { safeSpeed(horizontalWheelSpeed) }
    public var safePointerSpeed: Double { safeSpeed(pointerSpeed) }
    public func actionBinding(for button: Int, modifiers: ModifierMask = []) -> ActionBinding {
        guard (0...31).contains(button) || (100...111).contains(button) else { return ActionBinding() }
        if let binding = modifierBindings["\(button):\(modifiers.rawValue)"] { return binding }
        if let binding = bindings[String(button)] { return binding }
        return ActionBinding(action: button == 3 ? button3 : button == 4 ? button4 : .passthrough)
    }
    public func action(for button: Int) -> ButtonAction { actionBinding(for: button).action }
    public func inheritedProfile(name: String, bundleIdentifier: String) -> MouseProfile {
        var profile = self; profile.id = UUID(); profile.name = name; profile.bundleIdentifier = bundleIdentifier; return profile
    }
}

public struct ProfileConfiguration: Codable, Equatable {
    public var schemaVersion = 2
    public var defaultProfile: MouseProfile
    public var appProfiles: [MouseProfile]
    public var selectedDeviceFamily: String?
    public init(defaultProfile: MouseProfile = MouseProfile(), appProfiles: [MouseProfile] = [], selectedDeviceFamily: String? = "razer.naga.pro") {
        self.defaultProfile = defaultProfile; self.appProfiles = appProfiles; self.selectedDeviceFamily = selectedDeviceFamily
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, defaultProfile, appProfiles, selectedDeviceFamily }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...2).contains(version) else { throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c, debugDescription: "Unsupported profile version \(version)") }
        defaultProfile = try c.decodeIfPresent(MouseProfile.self, forKey: .defaultProfile) ?? MouseProfile()
        appProfiles = try c.decodeIfPresent([MouseProfile].self, forKey: .appProfiles) ?? []
        selectedDeviceFamily = c.contains(.selectedDeviceFamily) ? try c.decodeIfPresent(String.self, forKey: .selectedDeviceFamily) : "razer.naga.pro"
        schemaVersion = 2
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(2, forKey: .schemaVersion)
        try c.encode(defaultProfile, forKey: .defaultProfile)
        try c.encode(appProfiles, forKey: .appProfiles)
        if let selectedDeviceFamily { try c.encode(selectedDeviceFamily, forKey: .selectedDeviceFamily) }
        else { try c.encodeNil(forKey: .selectedDeviceFamily) }
    }
    public func profile(for bundleIdentifier: String?) -> MouseProfile {
        guard let bundleIdentifier else { return defaultProfile }
        return appProfiles.first { $0.bundleIdentifier == bundleIdentifier } ?? defaultProfile
    }
}

public enum ButtonPhase { case down, up, drag }
public struct ButtonDecision: Equatable {
    public let suppress: Bool
    public let emit: ButtonAction?
}

/// The down event fixes the decision until its matching up, even if the profile changes.
public struct ButtonPairRouter {
    private var active: [Int: ButtonAction] = [:]
    public init() {}
    public mutating func reset() { active.removeAll() }
    public mutating func route(button: Int, phase: ButtonPhase, profile: MouseProfile) -> ButtonDecision {
        switch phase {
        case .down:
            if let action = active[button] { return ButtonDecision(suppress: action != .passthrough, emit: nil) }
            let action = profile.action(for: button); active[button] = action
            return ButtonDecision(suppress: action != .passthrough, emit: action == .passthrough ? nil : action)
        case .up:
            let action = active.removeValue(forKey: button) ?? .passthrough
            return ButtonDecision(suppress: action != .passthrough, emit: nil)
        case .drag:
            return ButtonDecision(suppress: active[button].map { $0 != .passthrough } ?? false, emit: nil)
        }
    }
}

/// Carries fractions between wheel ticks and resets them when the corresponding axis settings change.
public struct WheelTransformer {
    private var remainder = [Double](repeating: 0, count: 3)
    private var previousFactors: [Double]?
    public init() {}
    public mutating func reset() { remainder = [0, 0, 0]; previousFactors = nil }
    public mutating func transform(_ deltas: [Int64], continuous: Bool, profile: MouseProfile) -> [Int64] {
        guard !continuous else { return deltas }
        let factors = [profile.safeWheelSpeed * (profile.invertWheel ? -1 : 1), profile.safeHorizontalWheelSpeed * (profile.invertHorizontalWheel ? -1 : 1), 1]
        for axis in 0..<3 where previousFactors?[axis] != factors[axis] { remainder[axis] = 0 }
        previousFactors = factors
        return deltas.enumerated().map { axis, delta in
            guard axis < remainder.count else { return delta }
            return scaledInteger(delta, factor: factors[axis], remainder: &remainder[axis])
        }
    }
}

private func scaledInteger(_ delta: Int64, factor: Double, remainder: inout Double) -> Int64 {
    let total = Double(delta) * factor + remainder
    guard total < Double(Int64.max) else { remainder = 0; return Int64.max }
    guard total > Double(Int64.min) else { remainder = 0; return Int64.min }
    let result = total.rounded(.towardZero); remainder = total - result
    return Int64(result)
}

public struct PointerTransformer {
    private var remainder = [Double](repeating: 0, count: 2)
    private var previousFactor: Double?
    private var previousProfileID: UUID?
    public init() {}
    public mutating func reset() { remainder = [0, 0]; previousFactor = nil; previousProfileID = nil }
    public mutating func transform(_ deltas: [Int64], profile: MouseProfile) -> [Int64] {
        let factor = profile.safePointerSpeed
        if previousFactor != factor || previousProfileID != profile.id { remainder = [0, 0]; previousFactor = factor; previousProfileID = profile.id }
        return deltas.enumerated().map { axis, delta in
            guard axis < 2 else { return delta }
            return scaledInteger(delta, factor: factor, remainder: &remainder[axis])
        }
    }
    public mutating func transform(dx: Int64, dy: Int64, profile: MouseProfile) -> (dx: Int64, dy: Int64) {
        let result = transform([dx, dy], profile: profile); return (result[0], result[1])
    }
}
