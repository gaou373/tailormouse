import XCTest
@testable import TailorMouseCore

final class NagaMousePreludeDecoderTests: XCTestCase {
    private func burst(_ decoder: inout NagaMousePreludeDecoder) -> [UInt64] {
        var replay: [UInt64] = []
        // Captured side-11 prelude spans about 5.4 ms.
        for (token,phase,time) in [(UInt64(1),ButtonPhase.down,0.0),(2,.up,0.0025),(3,.down,0.0037),(4,.up,0.0054)] {
            let result = decoder.mouse(token:token,phase:phase,now:time)
            XCTAssertTrue(result.consume)
            replay += result.replayTokens
        }
        return replay
    }
    func testCapturedDoubleClickPreludeIsMatchedOnlyForCalibratedPrefix() {
        for key in [UInt16(29),18] {
            var decoder = NagaMousePreludeDecoder()
            XCTAssertTrue(burst(&decoder).isEmpty)
            let result = decoder.key(key,now:0.0075,allowedPrefixes:[29,18])
            XCTAssertEqual(result.matchedTokens,[1,2,3,4])
            XCTAssertTrue(result.replayTokens.isEmpty)
            XCTAssertNil(decoder.pendingDeadline)
        }
    }
    func testNormalHeldClickDelaysDownAtMostTwelveMillisecondsAndPassesRelease() {
        var decoder = NagaMousePreludeDecoder()
        XCTAssertTrue(decoder.mouse(token:1,phase:.down,now:0).consume)
        XCTAssertTrue(decoder.expire(now:0.011).isEmpty)
        XCTAssertEqual(decoder.expire(now:0.012),[1])
        XCTAssertFalse(decoder.mouse(token:2,phase:.up,now:1).consume)
        XCTAssertNil(decoder.pendingDeadline)
    }
    func testNormalQuickClickAndDoubleClickReplayEveryTransitionInOrder() {
        var single = NagaMousePreludeDecoder()
        _ = single.mouse(token:1,phase:.down,now:0)
        _ = single.mouse(token:2,phase:.up,now:0.005)
        XCTAssertEqual(single.expire(now:0.012),[1,2])
        var double = NagaMousePreludeDecoder()
        XCTAssertTrue(burst(&double).isEmpty)
        XCTAssertEqual(double.expire(now:0.012),[1,2,3,4])
    }
    func testWrongKeyLateKeyAndIncompleteBurstNeverConsumeOrdinaryClicks() {
        var wrong = NagaMousePreludeDecoder()
        _ = burst(&wrong)
        let wrongResult = wrong.key(20,now:0.008,allowedPrefixes:[29,18])
        XCTAssertEqual(wrongResult.replayTokens,[1,2,3,4])
        XCTAssertTrue(wrongResult.matchedTokens.isEmpty)
        var late = NagaMousePreludeDecoder()
        _ = burst(&late)
        let lateResult = late.key(29,now:0.02,allowedPrefixes:[29,18])
        XCTAssertEqual(lateResult.replayTokens,[1,2,3,4])
        XCTAssertTrue(lateResult.matchedTokens.isEmpty)
        var incomplete = NagaMousePreludeDecoder()
        _ = incomplete.mouse(token:1,phase:.down,now:0)
        _ = incomplete.mouse(token:2,phase:.up,now:0.005)
        let incompleteResult = incomplete.key(29,now:0.006,allowedPrefixes:[29,18])
        XCTAssertEqual(incompleteResult.replayTokens,[1,2])
        XCTAssertTrue(incompleteResult.matchedTokens.isEmpty)
    }
    func testDragInterruptAndRecoveryCannotLeaveDeliveredButtonHeld() {
        var decoder = NagaMousePreludeDecoder()
        _ = decoder.mouse(token:1,phase:.down,now:0)
        XCTAssertEqual(decoder.flush(),[1]) // Delivered before a drag.
        XCTAssertFalse(decoder.mouse(token:2,phase:.up,now:0.02).consume)
        _ = decoder.mouse(token:3,phase:.down,now:1)
        decoder.reset() // No buffered down was delivered before Stop.
        XCTAssertTrue(decoder.expire(now:2).isEmpty)
        XCTAssertFalse(decoder.mouse(token:4,phase:.up,now:2).consume)
    }
    func testPreludeCannotCrossPhysicalConnections() {
        var a = NagaMousePreludeDecoder(), b = NagaMousePreludeDecoder()
        _ = burst(&a)
        XCTAssertTrue(b.key(29,now:0.008,allowedPrefixes:[29,18]).matchedTokens.isEmpty)
        XCTAssertEqual(a.expire(now:0.012),[1,2,3,4])
    }
    func testQuietMacroSuppressesPreludeAndPassthroughRetainsAllEightTransitions() {
        let layout = NagaKeyboardLayout(sequences:[.init(button:109,keyCodes:[29,36]),.init(button:110,keyCodes:[18,36])],doubleClickPrefixes:[29,18])
        for (key,button) in [(UInt16(29),109),(UInt16(18),110)] {
            for action in [ButtonAction.disabled,.passthrough,.copy] {
                var prelude = NagaMousePreludeDecoder(), keyboard = NagaKeyboardDecoder(), router = InputRouter()
                _ = burst(&prelude)
                let matched = prelude.key(key,now:0.0075,allowedPrefixes:Set(layout.doubleClickPrefixes)).matchedTokens
                let profile = MouseProfile(bindings:[String(button):.init(action:action)])
                var native: [UInt64] = [], emissions: [ButtonAction] = [], phases: [ButtonPhase] = []
                for (token,code,phase,time) in [(UInt64(5),key,ButtonPhase.down,0.0075),(6,key,.up,0.105),(7,36,.down,0.177),(8,36,.up,0.265)] {
                    for d in keyboard.route(.init(token:token,keyCode:code,phase:phase,modifiers:[],profile:profile),now:time,layout:layout).dispatches {
                        XCTAssertEqual(d.button,button)
                        XCTAssertEqual(d.replayKeys,[key,36])
                        phases.append(d.phase)
                        let decision = router.route(button:d.button,phase:d.phase,profile:d.profile)
                        emissions += decision.emissions.map { $0.binding.action }
                        if !decision.suppress {
                            if d.phase == .down { native += matched }
                            native += d.nativeTokens
                        }
                    }
                }
                XCTAssertEqual(phases,[.down,.up])
                XCTAssertEqual(native,action == .passthrough ? [1,2,3,4,5,6,7,8] : [])
                XCTAssertEqual(emissions,action == .passthrough ? [] : [action])
            }
        }
    }
    func testIncompleteKeyboardMacroReturnsItsMousePreludeForNativeReplay() {
        var prelude = NagaMousePreludeDecoder(), keyboard = NagaKeyboardDecoder()
        let layout = NagaKeyboardLayout(sequences:[.init(button:110,keyCodes:[18,36])],doubleClickPrefixes:[18])
        _ = burst(&prelude)
        let matched = prelude.key(18,now:0.0075,allowedPrefixes:[18]).matchedTokens
        _ = keyboard.route(.init(token:5,keyCode:18,phase:.down,modifiers:[],profile:MouseProfile()),now:0.0075,layout:layout)
        _ = keyboard.route(.init(token:6,keyCode:18,phase:.up,modifiers:[],profile:MouseProfile()),now:0.105,layout:layout)
        let events = keyboard.expire(now:0.3)
        XCTAssertEqual(events.map(\.button),[100,100])
        XCTAssertEqual(events.map(\.phase),[.down,.up])
        // The interceptor replays the mouse prelude when the sequence did not finish.
        XCTAssertTrue(events.allSatisfy { $0.replayKeys != [18,36] })
        XCTAssertEqual(matched,[1,2,3,4])
        XCTAssertTrue(keyboard.retainedTokens.isEmpty)
    }

    func testCalibrationDefaultsAreBackwardCompatibleAndInvalidPreludeIsRejected() throws {
        let old = Data(#"{"keyOverrides":{},"sequences":[]}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(NagaKeyboardLayout.self,from:old).doubleClickPrefixes.isEmpty)
        let valid = NagaKeyboardLayout(sequences:[.init(button:109,keyCodes:[29,36])],doubleClickPrefixes:[29])
        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(try JSONDecoder().decode(NagaKeyboardLayout.self,from:JSONEncoder().encode(valid)),valid)
        XCTAssertFalse(NagaKeyboardLayout(doubleClickPrefixes:[29]).isValid)
        XCTAssertFalse(NagaKeyboardLayout(sequences:valid.sequences,doubleClickPrefixes:[29,29]).isValid)
    }
}
