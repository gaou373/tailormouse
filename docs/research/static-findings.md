# SteerMouse 5.8: bounded static findings

Inspected 2026-10-11, read-only, from `/Applications/SteerMouse.app`. This is an initial map of input handling and settings structure, not recovered source or a behaviorally complete reconstruction. No target process was launched, attached, or modified. No user settings or personal preference values were read.

## Artifact identities

| Role | Bundle identity | Version from Info.plist | Executable SHA-256 |
| --- | --- | --- | --- |
| Configuration app | `jp.plentycom.app.SteerMouse` | short `5.8(0920)`, build `5.8` | `8829a0c3544b76def71808b7ed09af2fd6049bf110a30bab52eaa5571e4dc9f5` |
| Login-item helper | `jp.plentycom.boa.SteerMouse` | short `5.8(9A56)`, build `5.8` | `b2070391939b6f3f5431cb3fc1c7d89040b5a667ab89917cb653c6f0aca1f30c` |

Main executable: `Contents/MacOS/SteerMouse`. Helper executable: `Contents/Library/LoginItems/SteerMouse Manager.app/Contents/MacOS/SteerMouse Manager`.

Both are universal Mach-O executables with x86_64 and arm64 slices. Both bundle plists declare macOS 12.0 minimum; the helper declares `LSUIElement=true`. Signature metadata identifies Plentycom Systems, team `UHEB36849R`, and hardened-runtime flags on both executables. These are metadata observations, not an independent certificate-validation result. **Evidence: STATIC-01.**

## Input and process architecture

**Observed imports:** both binaries link Cocoa/AppKit, IOKit, Core Data, ApplicationServices, CoreGraphics, Carbon, and ServiceManagement. Both import HID device creation/opening, input value/report callbacks, HID queues, event-system service discovery, acceleration access, and property-setting functions. The helper additionally imports Quartz event taps, keyboard/mouse/scroll event creation and posting, cursor warping, and Accessibility element inspection. The main app imports `SMAppService`; both import `NSDistributedNotificationCenter`. **Evidence: STATIC-02.**

**Inference:** the configuration app and background helper divide UI/settings work and active event processing, with shared HID/settings support. Import presence establishes linked capability, not which branches run or which APIs are supported/documented on each macOS release. The imported IOHID event-system/service functions deserve compatibility scrutiny during a rebuild.

**Observed static control flow:** helper arm64 `-[AppControllerClass(JpPlentycom130) installEventTap]` starts at `0x10002f1a0`. It checks `AXIsProcessTrusted`, constructs event sources, calls `CGEventTapCreate` at `0x10002f2d4` with `_Eventtap_Callback` (`0x10002f378`), then creates a run-loop source and adds it to the current run loop. The callback contains paths to button extraction, click processing, hotkey posting, and tap re-enabling. This confirms a linked event-tap path beyond merely finding an import. It does not prove the path is currently installed or receiving events. **Evidence: STATIC-03.**

## Useful follow-up entry points

All addresses below are unslid virtual addresses in the **helper arm64 slice** with the helper hash above. Objective-C implementation symbols remain available. Names describe candidates; they do not establish complete semantics.

| Question | Symbol or method | Address | Established boundary |
| --- | --- | --- | --- |
| Event admission and dispatch | `-[AppControllerClass(JpPlentycom130) eventProc:type:ButtonIX:clickStatus:proxy:mouse:]` | `0x10002fc90` | Implementation symbol; full dispatch not traced |
| Mouse button mapping | `-[AppControllerClass(JpPlentycom200) mouseClickProc:proxy:buttonIX:clickStatus:pressed:hidModkeys:actData:mouse:]` | `0x100044a10` | Implementation symbol and callback call site |
| Scroll mapping | `-[AppControllerClass(JpPlentycom200) mouseRollProc:proxy:scrollIX:lineAxis:ptAxis:fixedAxis:hidModkeys:mouse:newLineAxis1:newPtAxis1:newFixedAxis1:newLineAxis2:newPtAxis2:newFixedAxis2:newModkeys:]` | `0x100045ab8` | Implementation symbol; axis transforms untraced |
| Action matching | `-[MouseClass(JpPlentycom410) searchActDataForButtonIX:scrollIX:modkeys:]` | `0x100048f18` | Calls `usedModkeys:` and `bsearch_b`; several fallback searches exist |
| Build per-app action data | `-[MouseClass(JpPlentycom410) buildAppDataList:]` | `0x1000487a4` | Implementation symbol only |
| Change active app profile | `-[MouseClass changeApplicationToProc:matchingKeyForSytemPref:deviceIndex:]` | `0x10003c978` | Implementation symbol only; original spelling retained |
| Device report handling | `-[MouseClass processDeviceReport]` | `0x10003c248` | Implementation symbol only |
| Cursor settings | `-[MouseClass setCursorSpeed]` | `0x10003d250` | Implementation symbol only |
| Scroll settings | `-[MouseClass setScrollSensFactor:accl:]` | `0x10003d41c` | Implementation symbol only |
| Restore cursor settings | `-[MouseClass restoreCursorSpeed]` | `0x10003d384` | Implementation symbol only |

Device-specific implementation families include Logitech models (MX Master/Anywhere, G-series), Microsoft, Kensington, Contour, Corsair, and SteelSeries. For example `logitechMXMasterShiftSens:smoothScroll:shiftToRatchet:deviceStatus:` and `logitechG502ChangeDPI:` are named implementation methods. This supports prioritizing device adapters as a separate research area; it does not verify hardware support, identify report protocols, or imply testing with those devices. **Evidence: STATIC-04.**

## Packaged settings model

Both bundles contain byte-identical `Device.momd` model files and `VersionInfo.plist`. The plist explicitly selects **`s500c125`** as current, alongside older `c100` and `s500c120` versions. The current `.mom` SHA-256 is `9fcc177537ae7f100229bef8d73c8be4d7d57ff5f6896a725436f2e6de505003`. Model files were decoded as binary plist keyed archives using `/usr/bin/python3` and `plistlib`; no Core Data store was opened. **Evidence: STATIC-05.**

Current model structure:

| Entity | Managed class | Relevant structure |
| --- | --- | --- |
| `Device` | `PS802DeviceClass` | `vid`, `pid`, `mid` integer identifiers; transport and resolution strings; `buttonCount`; selected app/cursor indices; disable flags; application and cursor-speed collections; transformable expansion fields |
| `Application` | `PS803AppClass` | `bundleID`, `matchingKey`, bookmark, index; scroll acceleration and sensitivity factor strings; disable flags; snapping settings; transformable setup command; action collection |
| `Action` | `PS804ActionClass` | `button` and `modkeys` Integer64; `scroll`, `name`, `funcName` strings; `func` and `expansionData` transformable attributes |
| `CursorSpeed` | `PS805CursorSpeedClass` | sensitivity/tracking-speed strings, acceleration-disable flag, lock/visibility flags, color bytes, index and title |
| `UserInfo` | `PS809UserInfoClass` | Entity presence observed; details outside this input/settings investigation |

Relationships decoded from the archive are `Device.applications ↔ Application.device`, `Device.cursorSpeeds ↔ CursorSpeed.device`, and `Application.actions ↔ Action.application`. Child-to-parent relationships encode minimum/maximum counts `1/1`; collection relationships encode `0/0` (the Core Data archive convention for unbounded maximum). These are schema constraints, not counts of a user's records.

**Observed static persistence path:** `_PS814createMOC` (`0x10000c274`) loads a model from a resource URL and calls `addPersistentStoreWithType:configuration:URL:options:error:` using `NSBinaryStoreType`. Its options include automatic migration and inferred mapping. `_PS814openMOC` obtains its URL from `_PS814prefsFileURL`. A binary store is established for this code path; calling the settings file SQLite would be unsupported. **Evidence: STATIC-06.**

**Unknown:** representation and allowed values inside transformable `func`, `setupCommand`, `partName`, and expansion fields; application fallback precedence; button/modifier bit layout; cursor/scroll acceleration equations; migration compatibility in practice. The schema provides useful design boundaries but is insufficient for importing user settings.

## Static data-location candidates

Binary CFStrings referenced by `_PS814prefsFileURL` decode to `SteerMouse & CursorSense`, `CursorSense`, `smsetting`, `cssetting`, and `Device.smsetting`. `_PS814prefsFolderURL` calls `_PS812urlForDirectory` with directory value `14` and domain mask `1`; that helper passes them to `URLsForDirectory:inDomains:` and appends the selected folder string. **Evidence: STATIC-07.**

**Inference:** the conventional SteerMouse settings candidate is `~/Library/Application Support/SteerMouse & CursorSense/Device.smsetting`. The routine also scans extensions and contains a CursorSense compatibility/copy branch, so the fixed candidate should not be treated as proof of the actual selected file. No filesystem lookup or contents read was performed for these user-data candidates.

Other literal candidates include `/tmp/SteerMouse_Debug.txt` and `SteerMouse_Manager_Log.txt`; only the first is an absolute path. Their existence, enablement, and content are unknown. Static domains `jp.plentycom.app.SteerMouse` and `jp.plentycom.boa.SteerMouse` do not alone establish specific preference-file paths.

## Evidence and reproducibility

Raw outputs stay local under ignored `.local/evidence/static/`. These `STATIC-*` labels are local finding identifiers, **not REA-issued Evidence IDs**. The root investigation owns REA inventory/provider evidence separately. No proprietary executable, resource bytes, disassembly, or full raw strings are included in this tracked report.

| Local finding ID | Source and method | Raw output |
| --- | --- | --- |
| `STATIC-01` | Bundle plists, SHA-256 bytes, `file`, `codesign -dv --verbose=4` | `{main,helper}-{file,signature}.txt`; executable hashes above |
| `STATIC-02` | `otool -L`, `nm -u`, both universal binaries | `{main,helper}-{loads,imports}.txt` |
| `STATIC-03` | `otool -arch arm64 -tvV`, event-tap methods and callback | `helper-arm64-disassembly.txt` |
| `STATIC-04` | `nm -arch arm64 -nm`, selected implementation symbols | `helper-arm64-symbols.txt` |
| `STATIC-05` | Binary plist UID decoding, entity/property dictionaries, SHA-256 and byte comparisons | `schema-structure.json`; packaged `.momd/VersionInfo.plist` |
| `STATIC-06` | arm64 assembly for `_PS814createMOC` and `_PS814openMOC` | `helper-arm64-disassembly.txt` |
| `STATIC-07` | arm64 assembly, Mach-O section mapping, referenced CFString records | `helper-arm64-disassembly.txt`; `cfstring-candidates.json` |

For `STATIC-07`, `otool` reports some CFStrings as `bad cfstring ref` because pointer fixups are encoded. The six selected records at `0x100085ae8` through `0x100085b88` were decoded directly from the selected arm64 slice: map the CFString record virtual address through its Mach-O section, map the low 32-bit target offset of its string pointer relative to `0x100000000`, then read its declared byte length. Each decoded result matches an independently present raw literal. This narrowly verifies those records; it is not a general chained-fixups decoder.

Coverage: linked-library/import tool captures for both executables, surviving symbol and Objective-C metadata capture, all three packaged model versions, and focused arm64 assembly inspection of event-tap setup, callback paths, store setup, path selection, and the beginning of action matching. Import recovery is tool-bounded, not guaranteed exhaustive. No deep decompilation, full call graph, x86_64 behavioral comparison, runtime observation, permissions changes, HID writes, or event posting occurred during this static pass. Further action matching, HID decoding and profile control flow are covered in the companion reports. A full replica remains further work; customization is deferred at the user's request.
