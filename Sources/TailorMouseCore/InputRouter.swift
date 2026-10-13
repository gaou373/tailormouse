import Foundation

public struct InputEmission: Equatable {
    public let button: Int
    public let binding: ActionBinding
    public init(button: Int, binding: ActionBinding) { self.button = button; self.binding = binding }
}
public struct RoutingDecision: Equatable {
    public let suppress: Bool
    public let emissions: [InputEmission]
    public init(suppress: Bool, emissions: [InputEmission] = []) { self.suppress = suppress; self.emissions = emissions }
}

/// Complete actions are emitted once. Physical releases retain their press-time suppression decision.
/// Chord candidates defer extra-button clicks; unmatched candidates replay complete single actions.
public struct InputRouter {
    private struct Press {
        var binding: ActionBinding
        var suppress: Bool
        var pending: Bool
        var candidates: [ChordBinding]
    }
    private var active: [Int: Press] = [:]
    public init() {}
    public mutating func reset() { active.removeAll() }
    public mutating func route(button: Int, phase: ButtonPhase, profile: MouseProfile, modifiers: ModifierMask = []) -> RoutingDecision {
        guard (0...31).contains(button) || (100...111).contains(button) else { return RoutingDecision(suppress: false) }
        switch phase {
        case .drag:
            return RoutingDecision(suppress: active[button]?.suppress ?? false)
        case .up:
            guard let press = active.removeValue(forKey: button) else { return RoutingDecision(suppress: false) }
            guard press.pending else { return RoutingDecision(suppress: press.suppress) }
            var emissions = press.suppress ? [InputEmission(button: button, binding: press.binding)] : []
            emissions += flushPending()
            return RoutingDecision(suppress: press.suppress, emissions: emissions)
        case .down:
            if let press = active[button] { return RoutingDecision(suppress: press.suppress) }
            let binding = profile.actionBinding(for: button, modifiers: modifiers)
            let nativeClick = button < 3 && (binding.action == .passthrough || (binding.action == .mouseClick && binding.mouseButton == button))
            let pendingButtons = active.keys.filter { active[$0]?.pending == true }.sorted()
            var emissions: [InputEmission] = []
            if let first = pendingButtons.first {
                let pressed = Set(pendingButtons + [button])
                let candidates = (active[first]?.candidates ?? []).filter {
                    ($0.modifiers.isEmpty || $0.modifiers == modifiers) && pressed.isSubset(of: Set($0.buttons))
                }
                if !candidates.isEmpty {
                    active[button] = Press(binding: binding, suppress: !nativeClick, pending: true, candidates: candidates)
                    for member in pendingButtons { active[member]?.candidates = candidates }
                    let exact = candidates.filter { Set($0.buttons) == pressed }
                    if let chord = exact.first(where: { $0.modifiers == modifiers }) ?? exact.first {
                        // This second down has not reached macOS, so consume its
                        // whole pair. Earlier native primary clicks keep their up.
                        active[button]?.suppress = true
                        for member in pressed { active[member]?.pending = false; active[member]?.candidates = [] }
                        return RoutingDecision(suppress: true, emissions: [InputEmission(button: button, binding: chord.binding)])
                    }
                    return RoutingDecision(suppress: !nativeClick)
                }
                emissions = flushPending()
            }
            let eligible = profile.chords.filter { $0.isValid && $0.buttons.contains(button) && ($0.modifiers.isEmpty || $0.modifiers == modifiers) }
            if !eligible.isEmpty {
                active[button] = Press(binding: binding, suppress: !nativeClick, pending: true, candidates: eligible)
                return RoutingDecision(suppress: !nativeClick, emissions: emissions)
            }
            let suppress = binding.action != .passthrough
            active[button] = Press(binding: binding, suppress: suppress, pending: false, candidates: [])
            if suppress { emissions.append(InputEmission(button: button, binding: binding)) }
            return RoutingDecision(suppress: suppress, emissions: emissions)
        }
    }
    private mutating func flushPending() -> [InputEmission] {
        let buttons = active.keys.filter { active[$0]?.pending == true }.sorted()
        return buttons.compactMap { button in
            guard let press = active[button] else { return nil }
            active[button]?.pending = false; active[button]?.candidates = []
            return press.suppress ? InputEmission(button: button, binding: press.binding) : nil
        }
    }
}
