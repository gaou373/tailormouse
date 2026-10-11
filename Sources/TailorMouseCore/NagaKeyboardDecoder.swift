import Foundation

public struct NagaKeySequence: Codable, Equatable {
    public var button: Int
    public var keyCodes: [UInt16]
    public init(button: Int, keyCodes: [UInt16]) { self.button = button; self.keyCodes = keyCodes }
}

/// Input calibration is independent of application actions and shared profiles.
public struct NagaKeyboardLayout: Codable, Equatable {
    public var keyOverrides: [String: Int]
    public var sequences: [NagaKeySequence]
    public init(keyOverrides: [String: Int] = [:], sequences: [NagaKeySequence] = []) {
        self.keyOverrides = keyOverrides; self.sequences = sequences
    }
    public var isValid: Bool {
        keyOverrides.allSatisfy { UInt16($0.key).map { $0 <= 127 } == true && (100...111).contains($0.value) } &&
        sequences.allSatisfy { (100...111).contains($0.button) && $0.keyCodes.count == 2 && $0.keyCodes.allSatisfy { $0 <= 127 } && button(for: $0.keyCodes[0]) != nil } &&
        Set(sequences.map { $0.keyCodes.map(String.init).joined(separator: ",") }).count == sequences.count
    }
    public func button(for key: UInt16) -> Int? { keyOverrides[String(key)] ?? NagaKeyMap.button(for: key) }
}

public struct NagaKeyboardInput {
    public let token: UInt64
    public let keyCode: UInt16
    public let phase: ButtonPhase
    public let modifiers: ModifierMask
    public let profile: MouseProfile
    public init(token: UInt64, keyCode: UInt16, phase: ButtonPhase, modifiers: ModifierMask, profile: MouseProfile) {
        self.token = token; self.keyCode = keyCode; self.phase = phase; self.modifiers = modifiers; self.profile = profile
    }
}

public struct NagaKeyboardDispatch {
    public let button: Int
    public let phase: ButtonPhase
    public let originToken: UInt64
    public let nativeTokens: [UInt64]
    public let replayKeys: [UInt16]
    public let modifiers: ModifierMask
    public let profile: MouseProfile
}
public struct NagaKeyboardResult {
    public let consume: Bool
    public let dispatches: [NagaKeyboardDispatch]
}

/// Recognizes a captured two-key onboard macro without firing its prefix action.
/// A held prefix resolves as its ordinary button; a released prefix waits briefly
/// for the macro suffix. Native events are retained for explicit Passthrough.
public struct NagaKeyboardDecoder {
    // Captured onboard macros place their second key about 170 ms after the first.
    public static let sequenceWindow: TimeInterval = 0.25
    private struct Held {
        let button: Int
        let origin: NagaKeyboardInput
        let replayKeys: [UInt16]
    }
    private struct Pending {
        let button: Int
        let down: NagaKeyboardInput
        let deadline: TimeInterval
        let candidates: [NagaKeySequence]
        var up: NagaKeyboardInput?
    }
    private var held: [UInt16: Held] = [:]
    private var pending: Pending?
    public init() {}
    public var pendingDeadline: TimeInterval? { pending?.deadline }
    public var retainedTokens: Set<UInt64> {
        guard let pending else { return [] }
        return Set([pending.down.token] + (pending.up.map { [$0.token] } ?? []))
    }
    public mutating func reset() { held.removeAll(); pending = nil }

    public mutating func expire(now: TimeInterval) -> [NagaKeyboardDispatch] {
        guard let pending, now >= pending.deadline else { return [] }
        return flushPending()
    }

    public mutating func route(_ input: NagaKeyboardInput, now: TimeInterval, layout: NagaKeyboardLayout) -> NagaKeyboardResult {
        var output = expire(now: now)
        if input.phase == .up {
            if var p = pending, p.down.keyCode == input.keyCode {
                p.up = input; pending = p
                return NagaKeyboardResult(consume: true, dispatches: output)
            }
            if let h = held.removeValue(forKey: input.keyCode) {
                output.append(dispatch(h, phase: .up, tokens: [input.token]))
                return NagaKeyboardResult(consume: true, dispatches: output)
            }
            // A key held before Start or recovery must retain its native release.
            return NagaKeyboardResult(consume: false, dispatches: output)
        }
        guard input.phase == .down else { return NagaKeyboardResult(consume: false, dispatches: output) }
        if let h = held[input.keyCode] {
            output.append(dispatch(h, phase: .down, tokens: [input.token]))
            return NagaKeyboardResult(consume: true, dispatches: output)
        }
        if let p = pending {
            if p.down.keyCode == input.keyCode, p.up == nil {
                output += flushPending()
                if let h = held[input.keyCode] { output.append(dispatch(h, phase: .down, tokens: [input.token])) }
                return NagaKeyboardResult(consume: true, dispatches: output)
            }
            if let up = p.up, p.down.modifiers == input.modifiers,
               let sequence = p.candidates.first(where: { $0.keyCodes[1] == input.keyCode }) {
                pending = nil
                let h = Held(button: sequence.button, origin: p.down, replayKeys: sequence.keyCodes)
                held[input.keyCode] = h
                output.append(dispatch(h, phase: .down, tokens: [p.down.token, up.token, input.token]))
                return NagaKeyboardResult(consume: true, dispatches: output)
            }
            output += flushPending()
        }
        guard let button = layout.button(for: input.keyCode) else { return NagaKeyboardResult(consume: false, dispatches: output) }
        let candidates = layout.sequences.filter { $0.keyCodes.count == 2 && $0.keyCodes[0] == input.keyCode }
        if !candidates.isEmpty {
            pending = Pending(button: button, down: input, deadline: now + Self.sequenceWindow, candidates: candidates)
        } else {
            let h = Held(button: button, origin: input, replayKeys: [input.keyCode])
            held[input.keyCode] = h
            output.append(dispatch(h, phase: .down, tokens: [input.token]))
        }
        return NagaKeyboardResult(consume: true, dispatches: output)
    }

    private func dispatch(_ held: Held, phase: ButtonPhase, tokens: [UInt64]) -> NagaKeyboardDispatch {
        NagaKeyboardDispatch(button: held.button, phase: phase, originToken: held.origin.token,
            nativeTokens: tokens, replayKeys: held.replayKeys, modifiers: held.origin.modifiers, profile: held.origin.profile)
    }
    private mutating func flushPending() -> [NagaKeyboardDispatch] {
        guard let p = pending else { return [] }
        pending = nil
        // The original mapping and modifiers are captured before the delay.
        let resolved = Held(button: p.button, origin: p.down, replayKeys: [p.down.keyCode])
        var output = [dispatch(resolved, phase: .down, tokens: [p.down.token])]
        if let up = p.up { output.append(dispatch(resolved, phase: .up, tokens: [up.token])) }
        else { held[p.down.keyCode] = resolved }
        return output
    }
}
