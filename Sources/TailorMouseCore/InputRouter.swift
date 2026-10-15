import Foundation

public enum InputEmissionPhase { case complete, down, up }
public struct InputEmission: Equatable {
    public let button: Int
    public let binding: ActionBinding
    public let phase: InputEmissionPhase
    public init(button: Int, binding: ActionBinding, phase: InputEmissionPhase = .complete) {
        self.button = button; self.binding = binding; self.phase = phase
    }
}
public struct RoutingDecision: Equatable {
    public let suppress: Bool
    public let emissions: [InputEmission]
    public init(suppress: Bool, emissions: [InputEmission] = []) { self.suppress = suppress; self.emissions = emissions }
}

/// Actions retain their press-time mapping; held shortcuts emit matched edges.
/// Chord candidates defer extra-button clicks; unmatched candidates replay complete single actions.
public struct InputRouter {
    private struct Press {
        var binding: ActionBinding
        var suppress: Bool
        var pending: Bool
        var candidates: [ChordBinding]
        var held = false
    }
    private struct HeldChord { let members: Set<Int>; let binding: ActionBinding }
    private var active: [Int: Press] = [:]
    private var heldChords: [Int: HeldChord] = [:]
    public init() {}
    @discardableResult public mutating func reset() -> [InputEmission] {
        let releases = active.keys.sorted().compactMap { button -> InputEmission? in
            guard let press = active[button], press.held else { return nil }
            return InputEmission(button: button, binding: press.binding, phase: .up)
        } + heldChords.keys.sorted().map { InputEmission(button: $0, binding: heldChords[$0]!.binding, phase: .up) }
        active.removeAll(); heldChords.removeAll(); return releases
    }
    public mutating func route(button: Int, phase: ButtonPhase, profile: MouseProfile, modifiers: ModifierMask = []) -> RoutingDecision {
        guard (0...31).contains(button) || (100...111).contains(button) else { return RoutingDecision(suppress: false) }
        switch phase {
        case .drag:
            return RoutingDecision(suppress: active[button]?.suppress ?? false)
        case .up:
            guard let press = active.removeValue(forKey: button) else { return RoutingDecision(suppress: false) }
            var emissions: [InputEmission] = []
            for owner in heldChords.keys.sorted() where heldChords[owner]!.members.contains(button) {
                let chord = heldChords.removeValue(forKey: owner)!
                emissions.append(InputEmission(button: owner, binding: chord.binding, phase: .up))
            }
            if press.held { emissions.append(InputEmission(button: button, binding: press.binding, phase: .up)) }
            if press.pending {
                // The physical button is already up: replay a complete tap,
                // even if its single-button mapping normally supports holds.
                if press.suppress { emissions.append(InputEmission(button: button, binding: press.binding)) }
                emissions += flushPending()
            }
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
                        let held = chord.binding.heldShortcut != nil
                        if held { heldChords[button] = HeldChord(members: pressed, binding: chord.binding) }
                        return RoutingDecision(suppress: true, emissions: [InputEmission(button: button, binding: chord.binding, phase: held ? .down : .complete)])
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
            if suppress {
                let held = binding.heldShortcut != nil
                active[button]?.held = held
                emissions.append(InputEmission(button: button, binding: binding, phase: held ? .down : .complete))
            }
            return RoutingDecision(suppress: suppress, emissions: emissions)
        }
    }
    private mutating func flushPending() -> [InputEmission] {
        let buttons = active.keys.filter { active[$0]?.pending == true }.sorted()
        return buttons.compactMap { button in
            guard let press = active[button] else { return nil }
            active[button]?.pending = false; active[button]?.candidates = []
            let held = press.binding.heldShortcut != nil
            active[button]?.held = press.suppress && held
            return press.suppress ? InputEmission(button: button, binding: press.binding, phase: held ? .down : .complete) : nil
        }
    }
}
