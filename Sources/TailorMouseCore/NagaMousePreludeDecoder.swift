import Foundation

public struct NagaMousePreludeResult {
    public let consume: Bool
    public let replayTokens: [UInt64]
    public let matchedTokens: [UInt64]
}

/// Recognizes the captured down/up/down/up burst immediately preceding an
/// onboard keyboard macro. Only explicitly calibrated Naga connections use it.
/// Unmatched clicks are released in order after at most twelve milliseconds.
public struct NagaMousePreludeDecoder {
    public static let window: TimeInterval = 0.012
    private var tokens: [UInt64] = []
    public private(set) var pendingDeadline: TimeInterval?
    public init() {}
    public mutating func reset() { tokens = []; pendingDeadline = nil }
    public mutating func flush() -> [UInt64] {
        let result = tokens; reset(); return result
    }
    public mutating func expire(now: TimeInterval) -> [UInt64] {
        guard let deadline = pendingDeadline, now >= deadline else { return [] }
        return flush()
    }
    public mutating func mouse(token: UInt64, phase: ButtonPhase, now: TimeInterval) -> NagaMousePreludeResult {
        var replay = expire(now: now)
        let expected: ButtonPhase = tokens.count.isMultiple(of: 2) ? .down : .up
        if tokens.count == 4 || phase != expected {
            replay += flush()
        }
        if tokens.isEmpty {
            guard phase == .down else { return .init(consume: false, replayTokens: replay, matchedTokens: []) }
            pendingDeadline = now + Self.window
        }
        tokens.append(token)
        return .init(consume: true, replayTokens: replay, matchedTokens: [])
    }
    public mutating func key(_ key: UInt16, now: TimeInterval, allowedPrefixes: Set<UInt16>) -> NagaMousePreludeResult {
        let replay = expire(now: now)
        if tokens.count == 4, allowedPrefixes.contains(key) {
            return .init(consume: false, replayTokens: replay, matchedTokens: flush())
        }
        return .init(consume: false, replayTokens: replay + flush(), matchedTokens: [])
    }
}
