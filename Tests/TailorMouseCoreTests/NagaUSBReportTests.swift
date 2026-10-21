import XCTest
@testable import TailorMouseCore

final class NagaUSBReportTests: XCTestCase {
    private let receiver = DeviceIdentity(vendorID: 0x1532, productID: 0x0090, transport: "USB", product: "")
    private func report(_ keys: [UInt8] = [], modifiers: UInt8 = 0) -> [UInt8] {
        [modifiers,0] + keys + Array(repeating: 0, count: max(0,6-keys.count))
    }
    private func transitions(_ bytes: [UInt8], raw: inout NagaBluetoothReportDecoder) -> [NagaRawKeyTransition] {
        let normalized = NagaKeyboardReportFormat(identity: receiver)!.canonical(reportID: 0, bytes: bytes)!
        return raw.route(reportID: 6, bytes: normalized)
    }
    func testFormatsRequireExactProductsAndTransportAndPreserveBluetoothPayload() {
        for product in [0x008f,0x0090] {
            XCTAssertEqual(NagaKeyboardReportFormat(identity: DeviceIdentity(vendorID: 0x1532, productID: product, transport: "USB", product: "")), .usbBoot)
        }
        let bluetooth = DeviceIdentity(vendorID: 0x1532, productID: 0x0092, transport: "Bluetooth Low Energy", product: "")
        let format = NagaKeyboardReportFormat(identity: bluetooth)!
        XCTAssertEqual(format.reportID,6)
        let bytes: [UInt8] = [6,0,0,0x1e,0,0,0,0]
        XCTAssertEqual(format.canonical(reportID: 6, bytes: bytes), bytes)
        for identity in [DeviceIdentity(vendorID: 1,productID: 0x0090,transport: "USB",product: ""),
                         DeviceIdentity(vendorID: 0x1532,productID: 0x0092,transport: "USB",product: ""),
                         DeviceIdentity(vendorID: 0x1532,productID: 0x0090,transport: "Bluetooth",product: ""),
                         DeviceIdentity(vendorID: 0x1532,productID: 0x0091,transport: "USB",product: "")] {
            XCTAssertNil(NagaKeyboardReportFormat(identity: identity))
        }
    }
    func testObservedReceiverReportsProduceMatchedSideOneThroughKeyboardDecoder() {
        var raw = NagaBluetoothReportDecoder(); var keyboard = NagaKeyboardDecoder(); var token: UInt64 = 0
        let down: [UInt8] = [0,0,0x1e,0,0,0,0,0]
        for _ in 0..<3 {
            for bytes in [down,report()] {
                let edges = transitions(bytes,raw: &raw)
                XCTAssertEqual(edges.count,1)
                for edge in edges {
                    token += 1
                    let routed = keyboard.route(NagaKeyboardInput(token: token,keyCode: edge.keyCode,phase: edge.phase,modifiers: edge.modifiers,profile: MouseProfile()),now: Double(token),layout: NagaKeyboardLayout())
                    XCTAssertEqual(routed.dispatches.map(\.button),[100])
                    XCTAssertEqual(routed.dispatches.map(\.phase),[edge.phase])
                }
            }
        }
    }
    func testAllTwelveUSBButtonsPreserveIndependentHoldsAndModifiers() {
        var raw = NagaBluetoothReportDecoder()
        let usages: [UInt8] = Array(0x1e...0x27)+[0x2d,0x2e]
        let expected: [UInt16] = [18,19,20,21,23,22,26,28,25,29,27,24]
        for (usage,key) in zip(usages,expected) {
            let down = transitions(report([usage],modifiers: 0x04),raw: &raw)
            XCTAssertEqual(down.map(\.keyCode),[key]);XCTAssertEqual(down.map(\.phase),[.down])
            XCTAssertEqual(down[0].modifiers,.option)
            XCTAssertTrue(transitions(report([usage]),raw: &raw).isEmpty)
            let up = transitions(report(),raw: &raw)
            XCTAssertEqual(up.map(\.keyCode),[key]);XCTAssertEqual(up.map(\.phase),[.up])
        }
        _ = transitions(report([0x27,0x2d]),raw: &raw)
        XCTAssertEqual(transitions(report([0x2d]),raw: &raw).map(\.keyCode),[29])
        XCTAssertEqual(transitions(report(),raw: &raw).map(\.keyCode),[27])
    }
    func testRawSideAnchorTriggersEachNativeClickChordWhileHeld() {
        let profile = MouseProfile(chords:[ChordBinding(buttons:[100,0],binding:ActionBinding(action:.copy)),
                                          ChordBinding(buttons:[100,1],binding:ActionBinding(action:.paste))])
        var raw = NagaBluetoothReportDecoder();var keyboard = NagaKeyboardDecoder();var router = InputRouter();var token: UInt64 = 0
        func routeSide(_ bytes: [UInt8]) {
            for edge in transitions(bytes,raw:&raw) {
                token += 1
                let result = keyboard.route(NagaKeyboardInput(token:token,keyCode:edge.keyCode,phase:edge.phase,modifiers:edge.modifiers,profile:profile),now:Double(token),layout:NagaKeyboardLayout())
                for e in result.dispatches { _ = router.route(button:e.button,phase:e.phase,profile:e.profile,modifiers:e.modifiers) }
            }
        }
        routeSide(report([0x1e]))
        for button in [0,0,1,1,0] {
            XCTAssertEqual(router.route(button:button,phase:.down,profile:profile).emissions.map(\.binding.action),[button==0 ? .copy : .paste])
            XCTAssertTrue(router.route(button:button,phase:.up,profile:profile).suppress)
            routeSide(report([0x1e])) // Repeated held snapshots cannot drop the anchor.
        }
        routeSide(report())
        XCTAssertFalse(router.route(button:0,phase:.down,profile:profile).suppress)
    }
    func testHeldShortcutReleaseKeepsPressTimeMappingAndStopCleansOutput() {
        let held = ActionBinding(action:.shortcut,shortcut:Shortcut(keyCode:8),shortcutBehavior:.hold)
        let profile = MouseProfile(bindings:["102":held])
        var raw=NagaBluetoothReportDecoder();var keyboard=NagaKeyboardDecoder();var router=InputRouter();var token:UInt64=0
        var emissions:[InputEmission]=[]
        for bytes in [report([0x20]),report([0x20]),report()] {
            for edge in transitions(bytes,raw:&raw) {
                token += 1
                let result=keyboard.route(NagaKeyboardInput(token:token,keyCode:edge.keyCode,phase:edge.phase,modifiers:edge.modifiers,profile: token==1 ? profile : MouseProfile()),now:Double(token),layout:NagaKeyboardLayout())
                for e in result.dispatches {emissions += router.route(button:e.button,phase:e.phase,profile:e.profile,modifiers:e.modifiers).emissions}
            }
        }
        XCTAssertEqual(emissions.map(\.phase),[.down,.up]);XCTAssertEqual(emissions.map(\.binding),[held,held])
        var output=HeldShortcuts();let owner=ShortcutHoldOwner(source:"receiver",button:102)
        _ = output.press(owner:owner,shortcut:held.shortcut!,repeating:false,now:0,delay:0.5,interval:0.05)
        XCTAssertEqual(output.release(source:"receiver").map(\.edge.phase),[.up])
        XCTAssertTrue(output.releaseAll().isEmpty)
    }
    func testOwnershipCoversCompositeInterfacesButExcludesOtherConnectionsAndKeyboards() {
        func endpoint(_ id: UInt64,_ connection:String,_ identity:DeviceIdentity) -> DeviceEndpoint {
            DeviceEndpoint(id:id,identity:identity,senderIDs:[id],connectionID:connection,canIdentifyEvents:true)
        }
        let raw=endpoint(1,"receiver-A",receiver)
        XCTAssertTrue(NagaKeyboardReportFormat.owns(endpoint(2,"receiver-A",receiver),endpoints:[raw]))
        XCTAssertFalse(NagaKeyboardReportFormat.owns(endpoint(3,"receiver-B",receiver),endpoints:[raw]))
        let keyboard=DeviceIdentity(vendorID:1,productID:1,transport:"USB",product:"")
        XCTAssertFalse(NagaKeyboardReportFormat.owns(endpoint(4,"receiver-A",keyboard),endpoints:[raw]))
        XCTAssertTrue(NagaBluetoothReportDecoder.handles(keyCode:18,layout:NagaKeyboardLayout()))
        XCTAssertFalse(NagaBluetoothReportDecoder.handles(keyCode:0,layout:NagaKeyboardLayout()))
    }
    func testMalformedRolloverAndSecondaryReportsDoNotReleaseHeldSideButton() {
        let format=NagaKeyboardReportFormat(identity:receiver)!
        XCTAssertNil(format.canonical(reportID:1,bytes:report()))
        XCTAssertNil(format.canonical(reportID:0,bytes:[0,0]))
        XCTAssertNil(format.canonical(reportID:0,bytes:[0,1,0,0,0,0,0,0]))
        var raw=NagaBluetoothReportDecoder()
        _ = transitions(report([0x1e]),raw:&raw)
        XCTAssertTrue(transitions(report([1]),raw:&raw).isEmpty)
        XCTAssertEqual(transitions(report(),raw:&raw).map(\.phase),[.up])
    }
    func testPrimeAndResetDoNotReplayAnInheritedHoldOrOldConnection() {
        let format=NagaKeyboardReportFormat(identity:receiver)!
        var raw=NagaBluetoothReportDecoder()
        raw.prime(reportID:6,bytes:format.canonical(reportID:0,bytes:report([0x1e]))!)
        XCTAssertTrue(transitions(report([0x1e]),raw:&raw).isEmpty)
        XCTAssertTrue(transitions(report(),raw:&raw).isEmpty)
        XCTAssertEqual(transitions(report([0x1e]),raw:&raw).map(\.phase),[.down])
        raw.reset();XCTAssertTrue(transitions(report(),raw:&raw).isEmpty)
        XCTAssertEqual(transitions(report([0x1e]),raw:&raw).map(\.phase),[.down])
    }
    func testCalibratedUSBMacroRetainsItsMatchedMousePrelude() {
        let layout=NagaKeyboardLayout(sequences:[NagaKeySequence(button:109,keyCodes:[29,36])],doubleClickPrefixes:[29])
        var mouse=NagaMousePreludeDecoder();var raw=NagaBluetoothReportDecoder();var keyboard=NagaKeyboardDecoder()
        for (i,phase) in [ButtonPhase.down,.up,.down,.up].enumerated() {
            XCTAssertTrue(mouse.mouse(token:UInt64(i+1),phase:phase,now:Double(i)*0.001).consume)
        }
        var matched:[UInt64]=[];var dispatches:[NagaKeyboardDispatch]=[];var token:UInt64=4
        for bytes in [report([0x27]),report(),report([0x28]),report()] {
            for edge in transitions(bytes,raw:&raw) {
                token += 1
                if edge.phase == .down {
                    let prelude=mouse.key(edge.keyCode,now:Double(token)*0.001,allowedPrefixes:Set(layout.doubleClickPrefixes))
                    XCTAssertTrue(prelude.replayTokens.isEmpty);matched += prelude.matchedTokens
                }
                dispatches += keyboard.route(NagaKeyboardInput(token:token,keyCode:edge.keyCode,phase:edge.phase,modifiers:edge.modifiers,profile:MouseProfile()),now:Double(token)*0.001,layout:layout).dispatches
            }
        }
        XCTAssertEqual(matched,[1,2,3,4])
        XCTAssertEqual(dispatches.map(\.button),[109,109]);XCTAssertEqual(dispatches.map(\.phase),[.down,.up])
        XCTAssertTrue(dispatches.allSatisfy{$0.replayKeys == [29,36]})
    }

}
