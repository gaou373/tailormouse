import XCTest
@testable import TailorMouseCore

final class WheelBindingSwapTests: XCTestCase {
    func testVerticalSwapMovesCompleteShortcutsAndLeavesOtherSettingsAlone() {
        let up = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 123, modifiers: [.command, .shift]))
        let down = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 124, modifiers: .option))
        var profile = MouseProfile(wheelSpeed: 1.55, wheelBindings: [
            "up": up, "down": down, "left": ActionBinding(action: .copy),
            "up:1": ActionBinding(action: .paste)
        ])
        let original = profile
        profile.swapWheelBindings(horizontal: false)
        XCTAssertEqual(profile.wheelBinding(direction: .up), down)
        XCTAssertEqual(profile.wheelBinding(direction: .down), up)
        XCTAssertEqual(profile.wheelBindings["left"], original.wheelBindings["left"])
        XCTAssertEqual(profile.wheelBindings["up:1"], original.wheelBindings["up:1"])
        XCTAssertEqual(profile.wheelSpeed, 1.55)
        profile.swapWheelBindings(horizontal: false)
        XCTAssertEqual(profile, original)
    }

    func testHorizontalModifierSwapSnapshotsInheritedAssignmentAndPersists() throws {
        let flags: ModifierMask = [.command, .shift]
        let left = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 123))
        let right = ActionBinding(action: .shortcut, shortcut: Shortcut(keyCode: 124, modifiers: .control))
        var profile = MouseProfile(wheelBindings: ["left": left, "right": ActionBinding(action: .copy),
            "right:3": right, "up:3": ActionBinding(action: .paste)])
        let original = profile
        profile.swapWheelBindings(horizontal: true, modifiers: flags)
        XCTAssertEqual(profile.wheelBinding(direction: .left, modifiers: flags), right)
        XCTAssertEqual(profile.wheelBinding(direction: .right, modifiers: flags), left)
        XCTAssertEqual(profile.wheelBinding(direction: .left), original.wheelBinding(direction: .left))
        XCTAssertEqual(profile.wheelBinding(direction: .right), original.wheelBinding(direction: .right))
        XCTAssertEqual(profile.wheelBindings["up:3"], original.wheelBindings["up:3"])
        let saved = try JSONDecoder().decode(MouseProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(saved, profile)
        let routed = WheelActionRouter.route(deltas: [0, 1], continuous: false, profile: saved, modifiers: flags)
        XCTAssertEqual(routed.map(\.binding), [right])
    }

    func testLegacyZeroModifierOverrideSwapsIntoEditableDefaultSlots() {
        var profile = MouseProfile(wheelBindings: ["up:0": ActionBinding(action: .copy), "down": ActionBinding(action: .paste)])
        profile.swapWheelBindings(horizontal: false)
        XCTAssertEqual(profile.wheelBinding(direction: .up).action, .paste)
        XCTAssertEqual(profile.wheelBinding(direction: .down).action, .copy)
        XCTAssertNil(profile.wheelBindings["up:0"])
        profile.wheelBindings["up"] = ActionBinding(action: .undo)
        XCTAssertEqual(profile.wheelBinding(direction: .up).action, .undo)
    }
}
