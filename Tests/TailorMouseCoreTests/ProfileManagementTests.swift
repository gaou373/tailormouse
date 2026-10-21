import XCTest
@testable import TailorMouseCore

final class ProfileManagementTests: XCTestCase {
    private let tracking = CursorTrackingSettings(acceleration: 1.5, sensitivity: 0.42)
    private let reference = NativePointerValues(resolution: 26214400, acceleration: 98304)
    private func source(name: String = "Default", bundle: String? = nil) -> MouseProfile {
        MouseProfile(name:name,bundleIdentifier:bundle,invertWheel:true,wheelSpeed:1.75,button3:.copy,button4:.paste,
                     horizontalWheelSpeed:0.55,invertHorizontalWheel:true,pointerAcceleration:0.5,pointerSensitivity:0.3,
                     wheelBindings:["up:8":ActionBinding(action:.undo)],bindings:["100":ActionBinding(action:.copy)],
                     modifierBindings:["100:1":ActionBinding(action:.paste)],chords:[ChordBinding(buttons:[100,0],binding:ActionBinding(action:.undo),note:"Work")])
    }
    private func configuration() -> ProfileConfiguration {
        ProfileConfiguration(defaultProfile:source(),appProfiles:[MouseProfile(name:"Editor",bundleIdentifier:"example.editor",pointerSensitivity:3)],
                             selectedDeviceFamily:nil,nagaKeyboardLayouts:["USB":NagaKeyboardLayout()],nagaWiredTrackingReference:reference,cursorTracking:tracking)
    }
    func testCopyReplacesAllApplicationSettingsAndPreservesIdentitiesAndSource() throws {
        var config=configuration();let old=config;let destination=config.appProfiles[0]
        let id=try config.manageProfile(.copy,sourceID:old.defaultProfile.id,target:ApplicationProfileTarget(name:"Other name",bundleIdentifier:"example.editor"))
        XCTAssertEqual(id,destination.id);XCTAssertEqual(config.defaultProfile,old.defaultProfile)
        let copied=config.appProfiles[0]
        XCTAssertEqual(copied.id,destination.id);XCTAssertEqual(copied.name,destination.name);XCTAssertEqual(copied.bundleIdentifier,destination.bundleIdentifier)
        XCTAssertEqual(copied.bindings,old.defaultProfile.bindings);XCTAssertEqual(copied.modifierBindings,old.defaultProfile.modifierBindings)
        XCTAssertEqual(copied.chords,old.defaultProfile.chords);XCTAssertEqual(copied.wheelBindings,old.defaultProfile.wheelBindings)
        XCTAssertEqual(copied.wheelSpeed,1.75);XCTAssertEqual(copied.horizontalWheelSpeed,0.55)
        XCTAssertTrue(copied.invertWheel);XCTAssertTrue(copied.invertHorizontalWheel)
        XCTAssertEqual(copied.button3,.copy);XCTAssertEqual(copied.button4,.paste)
        XCTAssertEqual(copied.pointerSensitivity,3) // Obsolete per-profile values are not moved.
        XCTAssertEqual(config.cursorTracking,old.cursorTracking);XCTAssertEqual(config.nagaWiredTrackingReference,old.nagaWiredTrackingReference)
        XCTAssertEqual(config.nagaKeyboardLayouts,old.nagaKeyboardLayouts);XCTAssertNil(config.selectedDeviceFamily)
    }
    func testTransferFromDefaultResetsOnlySourceAndSelectsDestinationIdentity() throws {
        var config=configuration();let old=config
        let result=try config.manageProfile(.transfer,sourceID:old.defaultProfile.id,target:ApplicationProfileTarget(name:"Editor",bundleIdentifier:"example.editor"))
        XCTAssertEqual(result,old.appProfiles[0].id)
        XCTAssertEqual(config.defaultProfile,MouseProfile(id:old.defaultProfile.id,name:old.defaultProfile.name))
        XCTAssertEqual(config.appProfiles[0].bindings,old.defaultProfile.bindings)
        XCTAssertEqual(config.cursorTracking,tracking);XCTAssertEqual(config.nagaWiredTrackingReference,reference)
    }
    func testTransferFromApplicationRetainsSourceAssociationAndOtherProfiles() throws {
        var config=configuration();let original=source(name:"Source",bundle:"example.source")
        config.appProfiles.append(original);let defaultBefore=config.defaultProfile
        _=try config.manageProfile(.transfer,sourceID:original.id,target:ApplicationProfileTarget(name:"Editor",bundleIdentifier:"example.editor"))
        XCTAssertEqual(config.profile(for:"example.source"),MouseProfile(id:original.id,name:original.name,bundleIdentifier:original.bundleIdentifier))
        XCTAssertEqual(config.profile(for:"example.editor").bindings,original.bindings)
        XCTAssertEqual(config.defaultProfile,defaultBefore)
    }
    func testNewDestinationCreatesOneProfileAndSubsequentCopyReusesIt() throws {
        var config=configuration();let target=ApplicationProfileTarget(name:"Timeline",bundleIdentifier:"example.timeline")
        let id=try config.manageProfile(.copy,sourceID:config.defaultProfile.id,target:target)
        XCTAssertEqual(config.appProfiles.count,2);XCTAssertEqual(config.profile(for:target.bundleIdentifier).id,id)
        XCTAssertNotEqual(id,config.defaultProfile.id)
        config.defaultProfile.bindings["101"]=ActionBinding(action:.redo)
        XCTAssertEqual(try config.manageProfile(.copy,sourceID:config.defaultProfile.id,target:target),id)
        XCTAssertEqual(config.appProfiles.count,2);XCTAssertEqual(config.profile(for:target.bundleIdentifier).bindings["101"]?.action,.redo)
    }
    func testResetApplicationKeepsIdentityGlobalTrackingAndOtherProfiles() throws {
        var config=configuration();let original=config
        let app=config.appProfiles[0]
        XCTAssertEqual(try config.manageProfile(.reset,sourceID:app.id),app.id)
        XCTAssertEqual(config.appProfiles[0],MouseProfile(id:app.id,name:app.name,bundleIdentifier:app.bundleIdentifier))
        XCTAssertEqual(config.defaultProfile,original.defaultProfile);XCTAssertEqual(config.cursorTracking,tracking)
        XCTAssertEqual(config.nagaWiredTrackingReference,reference);XCTAssertEqual(config.nagaKeyboardLayouts,original.nagaKeyboardLayouts)
    }
    func testInvalidOrSelfOperationsAreAtomic() throws {
        let original=configuration();let app=original.appProfiles[0]
        for action in [ProfileManagementAction.copy,.transfer] {
            for (source,target) in [(app.id,ApplicationProfileTarget(name:app.name,bundleIdentifier:app.bundleIdentifier!)),
                                    (UUID(),ApplicationProfileTarget(name:"Editor",bundleIdentifier:"example.editor")),
                                    (original.defaultProfile.id,ApplicationProfileTarget(name:"",bundleIdentifier:"example.invalid")),
                                    (original.defaultProfile.id,ApplicationProfileTarget(name:"Invalid",bundleIdentifier:" "))] {
                var config=original
                XCTAssertThrowsError(try config.manageProfile(action,sourceID:source,target:target));XCTAssertEqual(config,original)
            }
            var config=original
            XCTAssertThrowsError(try config.manageProfile(action,sourceID:config.defaultProfile.id));XCTAssertEqual(config,original)
        }
        var config=original;XCTAssertThrowsError(try config.resetProfile(id:UUID()));XCTAssertEqual(config,original)
    }
    func testLegacyMigrationUsesDefaultTrackingAndPreservesAppMappings() throws {
        let config=configuration()
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(config)) as! [String:Any]
        legacy["schemaVersion"]=2;legacy.removeValue(forKey:"cursorTracking")
        let migrated=try JSONDecoder().decode(ProfileConfiguration.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertEqual(migrated.schemaVersion,3)
        XCTAssertEqual(migrated.cursorTracking,CursorTrackingSettings(acceleration:0.5,sensitivity:0.3))
        XCTAssertEqual(migrated.defaultProfile,config.defaultProfile);XCTAssertEqual(migrated.appProfiles,config.appProfiles)
        XCTAssertEqual(migrated.nagaWiredTrackingReference,reference)
        XCTAssertEqual(try JSONDecoder().decode(ProfileConfiguration.self,from:JSONEncoder().encode(migrated)),migrated)
    }
    func testGlobalTrackingIgnoresApplicationProfileAndLegacyFieldChanges() throws {
        var config=configuration()
        let target=try reference.target(profile:config.trackingProfile,reference:reference)
        XCTAssertEqual(target.resolution,62415238);XCTAssertEqual(target.acceleration,98304)
        for id in [config.defaultProfile.id,config.appProfiles[0].id] {
            _=config.profile(id:id)
            XCTAssertEqual(try reference.target(profile:config.trackingProfile,reference:reference),target)
        }
        config.appProfiles[0].pointerSensitivity=4;config.defaultProfile.pointerSensitivity=0.25
        XCTAssertEqual(try reference.target(profile:config.trackingProfile,reference:reference),target)
        config.cursorTracking.sensitivity=0.5
        XCTAssertEqual(try reference.target(profile:config.trackingProfile,reference:reference).resolution,52428800)
        let restored=try JSONDecoder().decode(ProfileConfiguration.self,from:JSONEncoder().encode(config))
        XCTAssertEqual(restored.cursorTracking,config.cursorTracking)
        XCTAssertEqual(restored.trackingProfile.pointerSensitivity,0.5)
    }
    func testSharedSettingsValidationAndMissingV3SettingsRejectInvalidImport() throws {
        for invalid in [CursorTrackingSettings(acceleration:6),CursorTrackingSettings(acceleration:-1),CursorTrackingSettings(sensitivity:0.1),CursorTrackingSettings(sensitivity:5)] {
            var config=configuration();config.cursorTracking=invalid
            XCTAssertThrowsError(try JSONDecoder().decode(ProfileConfiguration.self,from:JSONEncoder().encode(config)))
        }
        var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(configuration())) as! [String:Any]
        json.removeValue(forKey:"cursorTracking")
        XCTAssertThrowsError(try JSONDecoder().decode(ProfileConfiguration.self,from:JSONSerialization.data(withJSONObject:json)))
        XCTAssertFalse(CursorTrackingSettings(acceleration:.nan).isValid);XCTAssertFalse(CursorTrackingSettings(sensitivity:.infinity).isValid)
    }
    func testResetWhileShortcutHeldRetainsMatchedRelease() throws {
        let binding=ActionBinding(action:.shortcut,shortcut:Shortcut(keyCode:8),shortcutBehavior:.hold)
        var config=ProfileConfiguration(defaultProfile:MouseProfile(bindings:["102":binding]),cursorTracking:tracking)
        var router=InputRouter()
        XCTAssertEqual(router.route(button:102,phase:.down,profile:config.defaultProfile).emissions,[InputEmission(button:102,binding:binding,phase:.down)])
        try config.resetProfile(id:config.defaultProfile.id)
        XCTAssertEqual(router.route(button:102,phase:.up,profile:config.defaultProfile).emissions,[InputEmission(button:102,binding:binding,phase:.up)])
        XCTAssertEqual(config.cursorTracking,tracking)
    }
    func testTransferWhileChordAnchorHeldPreservesItsPressSnapshot() throws {
        var config=configuration();let old=config.defaultProfile;var router=InputRouter()
        _=router.route(button:100,phase:.down,profile:old)
        _=try config.manageProfile(.transfer,sourceID:old.id,target:ApplicationProfileTarget(name:"Editor",bundleIdentifier:"example.editor"))
        for _ in 0..<3 {
            XCTAssertEqual(router.route(button:0,phase:.down,profile:config.defaultProfile).emissions.map(\.binding.action),[.undo])
            XCTAssertTrue(router.route(button:0,phase:.up,profile:config.defaultProfile).suppress)
        }
        _=router.route(button:100,phase:.up,profile:config.defaultProfile)
        XCTAssertFalse(router.route(button:0,phase:.down,profile:config.defaultProfile).suppress)
        XCTAssertEqual(config.cursorTracking,tracking)
    }
}
