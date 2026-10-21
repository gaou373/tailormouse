import CoreGraphics
import Foundation
import TailorMouseCore

@main
struct KeyboardModifierBridgeChecks {
    static func main() {
        let tag: Int64 = 0x5441494c4f52
        var holds = HeldShortcuts()
        let owner = ShortcutHoldOwner(source: "hyperspeed", button: 100)
        _ = holds.press(owner: owner, shortcut: ModifierKey.command.shortcut, repeating: false, now: 0, delay: 0, interval: 1)
        // Same event object reaches downstream listeners, with physical flags
        // preserved on both edges. There is no synthetic replacement key.
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: down)!
            event.flags = [.maskShift, .maskNumericPad]
            let originalKey = event.getIntegerValueField(.keyboardEventKeycode)
            KeyboardModifierBridge.apply(to: event, type: down ? .keyDown : .keyUp, held: holds.heldModifiers, generatedTag: tag)
            precondition(event.flags.contains([.maskCommand, .maskShift, .maskNumericPad]))
            precondition(event.flags.rawValue & ModifierKey.command.deviceFlag != 0)
            precondition(event.getIntegerValueField(.keyboardEventKeycode) == originalKey)
        }
        _ = holds.release(owner: owner)
        let released = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        released.flags = []
        KeyboardModifierBridge.apply(to: released, type: .keyDown, held: holds.heldModifiers, generatedTag: tag)
        precondition(released.flags.isEmpty)
        let generated = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true)!
        generated.flags = []
        generated.setIntegerValueField(.eventSourceUserData, value: tag)
        KeyboardModifierBridge.apply(to: generated, type: .keyDown, held: .command, generatedTag: tag)
        precondition(generated.flags.isEmpty)
        // Stop/disconnect recovery removes the bridge's held modifier input.
        _ = holds.press(owner: owner, shortcut: ModifierKey.command.shortcut, repeating: false, now: 1, delay: 0, interval: 1)
        _ = holds.releaseAll()
        precondition(holds.heldModifiers.isEmpty)
        print("4 keyboard modifier bridge checks passed (unposted events; no input interception).")
    }
}
