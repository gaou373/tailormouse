import XCTest
@testable import TailorMouseCore

final class NagaKeyboardDecoderTests: XCTestCase {
    private let layout = NagaKeyboardLayout(keyOverrides: ["36": 110], sequences: [NagaKeySequence(button: 111, keyCodes: [18,36])])
    private func input(_ token: UInt64, _ key: UInt16, _ phase: ButtonPhase, profile: MouseProfile = MouseProfile(), modifiers: ModifierMask = []) -> NagaKeyboardInput {
        NagaKeyboardInput(token: token, keyCode: key, phase: phase, modifiers: modifiers, profile: profile)
    }

    func testStandardTenAndElevenRemainHeldIndependentlyUntilTheirOwnRelease() {
        var decoder = NagaKeyboardDecoder(), router = InputRouter()
        let standard = NagaKeyboardLayout()
        let original = MouseProfile(bindings: ["109": ActionBinding(action: .copy), "110": ActionBinding(action: .paste)])
        for (key, button, token) in [(UInt16(29), 109, UInt64(1)), (UInt16(27), 110, UInt64(2))] {
            let down = decoder.route(input(token, key, .down, profile: original), now: 0, layout: standard)
            XCTAssertEqual(down.dispatches.map(\.button), [button])
            XCTAssertEqual(down.dispatches.map(\.phase), [.down])
            XCTAssertEqual(down.dispatches.flatMap { router.route(button: $0.button, phase: $0.phase, profile: $0.profile).emissions }.count, 1)
        }
        // Passing the old macro deadline must not manufacture a release.
        XCTAssertTrue(decoder.expire(now: 3).isEmpty)
        XCTAssertNil(decoder.pendingDeadline)
        for (key, button, token) in [(UInt16(29), 109, UInt64(3)), (UInt16(27), 110, UInt64(4))] {
            let repeatDown = decoder.route(input(token, key, .down), now: 3, layout: standard)
            XCTAssertEqual(repeatDown.dispatches.map(\.button), [button])
            XCTAssertTrue(repeatDown.dispatches.flatMap { router.route(button: $0.button, phase: $0.phase, profile: $0.profile).emissions }.isEmpty)
            let up = decoder.route(input(token + 2, key, .up), now: 4, layout: standard)
            XCTAssertEqual(up.dispatches.map(\.button), [button])
            XCTAssertEqual(up.dispatches.map(\.phase), [.up])
            XCTAssertEqual(up.dispatches.first?.profile, original)
            XCTAssertTrue(up.dispatches.allSatisfy { router.route(button: $0.button, phase: $0.phase, profile: $0.profile).suppress })
        }
        decoder.reset(); router.reset()
        for key: UInt16 in [29, 27] {
            _ = decoder.route(input(10, key, .down, profile: original), now: 5, layout: standard)
        }
        decoder.reset()
        for key: UInt16 in [29, 27] {
            let orphanUp = decoder.route(input(11, key, .up), now: 6, layout: standard)
            XCTAssertFalse(orphanUp.consume)
            XCTAssertTrue(orphanUp.dispatches.isEmpty)
            XCTAssertEqual(decoder.route(input(12, key, .down), now: 7, layout: standard).dispatches.map(\.phase), [.down])
            XCTAssertEqual(decoder.route(input(13, key, .up), now: 8, layout: standard).dispatches.map(\.phase), [.up])
        }
    }

    func testRecordedTenAndElevenMacrosSurviveTheirActualTiming() {
        let wired = NagaKeyboardLayout(sequences: [
            NagaKeySequence(button: 109, keyCodes: [29,36]),
            NagaKeySequence(button: 110, keyCodes: [18,36])
        ])
        for (prefix, button) in [(UInt16(29),109), (UInt16(18),110)] {
            var decoder = NagaKeyboardDecoder(), router = InputRouter()
            let profile = MouseProfile(bindings: [String(button): ActionBinding(action: .copy), "100": ActionBinding(action: .paste)])
            var events: [NagaKeyboardDispatch] = []
            events += decoder.route(input(1,prefix,.down,profile:profile),now:0,layout:wired).dispatches
            events += decoder.route(input(2,prefix,.up,profile:profile),now:0.098,layout:wired).dispatches
            // The installed 120 ms deadline fired before the captured Return.
            XCTAssertTrue(decoder.expire(now:0.121).isEmpty)
            events += decoder.route(input(3,36,.down,profile:profile),now:0.170,layout:wired).dispatches
            events += decoder.route(input(4,36,.up,profile:profile),now:0.258,layout:wired).dispatches
            XCTAssertEqual(events.map(\.button), [button,button])
            XCTAssertEqual(events.map(\.phase), [.down,.up])
            XCTAssertEqual(events.flatMap(\.nativeTokens), [1,2,3,4])
            XCTAssertEqual(events.flatMap { router.route(button:$0.button,phase:$0.phase,profile:$0.profile).emissions }.map { $0.binding.action }, [.copy])
            XCTAssertTrue(decoder.retainedTokens.isEmpty)
            XCTAssertNil(decoder.pendingDeadline)
            XCTAssertEqual(decoder.route(input(5,24,.down),now:1,layout:wired).dispatches.map(\.button), [111])
            XCTAssertEqual(decoder.route(input(6,24,.up),now:1.01,layout:wired).dispatches.map(\.phase), [.up])
        }
    }

    func testIndividualKeyOverridesHaveMatchedTransitions() {
        var decoder = NagaKeyboardDecoder()
        for (key,button) in [(UInt16(29),109),(UInt16(36),110)] {
            XCTAssertEqual(decoder.route(input(1,key,.down), now: 0, layout: layout).dispatches.map(\.button), [button])
            XCTAssertEqual(decoder.route(input(2,key,.up), now: 0.01, layout: layout).dispatches.map(\.phase), [.up])
        }
    }
    func testConfiguredMacroFiresExactlyOneActionAndNeverItsPrefix() {
        var decoder = NagaKeyboardDecoder(), router = InputRouter()
        let profile = MouseProfile(bindings: ["100": ActionBinding(action: .paste), "111": ActionBinding(action: .copy)])
        var dispatched: [NagaKeyboardDispatch] = []
        for (token,key,phase,time) in [(UInt64(1),UInt16(18),ButtonPhase.down,0.0),(2,18,.up,0.01),(3,36,.down,0.02),(4,36,.up,0.03)] {
            let result = decoder.route(input(token,key,phase,profile:profile), now:time, layout:layout)
            XCTAssertTrue(result.consume)
            dispatched += result.dispatches
        }
        XCTAssertEqual(dispatched.map(\.button), [111,111])
        XCTAssertEqual(dispatched.map(\.phase), [.down,.up])
        var actions: [ButtonAction] = []
        for d in dispatched {
            let routed = router.route(button:d.button,phase:d.phase,profile:d.profile,modifiers:d.modifiers)
            XCTAssertTrue(routed.suppress)
            actions += routed.emissions.map { $0.binding.action }
        }
        XCTAssertEqual(actions,[.copy])
        XCTAssertNil(decoder.pendingDeadline)
        XCTAssertTrue(decoder.retainedTokens.isEmpty)
    }
    func testPassthroughMacroRetainsAllOriginalTransitionsInOrder() {
        var decoder = NagaKeyboardDecoder(), router = InputRouter()
        let profile = MouseProfile(bindings: ["111":ActionBinding(action:.passthrough)])
        var native: [UInt64] = []
        for (token,key,phase,time) in [(UInt64(1),UInt16(18),ButtonPhase.down,0.0),(2,18,.up,0.01),(3,36,.down,0.02),(4,36,.up,0.03)] {
            for d in decoder.route(input(token,key,phase,profile:profile),now:time,layout:layout).dispatches {
                XCTAssertEqual(d.replayKeys,[18,36])
                if !router.route(button:d.button,phase:d.phase,profile:d.profile).suppress { native += d.nativeTokens }
            }
        }
        XCTAssertEqual(native,[1,2,3,4])
    }
    func testSinglePrefixTapExpiresWithOriginalProfileAndPairedRelease() {
        var decoder = NagaKeyboardDecoder()
        let original = MouseProfile(bindings:["100":ActionBinding(action:.copy)])
        _ = decoder.route(input(1,18,.down,profile:original,modifiers:.command),now:0,layout:layout)
        _ = decoder.route(input(2,18,.up,profile:MouseProfile()),now:0.01,layout:layout)
        XCTAssertTrue(decoder.expire(now:0.1).isEmpty)
        let events = decoder.expire(now:0.26)
        XCTAssertEqual(events.map(\.button),[100,100])
        XCTAssertEqual(events.map(\.phase),[.down,.up])
        XCTAssertTrue(events.allSatisfy { $0.profile == original && $0.modifiers == .command })
        XCTAssertEqual(events.flatMap(\.nativeTokens),[1,2])
    }
    func testHeldPrefixAndRepeatsDoNotBecomeMacroOrDuplicateAction() {
        var decoder = NagaKeyboardDecoder(), router = InputRouter()
        let profile = MouseProfile(bindings:["100":ActionBinding(action:.copy)])
        _ = decoder.route(input(1,18,.down,profile:profile),now:0,layout:layout)
        let repeated = decoder.route(input(2,18,.down,profile:profile),now:0.05,layout:layout).dispatches
        XCTAssertEqual(repeated.map(\.button),[100,100])
        let emissions = repeated.flatMap { router.route(button:$0.button,phase:$0.phase,profile:$0.profile).emissions }
        XCTAssertEqual(emissions.count,1)
        XCTAssertEqual(decoder.route(input(3,36,.down),now:0.06,layout:layout).dispatches.map(\.button),[110])
        XCTAssertEqual(decoder.route(input(4,18,.up),now:0.07,layout:layout).dispatches.map(\.phase),[.up])
    }
    func testTimeoutMismatchAndModifierChangeDoNotCompleteMacro() {
        for (time,modifiers) in [(0.3,ModifierMask()),(0.02,ModifierMask.command)] {
            var decoder = NagaKeyboardDecoder()
            _ = decoder.route(input(1,18,.down),now:0,layout:layout)
            _ = decoder.route(input(2,18,.up),now:0.01,layout:layout)
            XCTAssertEqual(decoder.route(input(3,36,.down,modifiers:modifiers),now:time,layout:layout).dispatches.map(\.button),[100,100,110])
        }
    }
    func testRecoveryDropsPendingEventsAndUnknownKeysPassThrough() {
        var decoder = NagaKeyboardDecoder()
        _ = decoder.route(input(1,18,.down),now:0,layout:layout)
        XCTAssertEqual(decoder.retainedTokens,[1])
        decoder.reset()
        XCTAssertTrue(decoder.expire(now:1).isEmpty)
        XCTAssertTrue(decoder.retainedTokens.isEmpty)
        XCTAssertFalse(decoder.route(input(2,0,.down),now:2,layout:layout).consume)
        let orphan = decoder.route(input(3,18,.up),now:2,layout:layout)
        XCTAssertTrue(orphan.dispatches.isEmpty)
        XCTAssertFalse(orphan.consume)
    }
    func testPendingSequencesCannotCrossDevices() {
        var a = NagaKeyboardDecoder(), b = NagaKeyboardDecoder()
        _ = a.route(input(1,18,.down),now:0,layout:layout)
        _ = a.route(input(2,18,.up),now:0.01,layout:layout)
        XCTAssertEqual(b.route(input(3,36,.down),now:0.02,layout:layout).dispatches.map(\.button),[110])
        XCTAssertEqual(a.expire(now:0.3).map(\.button),[100,100])
    }
    func testCalibrationRoundTripAndInvalidDefinitionsRejected() throws {
        let config = ProfileConfiguration(nagaKeyboardLayouts:["USB":layout])
        XCTAssertEqual(try JSONDecoder().decode(ProfileConfiguration.self,from:JSONEncoder().encode(config)),config)
        XCTAssertTrue(layout.isValid)
        XCTAssertFalse(NagaKeyboardLayout(keyOverrides:["36":200]).isValid)
        XCTAssertFalse(NagaKeyboardLayout(sequences:[NagaKeySequence(button:111,keyCodes:[])]).isValid)
        XCTAssertFalse(NagaKeyboardLayout(sequences:[NagaKeySequence(button:111,keyCodes:[18,36]),NagaKeySequence(button:110,keyCodes:[18,36])]).isValid)
        let json = #"{"schemaVersion":2,"nagaKeyboardLayouts":{"USB":{"keyOverrides":{"36":200},"sequences":[]}}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ProfileConfiguration.self,from:Data(json.utf8)))
    }
}
