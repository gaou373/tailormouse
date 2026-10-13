import XCTest
@testable import TailorMouseCore

final class MouseButtonRecordingTests: XCTestCase {
    func testClearPrimaryLabelsAndNoUnobservedExtraChoices() {
        XCTAssertEqual(ChordButtonChoices.clicks.map(ChordButtonChoices.title), ["Left Click","Right Click","Middle Click"])
        XCTAssertEqual(ChordButtonChoices.sideButtons.map(ChordButtonChoices.title), (1...12).map { "Side Button \($0)" })
        XCTAssertTrue(ChordButtonChoices.extras(observed:[],saved:[]).isEmpty)
        XCTAssertEqual(ChordButtonChoices.extras(observed:[0,4,31,100],saved:[3,4,111,32]),[3,4,31])
    }
    func testEverySupportedButtonRequiresItsOwnPressAndRelease() {
        for button in Array(0...31) + Array(100...111) {
            var recorder = MouseButtonRecording(); recorder.begin()
            XCTAssertNil(recorder.route(button:button,phase:.up,source:"mouse"))
            XCTAssertNil(recorder.route(button:button,phase:.down,source:"mouse"))
            XCTAssertNil(recorder.route(button:button,phase:.drag,source:"mouse"))
            XCTAssertEqual(recorder.route(button:button,phase:.up,source:"mouse"),button)
            XCTAssertFalse(recorder.active)
            XCTAssertNil(recorder.route(button:button,phase:.down,source:"mouse"))
        }
    }
    func testRepeatsAndOtherSourcesCannotCompleteOrReplaceThePress() {
        var recorder = MouseButtonRecording(); recorder.begin()
        XCTAssertNil(recorder.route(button:100,phase:.down,source:"USB"))
        XCTAssertNil(recorder.route(button:100,phase:.down,source:"USB"))
        XCTAssertNil(recorder.route(button:101,phase:.down,source:"USB"))
        XCTAssertNil(recorder.route(button:100,phase:.up,source:"Bluetooth"))
        XCTAssertNil(recorder.route(button:101,phase:.up,source:"USB"))
        XCTAssertEqual(recorder.route(button:100,phase:.up,source:"USB"),100)
    }
    func testCancelTimeoutAndNewAttemptDropAnIncompletePress() {
        var recorder = MouseButtonRecording(); recorder.begin()
        _ = recorder.route(button:1,phase:.down,source:"mouse")
        recorder.cancel()
        XCTAssertNil(recorder.route(button:1,phase:.up,source:"mouse"))
        recorder.begin()
        XCTAssertNil(recorder.route(button:1,phase:.up,source:"mouse"))
        _ = recorder.route(button:2,phase:.down,source:"mouse")
        XCTAssertEqual(recorder.route(button:2,phase:.up,source:"mouse"),2)
    }
    func testInvalidButtonOrUnknownSourceNeverArmsAPress() {
        var recorder = MouseButtonRecording(); recorder.begin()
        for button in [-1,32,99,112] { XCTAssertNil(recorder.route(button:button,phase:.down,source:"mouse")) }
        XCTAssertNil(recorder.route(button:0,phase:.down,source:""))
        XCTAssertNil(recorder.route(button:0,phase:.up,source:"mouse"))
        XCTAssertTrue(recorder.active)
    }
    func testPrimaryAndSideChordValidationAndRoundTrip() throws {
        for button in 0...2 {
            let chord = ChordBinding(buttons:[button,100],binding:ActionBinding(action:.copy))
            XCTAssertTrue(chord.isValid)
            XCTAssertEqual(try JSONDecoder().decode(ChordBinding.self,from:JSONEncoder().encode(chord)),chord)
        }
        XCTAssertFalse(ChordBinding(buttons:[0,0],binding:ActionBinding()).isValid)
    }
    func testNativePrimaryFirstChordPreservesClickDragAndUpAcrossEdits() {
        for button in 0...2 {
            let native = ActionBinding(action:.mouseClick,mouseButton:button)
            let profile = MouseProfile(bindings:[String(button):native],chords:[ChordBinding(buttons:[button,100],binding:ActionBinding(action:.copy))])
            var router = InputRouter()
            XCTAssertEqual(router.route(button:button,phase:.down,profile:profile),RoutingDecision(suppress:false))
            XCTAssertFalse(router.route(button:button,phase:.drag,profile:MouseProfile()).suppress)
            let chord = router.route(button:100,phase:.down,profile:MouseProfile())
            XCTAssertTrue(chord.suppress); XCTAssertEqual(chord.emissions.map { $0.binding.action },[.copy])
            XCTAssertTrue(router.route(button:100,phase:.up,profile:MouseProfile()).suppress)
            XCTAssertFalse(router.route(button:button,phase:.up,profile:MouseProfile()).suppress)
            XCTAssertTrue(router.route(button:button,phase:.up,profile:MouseProfile()).emissions.isEmpty)
        }
    }
    func testPrimarySecondChordConsumesOnlyItsMatchedPair() {
        let profile = MouseProfile(chords:[ChordBinding(buttons:[100,0],binding:ActionBinding(action:.paste))])
        var router = InputRouter()
        XCTAssertTrue(router.route(button:100,phase:.down,profile:profile).suppress)
        XCTAssertEqual(router.route(button:0,phase:.down,profile:profile).emissions.map { $0.binding.action },[.paste])
        XCTAssertTrue(router.route(button:0,phase:.drag,profile:MouseProfile()).suppress)
        XCTAssertTrue(router.route(button:0,phase:.up,profile:MouseProfile()).suppress)
        XCTAssertTrue(router.route(button:100,phase:.up,profile:MouseProfile()).suppress)
    }
    func testUnmatchedNativePrimaryDoesNotReplayADuplicateClick() {
        let profile = MouseProfile(chords:[ChordBinding(buttons:[0,100],binding:ActionBinding(action:.copy))])
        var router = InputRouter()
        XCTAssertFalse(router.route(button:0,phase:.down,profile:profile).suppress)
        XCTAssertEqual(router.route(button:0,phase:.up,profile:profile),RoutingDecision(suppress:false))
        _ = router.route(button:0,phase:.down,profile:profile)
        XCTAssertTrue(router.route(button:1,phase:.down,profile:profile).emissions.isEmpty)
        router.reset()
        XCTAssertFalse(router.route(button:0,phase:.up,profile:profile).suppress)
        XCTAssertFalse(router.route(button:1,phase:.up,profile:profile).suppress)
    }
    func testCustomPrimaryMappingIsDeferredAndReplayedOnceIfUnmatched() {
        var profile = MouseProfile(bindings:["0":ActionBinding(action:.undo)],chords:[ChordBinding(buttons:[0,100],binding:ActionBinding(action:.copy))])
        var router = InputRouter()
        XCTAssertTrue(router.route(button:0,phase:.down,profile:profile).suppress)
        profile.bindings["0"] = ActionBinding(action:.paste)
        let up = router.route(button:0,phase:.up,profile:profile)
        XCTAssertTrue(up.suppress); XCTAssertEqual(up.emissions.map { $0.binding.action },[.undo])
        XCTAssertTrue(router.route(button:0,phase:.up,profile:profile).emissions.isEmpty)
    }
}
