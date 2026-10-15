public enum NagaModifiers {
    /// Receiver/wired side buttons use a different keyboard interface from the
    /// user's keyboard. Preserve onboard modifiers and include held keyboard
    /// modifiers even when that interface's event omits them.
    public static func resolve(event: ModifierMask, hardware: ModifierMask) -> ModifierMask {
        event.union(hardware)
    }
}

/// The receiver's keyboard reports can clear polled hardware flags even while
/// a modifier on another keyboard remains physically held. Retain the latest
/// keyboard flagsChanged snapshot until its next real transition.
public struct NagaModifierState {
    private var keyboard: ModifierMask?
    public init() {}
    public mutating func begin(snapshot: ModifierMask) { keyboard = snapshot }
    public mutating func changed(_ modifiers: ModifierMask) { keyboard = modifiers }
    public mutating func reset() { keyboard = nil }
    public func resolve(event: ModifierMask, hardware: ModifierMask) -> ModifierMask {
        NagaModifiers.resolve(event: event, hardware: keyboard ?? hardware)
    }
}
