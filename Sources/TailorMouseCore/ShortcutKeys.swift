import Foundation

public enum ShortcutKeyGroup: String, CaseIterable {
    case alphanumerics = "Alphanumerics", navigation = "Navigation", numpad = "Numpad", function = "F-Keys", others = "Others"
}
public struct ShortcutKeyChoice: Identifiable {
    public let title: String
    public let keyCode: UInt16
    public let functionKey: Int?
    public var id: String { functionKey.map { "function:\($0)" } ?? "key:\(keyCode)" }
    public func shortcut(modifiers: ModifierMask = []) -> Shortcut {
        Shortcut(keyCode: keyCode, modifiers: modifiers, functionKey: functionKey)
    }
    private static func keys(_ pairs: [(String, UInt16)]) -> [Self] {
        pairs.map { Self(title: $0.0, keyCode: $0.1, functionKey: nil) }
    }
    public static let nativeFunctionCodes: [UInt16] = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
    public static func choices(in group: ShortcutKeyGroup) -> [Self] {
        switch group {
        case .alphanumerics:
            return keys([("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),("H",4),("I",34),("J",38),("K",40),("L",37),("M",46),("N",45),("O",31),("P",35),("Q",12),("R",15),("S",1),("T",17),("U",32),("V",9),("W",13),("X",7),("Y",16),("Z",6),("0",29),("1",18),("2",19),("3",20),("4",21),("5",23),("6",22),("7",26),("8",28),("9",25)])
        case .navigation:
            return keys([("←",123),("→",124),("↑",126),("↓",125),("Tab",48),("Space",49),("Escape",53),("Return",36),("Backspace",51),("Home",115),("End",119),("Page Up",116),("Page Down",121),("Help",114),("Forward Delete",117)])
        case .numpad:
            return keys([("Numpad 0",82),("Numpad 1",83),("Numpad 2",84),("Numpad 3",85),("Numpad 4",86),("Numpad 5",87),("Numpad 6",88),("Numpad 7",89),("Numpad 8",91),("Numpad 9",92),("Numpad .",65),("Numpad +",69),("Numpad −",78),("Numpad ×",67),("Numpad ÷",75),("Numpad =",81),("Numpad Enter",76),("Numpad Clear",71)])
        case .function:
            return (1...24).map { number in
                Self(title: "F\(number)", keyCode: number <= 20 ? nativeFunctionCodes[number - 1] : 127,
                     functionKey: number > 20 ? number : nil)
            }
        case .others:
            return keys([("`",50),("−",27),("=",24),("[",33),("]",30),("\\",42),(";",41),("'",39),(",",43),(".",47),("/",44)])
        }
    }
    public static var all: [Self] { ShortcutKeyGroup.allCases.flatMap(choices) }
}
public struct ShortcutKeyEdge: Equatable {
    public let keyCode: UInt16
    public let unicode: UInt16?
    public let modifiers: ModifierMask
    public let phase: ButtonPhase
}
public extension Shortcut {
    var isValid: Bool {
        keyCode <= 127 && modifiers.rawValue <= 15 && (functionKey.map { (21...24).contains($0) && keyCode == 127 } ?? true)
    }
    var keyTitle: String {
        if let functionKey { return "F\(functionKey)" }
        return ShortcutKeyChoice.all.first { $0.functionKey == nil && $0.keyCode == keyCode }?.title ?? "Key \(keyCode)"
    }
    var functionNumber: Int? {
        functionKey ?? ShortcutKeyChoice.nativeFunctionCodes.firstIndex(of: keyCode).map { $0 + 1 }
    }
    /// A complete pair, including AppKit's reserved function character for F21–24.
    /// These extended keys require an app that recognizes character-based hotkeys.
    var edges: [ShortcutKeyEdge] {
        guard isValid else { return [] }
        let unicode = functionKey.map { UInt16(0xF703 + $0) }
        return [.down, .up].map { ShortcutKeyEdge(keyCode: keyCode, unicode: unicode, modifiers: modifiers, phase: $0) }
    }
}
public enum VisibleMouseButtons {
    public static func ordinary(observed: Set<Int>) -> [Int] {
        [0,1,2] + observed.filter { (3...31).contains($0) }.sorted()
    }
}
