import Foundation

public struct ShortcutHoldOwner: Hashable {
    public let source: String
    public let button: Int
    public init(source: String, button: Int) { self.source = source; self.button = button }
}
public struct HeldShortcutEvent: Equatable {
    public let edge: ShortcutKeyEdge
    public let isRepeat: Bool
}

/// Tracks posted keys independently of changing profiles and device instances.
/// Repeats are down events, followed by one final up, rather than repeated taps.
public struct HeldShortcuts {
    private struct Hold {
        let shortcut: Shortcut
        let order: UInt64
        let interval: TimeInterval
        var deadline: TimeInterval?
    }
    private var holds: [ShortcutHoldOwner: Hold] = [:]
    private var order: UInt64 = 0
    public init() {}
    private func sameKey(_ a: Shortcut, _ b: Shortcut) -> Bool {
        a.keyCode == b.keyCode && a.functionKey == b.functionKey
    }
    private var repeatOwners: [ShortcutHoldOwner] {
        holds.keys.filter { owner in
            guard let hold = holds[owner], hold.deadline != nil else { return false }
            return !holds.values.contains { $0.deadline != nil && sameKey($0.shortcut, hold.shortcut) && $0.order > hold.order }
        }
    }
    public var nextDeadline: TimeInterval? { repeatOwners.compactMap { holds[$0]?.deadline }.min() }

    public mutating func press(owner: ShortcutHoldOwner, shortcut: Shortcut, repeating: Bool,
                               now: TimeInterval, delay: TimeInterval, interval: TimeInterval) -> [HeldShortcutEvent] {
        guard holds[owner] == nil, shortcut.isValid, now.isFinite else { return [] }
        let alreadyDown = holds.values.contains { sameKey($0.shortcut, shortcut) }
        order &+= 1
        // Match AppKit's settings; disable repeats for non-finite/off values.
        let repeats = repeating && delay.isFinite && delay >= 0 && interval.isFinite && interval > 0
        holds[owner] = Hold(shortcut: shortcut, order: order, interval: max(0.001, interval),
                            deadline: repeats ? now + delay : nil)
        return alreadyDown ? [] : [HeldShortcutEvent(edge: shortcut.edges[0], isRepeat: false)]
    }
    public mutating func release(owner: ShortcutHoldOwner) -> [HeldShortcutEvent] {
        guard let hold = holds.removeValue(forKey: owner),
              !holds.values.contains(where: { sameKey($0.shortcut, hold.shortcut) }) else { return [] }
        return [HeldShortcutEvent(edge: hold.shortcut.edges[1], isRepeat: false)]
    }
    public mutating func repeats(now: TimeInterval) -> [HeldShortcutEvent] {
        guard now.isFinite else { return [] }
        return repeatOwners.sorted { holds[$0]!.order < holds[$1]!.order }.compactMap { owner in
            guard var hold = holds[owner], let deadline = hold.deadline, now >= deadline else { return nil }
            // A stalled run loop must not replay a burst of missed repeats.
            hold.deadline = now + hold.interval; holds[owner] = hold
            return HeldShortcutEvent(edge: hold.shortcut.edges[0], isRepeat: true)
        }
    }
    public mutating func release(source: String) -> [HeldShortcutEvent] {
        let owners = holds.keys.filter { $0.source == source }.sorted { holds[$0]!.order < holds[$1]!.order }
        return owners.flatMap { release(owner: $0) }
    }
    public mutating func releaseAll() -> [HeldShortcutEvent] {
        let owners = holds.keys.sorted { holds[$0]!.order < holds[$1]!.order }
        return owners.flatMap { release(owner: $0) }
    }
}
