import Foundation

/// Modifier-only output has no letter key and is held until its owner releases.
public enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case command, shift, option, control
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var mask: ModifierMask {
        switch self { case .command: return .command; case .shift: return .shift; case .option: return .option; case .control: return .control }
    }
    public var keyCode: UInt16 {
        switch self { case .command: return 55; case .shift: return 56; case .option: return 58; case .control: return 59 }
    }
    /// Left-key device bits from IOKit's IOLLEvent.h, alongside the generic
    /// Command/Shift/Option/Control bits carried by CGEventFlags.
    public var deviceFlag: UInt64 {
        switch self { case .command: return 0x08; case .shift: return 0x02; case .option: return 0x20; case .control: return 0x01 }
    }
    public var shortcut: Shortcut { Shortcut(keyCode: keyCode, modifiers: mask) }
}
public extension Shortcut {
    var modifierKey: ModifierKey? {
        guard functionKey == nil else { return nil }
        return ModifierKey.allCases.first { $0.keyCode == keyCode }
    }
}

public extension HeldShortcutEvent {
    /// Physical keys remain owned by the keyboard. Never synthesize their
    /// release, and preserve other physically held modifiers in every edge.
    func modifierOutputFlags(physical: ModifierMask) -> ModifierMask? {
        guard let key = ModifierKey.allCases.first(where: { $0.keyCode == edge.keyCode }),
              !physical.contains(key.mask) else { return nil }
        return edge.modifiers.union(physical)
    }
}
