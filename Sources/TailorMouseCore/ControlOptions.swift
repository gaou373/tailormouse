import Foundation

public enum ActionCategory: String, CaseIterable, Identifiable {
    case click = "Click", scroll = "Scroll", shortcut = "Keyboard Shortcut", system = "System Control"
    case zoom = "Zoom", mission = "Mission Control", music = "Music Control", application = "Application Switcher"
    case snapping = "Cursor Snapping", open = "Open", none = "No Action"
    public var id: String { rawValue }
    public var actions: [ButtonAction] {
        switch self {
        case .click: return [.mouseClick, .passthrough]
        case .scroll: return [.scroll]
        case .shortcut: return [.shortcut]
        case .system: return [.back, .forward, .copy, .paste, .cut, .undo, .redo, .selectAll, .escape, .enter, .space, .volumeUp, .volumeDown, .mute]
        case .zoom: return [.zoomIn, .zoomOut]
        case .mission: return [.missionControl]
        case .music: return [.playPause, .nextTrack, .previousTrack]
        case .application: return [.appSwitcher]
        case .snapping: return [.cursorSnap]
        case .open: return [.open]
        case .none: return [.disabled]
        }
    }
    public static func category(for action: ButtonAction, wheel: Bool = false) -> Self {
        if wheel && action == .passthrough { return .scroll }
        return allCases.first { $0.actions.contains(action) } ?? .none
    }
}

public enum WheelDirection: String, CaseIterable, Identifiable {
    case up, down, left, right
    public var id: String { rawValue }
    public var axis: Int { self == .up || self == .down ? 0 : 1 }
    public var sign: Int { self == .up || self == .left ? 1 : -1 }
    public var title: String { "Roll " + rawValue.capitalized }
    public static func direction(axis: Int, delta: Int64) -> Self { axis == 0 ? (delta > 0 ? .up : .down) : (delta > 0 ? .left : .right) }
}

public struct WheelMappedAction {
    public let axis: Int
    public let binding: ActionBinding
}
public enum WheelActionRouter {
    public static func route(deltas: [Int64], continuous: Bool, profile: MouseProfile, modifiers: ModifierMask) -> [WheelMappedAction] {
        guard !continuous else { return [] }
        return deltas.prefix(2).enumerated().compactMap { axis, delta in
            guard delta != 0 else { return nil }
            let binding = profile.wheelBinding(direction: .direction(axis: axis, delta: delta), modifiers: modifiers)
            return binding.action == .passthrough ? nil : WheelMappedAction(axis: axis, binding: binding)
        }
    }
}

public struct NativePointerValues: Codable, Equatable {
    public let resolution: Int64
    public let acceleration: Int64
    public init(resolution: Int64, acceleration: Int64) { self.resolution = resolution; self.acceleration = acceleration }
    public var isValidReference: Bool {
        resolution > 0 && resolution <= Int64(Int32.max) && (-65536...Int64(Int32.max)).contains(acceleration)
    }
    public func target(profile: MouseProfile, reference: Self? = nil) throws -> Self {
        let baseline = reference ?? self
        let gain = profile.pointerSensitivity ?? 1
        guard gain.isFinite, (0.25...4).contains(gain), baseline.isValidReference,
              profile.pointerAcceleration.map({ $0.isFinite && (0...5).contains($0) }) ?? true else { throw NativePointerError.invalid }
        let scaled = Double(baseline.resolution) / gain
        guard scaled >= 1, scaled <= Double(Int32.max) else { throw NativePointerError.invalid }
        return Self(resolution: Int64(scaled.rounded()), acceleration: profile.pointerAcceleration.map { Int64(($0 * 65536).rounded()) } ?? baseline.acceleration)
    }
}
public enum NativePointerError: Error { case invalid, writeFailed, readbackFailed, recoveryFailed }
public enum NativePointerProperty: CaseIterable { case resolution, acceleration }
public enum NativePointerTransaction {
    public static func apply(before: NativePointerValues, target: NativePointerValues,
        write: (NativePointerProperty, Int64) throws -> Void, read: () throws -> NativePointerValues) throws {
        var attempted: [NativePointerProperty] = []
        func value(_ p: NativePointerProperty, _ v: NativePointerValues) -> Int64 { p == .resolution ? v.resolution : v.acceleration }
        do {
            for property in NativePointerProperty.allCases where value(property, before) != value(property, target) ||
                (property == .acceleration && before.resolution != target.resolution) {
                attempted.append(property); try write(property, value(property, target))
            }
            guard try read() == target else { throw NativePointerError.readbackFailed }
        } catch {
            let failure = error
            do {
                // Resolution must be restored before acceleration, whose
                // reapplication commits the effective native tracking curve.
                for property in NativePointerProperty.allCases where attempted.contains(property) ||
                    (property == .acceleration && attempted.contains(.resolution)) {
                    try write(property, value(property, before))
                }
                guard try read() == before else { throw NativePointerError.recoveryFailed }
            } catch { throw NativePointerError.recoveryFailed }
            throw failure
        }
    }
}
