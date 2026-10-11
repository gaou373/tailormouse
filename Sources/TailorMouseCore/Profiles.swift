import Foundation

public enum ButtonAction: String, Codable, CaseIterable, Identifiable {
    case passthrough, back, forward, copy, paste
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct MouseProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleIdentifier: String?
    public var invertWheel: Bool
    public var wheelSpeed: Double
    public var button3: ButtonAction
    public var button4: ButtonAction

    public init(id: UUID = UUID(), name: String = "Default", bundleIdentifier: String? = nil,
                invertWheel: Bool = false, wheelSpeed: Double = 1,
                button3: ButtonAction = .passthrough, button4: ButtonAction = .passthrough) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.invertWheel = invertWheel
        self.wheelSpeed = wheelSpeed
        self.button3 = button3
        self.button4 = button4
    }

    public var safeWheelSpeed: Double { wheelSpeed.isFinite ? min(4, max(0.25, wheelSpeed)) : 1 }
    public func action(for button: Int) -> ButtonAction {
        button == 3 ? button3 : button == 4 ? button4 : .passthrough
    }
}

public struct ProfileConfiguration: Codable, Equatable {
    public var schemaVersion = 1
    public var defaultProfile: MouseProfile
    public var appProfiles: [MouseProfile]
    public init(defaultProfile: MouseProfile = MouseProfile(), appProfiles: [MouseProfile] = []) {
        self.defaultProfile = defaultProfile
        self.appProfiles = appProfiles
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
            // Repeated downs must not emit another shortcut or change the pair's decision.
            if let action = active[button] { return ButtonDecision(suppress: action != .passthrough, emit: nil) }
            let action = profile.action(for: button)
            active[button] = action
            return ButtonDecision(suppress: action != .passthrough, emit: action == .passthrough ? nil : action)
        case .up:
            let action = active.removeValue(forKey: button) ?? .passthrough
            return ButtonDecision(suppress: action != .passthrough, emit: nil)
        case .drag:
            return ButtonDecision(suppress: active[button].map { $0 != .passthrough } ?? false, emit: nil)
        }
    }
}

/// Carries fractions between wheel ticks, so speeds below 1 do not discard every tick.
public struct WheelTransformer {
    private var remainder = [Double](repeating: 0, count: 3)
    private var previousFactor: Double?
    public init() {}
    public mutating func reset() { remainder = [0, 0, 0]; previousFactor = nil }
    public mutating func transform(_ deltas: [Int64], continuous: Bool, profile: MouseProfile) -> [Int64] {
        guard !continuous else { return deltas }
        let factor = profile.safeWheelSpeed * (profile.invertWheel ? -1 : 1)
        if factor != previousFactor { remainder = [0, 0, 0]; previousFactor = factor }
        return deltas.enumerated().map { axis, delta in
            guard axis < remainder.count else { return delta }
            let total = Double(delta) * factor + remainder[axis]
            let result = total.rounded(.towardZero)
            remainder[axis] = total - result
            return Int64(clamping: Int(result))
        }
    }
}
