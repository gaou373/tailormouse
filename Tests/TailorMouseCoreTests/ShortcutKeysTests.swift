import XCTest
@testable import TailorMouseCore

final class ShortcutKeysTests: XCTestCase {
    func testAllTwentyFourFunctionKeysAreSelectableAndDistinct() {
        let keys = ShortcutKeyChoice.choices(in: .function)
        XCTAssertEqual(keys.map(\.title), (1...24).map { "F\($0)" })
        XCTAssertEqual(Set(keys.map(\.id)).count, 24)
        for key in keys { XCTAssertTrue(key.shortcut().isValid); XCTAssertEqual(key.shortcut().keyTitle, key.title) }
    }
    func testNativeFunctionKeyMappingAndExtendedCharacters() {
        let keys = ShortcutKeyChoice.choices(in: .function)
        XCTAssertEqual(keys.prefix(20).map(\.keyCode), [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90])
        XCTAssertTrue(keys.prefix(20).allSatisfy { $0.shortcut().edges.allSatisfy { $0.unicode == nil } })
        XCTAssertEqual(keys.suffix(4).map { $0.shortcut().edges.first!.unicode! }, [0xF718,0xF719,0xF71A,0xF71B])
    }
    func testEveryMenuKeyEmitsMatchingDownUpAndPreservesModifiers() {
        for key in ShortcutKeyChoice.all {
            let shortcut = key.shortcut(modifiers: [.command,.option])
            let edges = shortcut.edges
            XCTAssertEqual(edges.map(\.phase), [.down,.up])
            XCTAssertEqual(edges.map(\.modifiers), [[.command,.option],[.command,.option]])
            XCTAssertEqual(edges[0].keyCode, edges[1].keyCode)
            XCTAssertEqual(edges[0].unicode, edges[1].unicode)
        }
    }
    func testExtendedFunctionShortcutRoundTripsAndLegacyShortcutStillDecodes() throws {
        let f24 = ShortcutKeyChoice.choices(in: .function).last!.shortcut(modifiers: .control)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(f24)), f24)
        let legacy = try JSONDecoder().decode(Shortcut.self, from: Data("{\"keyCode\":105,\"modifiers\":1}".utf8))
        XCTAssertNil(legacy.functionKey); XCTAssertEqual(legacy.keyTitle,"F13"); XCTAssertTrue(legacy.isValid)
    }
    func testInvalidExtendedFunctionKeysCannotEmit() {
        for shortcut in [Shortcut(keyCode:127,functionKey:25), Shortcut(keyCode:127,functionKey:20), Shortcut(keyCode:0,functionKey:24), Shortcut(keyCode:128)] {
            XCTAssertFalse(shortcut.isValid); XCTAssertTrue(shortcut.edges.isEmpty)
        }
    }
    func testExtendedShortcutPressSnapshotRepeatReleaseAndRecovery() {
        let original = ActionBinding(action: .shortcut, shortcut: ShortcutKeyChoice.choices(in: .function).last!.shortcut(modifiers: .shift))
        var profile = MouseProfile(); profile.bindings["100"] = original
        var router = InputRouter()
        XCTAssertEqual(router.route(button:100,phase:.down,profile:profile).emissions.map(\.binding),[original])
        profile.bindings["100"] = ActionBinding(action:.shortcut,shortcut:Shortcut(keyCode:0))
        XCTAssertTrue(router.route(button:100,phase:.down,profile:profile).emissions.isEmpty)
        XCTAssertTrue(router.route(button:100,phase:.up,profile:profile).suppress)
        _ = router.route(button:100,phase:.down,profile:profile)
        router.reset()
        XCTAssertFalse(router.route(button:100,phase:.up,profile:profile).suppress)
    }
    func testOnlyObservedExtraButtonsAppear() {
        XCTAssertEqual(VisibleMouseButtons.ordinary(observed:[]),[0,1,2])
        XCTAssertEqual(VisibleMouseButtons.ordinary(observed:[-1,0,2,3,5,31,32,100,111]),[0,1,2,3,5,31])
    }
}
