import XCTest
import CoreGraphics
@testable import TailorMouseCore

final class PointerPositionTests: XCTestCase {
    func testFractionalMovementAccumulatesAtQuarterSpeedWithoutIntegerDeltas() {
        var pointer = PointerPositionTransformer()
        let slow = MouseProfile(pointerSpeed: 0.25)
        pointer.rebase(at: CGPoint(x: 10, y: 20))
        // The next native event starts from the cursor position actually applied.
        var cursor = CGPoint(x: 10, y: 20)
        for _ in 0..<8 {
            let native = CGPoint(x: cursor.x + 0.5, y: cursor.y - 0.25)
            cursor = pointer.target(for: native, profile: slow)
            pointer.rebase(at: cursor)
        }
        XCTAssertEqual(cursor.x, 11)
        XCTAssertEqual(cursor.y, 19.5)
    }
    func testProfileChangesScaleTheNextMovementWithoutAccumulatingOldOffset() {
        var pointer = PointerPositionTransformer()
        pointer.rebase(at: CGPoint(x: 100, y: 100))
        let fast = pointer.target(for: CGPoint(x: 102, y: 99), profile: MouseProfile(pointerSpeed: 4))
        XCTAssertEqual(fast, CGPoint(x: 108, y: 96))
        pointer.rebase(at: fast)
        let slow = pointer.target(for: CGPoint(x: 110, y: 94), profile: MouseProfile(pointerSpeed: 0.5))
        XCTAssertEqual(slow, CGPoint(x: 109, y: 95))
    }
    func testOtherDeviceMovementAndResetCannotBecomeAnAmplifiedNagaJump() {
        var pointer = PointerPositionTransformer()
        let fast = MouseProfile(pointerSpeed: 4)
        pointer.rebase(at: CGPoint(x: 100, y: 100))
        pointer.rebase(at: CGPoint(x: 900, y: 800)) // Untouched trackpad movement.
        XCTAssertEqual(pointer.target(for: CGPoint(x: 902, y: 800), profile: fast), CGPoint(x: 908, y: 800))
        pointer.reset()
        XCTAssertEqual(pointer.target(for: CGPoint(x: 500, y: 500), profile: fast), CGPoint(x: 500, y: 500))
        pointer.rebase(at: CGPoint(x: 500, y: 500))
        XCTAssertEqual(pointer.target(for: CGPoint(x: 501, y: 500), profile: fast), CGPoint(x: 504, y: 500))
    }
    func testOneTimesPreservesNativePositionAndFailedWarpCanRebase() {
        var pointer = PointerPositionTransformer()
        pointer.rebase(at: CGPoint(x: 20, y: 20))
        let native = CGPoint(x: 22.5, y: 19.25)
        XCTAssertEqual(pointer.target(for: native, profile: MouseProfile()), native)
        _ = pointer.target(for: native, profile: MouseProfile(pointerSpeed: 4))
        pointer.rebase(at: native) // Warp failed; keep the actual native location.
        XCTAssertEqual(pointer.target(for: CGPoint(x: 23.5, y: 19.25), profile: MouseProfile(pointerSpeed: 2)), CGPoint(x: 24.5, y: 19.25))
    }
    func testDisplayEdgesAndGapsUseTheAppliedClampedPosition() {
        var pointer = PointerPositionTransformer()
        let fast = MouseProfile(pointerSpeed: 4)
        let displays = [CGRect(x: -100, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)]
        pointer.rebase(at: CGPoint(x: -10, y: 50))
        let gap = pointer.target(for: CGPoint(x: -5, y: 50), profile: fast, displays: displays)
        XCTAssertEqual(gap, CGPoint(x: -1, y: 50))
        pointer.rebase(at: CGPoint(x: 190, y: 50))
        let edge = pointer.target(for: CGPoint(x: 195, y: 50), profile: fast, displays: displays)
        XCTAssertEqual(edge, CGPoint(x: 199, y: 50))
        pointer.rebase(at: edge)
        XCTAssertEqual(pointer.target(for: CGPoint(x: 198, y: 50), profile: fast, displays: displays), CGPoint(x: 195, y: 50))
    }
}
