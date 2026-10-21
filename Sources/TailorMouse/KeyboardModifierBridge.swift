import CoreGraphics
import Foundation
import TailorMouseCore

/// Compose held mouse modifiers before session-level shortcut listeners run.
/// Only keyboard edges are touched; no key is recorded, replaced or reposted.
final class KeyboardModifierBridge {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    let generatedTag: Int64
    var heldModifiers: () -> ModifierMask = { [] }
    var interrupted: () -> Void = {}

    init(generatedTag: Int64) { self.generatedTag = generatedTag }

    static func apply(to event: CGEvent, type: CGEventType, held: ModifierMask, generatedTag: Int64) {
        guard type == .keyDown || type == .keyUp,
              event.getIntegerValueField(.eventSourceUserData) != generatedTag else { return }
        var flags = CGEventFlags()
        for key in ModifierKey.allCases where held.contains(key.mask) {
            switch key {
            case .command: flags.insert(.maskCommand)
            case .shift: flags.insert(.maskShift)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            }
            flags.formUnion(CGEventFlags(rawValue: key.deviceFlag))
        }
        event.flags.formUnion(flags)
    }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let bridge = Unmanaged<KeyboardModifierBridge>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    DispatchQueue.main.async { [weak bridge] in bridge?.interrupted() }
                } else {
                    KeyboardModifierBridge.apply(to: event, type: type, held: bridge.heldModifiers(), generatedTag: bridge.generatedTag)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); return false
        }
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    deinit { stop() }
}
