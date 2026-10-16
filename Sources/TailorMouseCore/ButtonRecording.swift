import Foundation

/// A single scoped mouse press, committed only after its matching release.
public struct MouseButtonRecording {
    public private(set) var active = false
    private var pending: (button: Int, source: String)?
    public init() {}
    public mutating func begin() { pending = nil; active = true }
    public mutating func cancel() { pending = nil; active = false }
    public mutating func scroll(direction: WheelDirection, source: String) -> Int? {
        guard active, pending == nil, !source.isEmpty else { return nil }
        cancel(); return direction.chordInput
    }
    public mutating func route(button: Int, phase: ButtonPhase, source: String) -> Int? {
        guard active, !source.isEmpty, (0...31).contains(button) || (100...111).contains(button) else { return nil }
        if phase == .down, pending == nil { pending = (button, source) }
        guard phase == .up, let press = pending, press.button == button, press.source == source else { return nil }
        cancel(); return button
    }
}
public enum ChordButtonChoices {
    public static let clicks = [0,1,2]
    public static let sideButtons = Array(100...111)
    public static let scrollDirections = WheelDirection.allCases.map(\.chordInput)
    public static func title(_ button: Int) -> String {
        if let direction = WheelDirection(chordInput: button) { return "Scroll " + direction.rawValue.capitalized }
        switch button {
        case 0: return "Left Click"
        case 1: return "Right Click"
        case 2: return "Middle Click"
        case 100...111: return "Side Button \(button - 99)"
        default: return "Button \(button + 1)"
        }
    }
    public static func extras(observed: Set<Int>, saved: [Int]) -> [Int] {
        Set(observed.union(saved)).filter { (3...31).contains($0) }.sorted()
    }
}
