# SteerMouse profile and persistence architecture

This pass reverse engineers packaged code before any fixing or customization. It is a read-only static investigation of the helper's **arm64** slice. The pseudocode below is handwritten from assembly, with explanatory variable names; it is neither original source nor decompiler output. No target method was executed, no user preference store or user definition folder was inspected, and no override was installed.

Target helper SHA-256: `b2070391939b6f3f5431cb3fc1c7d89040b5a667ab89917cb653c6f0aca1f30c`, installed SteerMouse Manager 5.8(9A56), inside `/Applications/SteerMouse.app`. Configuration app SHA-256: `8829a0c3544b76def71808b7ed09af2fd6049bf110a30bab52eaa5571e4dc9f5`. Every address in this report is an unslid helper arm64 virtual address.

REA artifact context remains the original inspection `ev_fb3796420edd63980209c029cbb5371edc1ab541acb1ea17a97053c761015eb8`, inventory `ev_2dde61a09d55ffe8ae6789bce1236c0bd57b300d09a30f6954c2252e03c233cd`, and Apple graph `ev_37a1afa6b9d037507715517d52a20e373b3a7416773d06f24e5f9a33ec11227b`. Those records establish packaged scope; they do **not** supply the assembly conclusions below. `PROFILE-*` identifiers are local finding IDs, not REA Evidence IDs. Assembly sources are the ignored `.local/evidence/static/helper-arm64-disassembly.txt`; line references are 1-based and refer to that exact capture. Selected fixed strings are in ignored `profile-constants.json` and `naga/cfstrings.json`.

## Device identity is normalized before settings lookup

**Observed, PROFILE-01.** `-[MouseClass loadMOC:matchingKeyForSytemPref:deviceIndex:]` (`0x10003c55c`, lines 61894–62016) reads physical `vid/pid/mid/transport` fields, calls `_PS834deviceDefDataPersonality` (`0x100018014`, lines 23882–23927), then uses the returned identifiers in `_PS814fetchDevice` (`0x10000c68c`, lines 11663–11739).

The fetch constructs entity `Device` and the fixed predicate `vid == %d AND pid == %d AND mid == %d AND transport == %@`, executes it in the supplied context, and takes `lastObject`. There is no location ID or serial number in this predicate. No explicit sort or fetch limit occurs in this routine. A null context follows an error path and returns null.

```text
loadMOC(context, settingsPreviewKey, settingsPreviewDevice):
    dataIdentity = normalizeViaDeviceDefinition(physicalIdentity)
    device = fetchDevice(dataIdentity, context)
    if device exists:
        searchAndApplyDeviceDefinition(device)
    else:
        device = insertDefinedDevice(dataIdentity, client, context, -1.0, -1.0)
        if device is null: fatalErrorPath()
    self.deviceObj = device
    cache buttonCount, hScrollOp, needsButtonFixer,
          setupImmediately, autoPowerOffInterval
    self.defaultApplication = device.defApplication
    buildAppDataList(context)
    clear cached action/state fields
    changeApplicationToProc(null, settingsPreviewKey, settingsPreviewDevice)
```

**Observed, PROFILE-02.** `_PS834deviceDefDataPersonality` initializes all requested outputs to the physical identity, selects a definition, and calls `-[PS834DeviceDefinition dataVID:dataPID:dataMID:dataTransport:forVID:pid:mid:transport:]` (`0x100018ec4`, lines 24852–24992). That method chooses a matching personality and examines `dataPersonality` there. If that dictionary has no entries, it examines definition-level `dataPersonality`. No recursive alias chaining appears in these two routines.

```text
alias = dictionaryOrNull(selectedPersonality["dataPersonality"])
if alias.count == 0:
    alias = dictionaryOrNull(definition["dataPersonality"])
for each requested numeric output (vid, pid, mid):
    if alias.count != 0:
        output = numberOrNull(alias[field]).intValue
    else:
        output = physical[field]
if transport output is requested:
    output = physical.transport if alias.count == 0
             else stringOrNull(alias["transport"])
```

An important edge case: a nonempty alias dictionary **does not preserve each missing field independently**. Absent/wrong-type numeric fields take the Objective-C null-message `intValue` path (zero); absent/wrong-type transport becomes null. This is observed control flow, not a recommendation to install a definition.

**Inference:** different physical identities can resolve to the same settings record through this alias layer. Transport-specific records are explained by the four-field predicate when normalization leaves different tuples. This pass does not establish which tuple a currently attached Naga Pro actually resolves to.

Packaged corroboration, not a proposed fix: `Razer Naga Pro.xml` (SHA-256 `ee10b922f9600213b0693af4a1c002d7f6c8c3c1c6e14506dfb71fc1a52b60ef`) supplies two physical personalities, vendor `5426`, product `143` and `144`, without an alias. `Razer Naga V2 PRO.xml` (SHA-256 `0ee8c972892793a172e7f633772b6ba0778a5d19ee834b626a29307b49397915`) includes three personalities aliasing to vendor `5426`, product `168`, transport `USB`. This proves that the packaged format uses alias dictionaries; it does not prove compatibility between those models. Source: ignored `naga/definition-structure.json`.

## Definition matching and the user-definition loader

**Observed, PROFILE-03.** `+[PS834DeviceDefinition scoreForPersonality:vid:pid:mid:transport:]` (`0x100018b90`, lines 24644–24749) requires a nonzero matching numeric vendor ID. A specified nonzero product or model ID must match. Base score is `1000` for a vendor match, `1100` for a vendor-and-product match; a specified matching model adds `10`. A nonempty transport is compared by **hash**, and adds `1` if hashes match, otherwise rejects with zero. The assembly does not use string equality in that last comparison.

`personalityForVID:pid:mid:transport:score:` (`0x100018d34`, lines 24750–24841) chooses the first personality with a strictly better score. `_PS834deviceDefFromList` (`0x100017a6c`, lines 23516–23638) considers positive definition scores. On equal scores it favors `inUserFolder` over a bundled definition. Among equal-origin candidates, a nonzero `createDate` comparison replaces the incumbent; if dates compare equal, a nonzero numeric-option `osVersion` comparison also replaces it. These branches do **not** establish a newest-date-wins rule: the comparison result is tested for zero, not direction. The collection is a set, so do not infer a stable ordering for ties from filenames.

**Observed, PROFILE-04.** `_PS834deviceDefList` (`0x100017c98`, lines 23657–23797) caches the resulting set. On first initialization it:

1. Calls `_PS814prefsFolderURL(1, null)` and appends fixed `Device Definitions`.
2. Checks reachability and has a branch that creates the directory if absent.
3. Loads definitions with `_PS834deviceDefsInDirectory` (`0x100017ec8`, lines 23798–23881), selecting exact `xml` extension and calling `deviceDefinitionWithURL:`.
4. Marks loaded user definitions `inUserFolder=true`.
5. Merges definitions from `resourceURL/Device Definitions` of discovered SteerMouse and CursorSense bundles.
6. Removes definitions whose `isAvailableForCurrentOS` returns false, then retains the cached set.

`_PS814prefsFolderURL` (`0x10000bf88`, lines 11205–11215) selects `SteerMouse & CursorSense` for its nonzero first argument, then calls `_PS812urlForDirectory` (`0x10001d508`, lines 29525–29556) with domain `1` and directory `14`. Those conventional Foundation enum values yield the inferred folder `~/Library/Application Support/SteerMouse & CursorSense/Device Definitions`. **The construction is statically confirmed; actual filesystem contents, runtime reachability and installed user overrides remain unknown.** Nothing in this investigation called the loader or its directory-creation branch.

## Application profiles have two related fallback paths

**Observed, PROFILE-05.** `-[MouseClass changeApplicationToProc:matchingKeyForSytemPref:deviceIndex:]` (`0x10003c978`, lines 62159–62203) uses `NSWorkspace.frontmostApplication` when no process is supplied. It normally derives a key from the process. When the process bundle ID is the fixed `jp.plentycom.app.SteerMouse` and the mouse matches the provided device index, it retains the supplied preview/settings key instead.

`+[PS803AppClass matchingKeyFromProc:]` (`0x100041954`, lines 67455–67478) uses the bundle URL's last path component when present; otherwise it converts the executable URL path through `pathWithoutHomeDirectory:`. This is not simply bundle-ID profile matching.

`compareMatchingKey:to:` (`0x1000419dc`, lines 67491–67528) returns true when both keys are empty and false when only one is empty. Otherwise it searches `"/" + storedKey` for `"/" + requestedKey` with options `0xd` (case insensitive, backwards, anchored). **Inference from Foundation option semantics:** matching uses a case-insensitive suffix comparison with a path-component boundary. The installed Xcode macOS SDK's `Foundation.framework/Headers/NSString.h`, lines 50–54, confirms these bit values and the end-anchoring rule. `isEqualToMatchingKey:` (`0x100041a70`, lines 67529–67542) delegates to that method. Multiple matches are not disambiguated here.

`-[MouseClass changeApplicationToMatchingKey:]` (`0x10003c744`, lines 62017–62158) separately selects the managed Application object and cached action bytes:

```text
selectedApplication = first enumerated device.applications matching key
if none: selectedApplication = defaultApplication

oldData = activeAppData
activeAppData = null
for storedKey in appDataDictionary:
    if compareMatchingKey(storedKey, key):
        activeAppData = appDataDictionary[storedKey]
        break
if activeAppData is null:
    activeAppData = appDataDictionary[""]
cache first word from activeAppData.bytes
smoothScrollSensitivity = device.SM702smoothScrollSens
if sensitivity != 0 and !selectedApplication.SM703actualSmoothScrollOn:
    sensitivity = 0
return activeAppData != oldData
```

The default dictionary key is the decoded empty CFString at `0x100085a08`. The method returns whether the cached data **pointer** changed, not a deep byte comparison. The loop order is the collection's enumeration order; no specificity ranking appears in this method. The derivation of `defApplication`, construction of the cached byte structure and all ambiguous-key behavior remain separate questions.

## Shared store and distributed notification reloads

**Observed, PROFILE-06.** `_PS814createMOC` (`0x10000c274`, lines 11395–11509) loads packaged `Device.momd`, constructs a persistent-store coordinator, and adds an `NSBinaryStoreType` store at the provided URL, enabling automatic migration and inferred mapping. The read-only argument calls `setReadOnly:true` after store creation and clears the new context's undo manager; the other branch creates a context without that change. `_PS814openMOC` (`0x10000c43c`, lines 11510–11545) obtains the URL from `_PS814prefsFileURL` then delegates. See STATIC-05–07 in [static findings](static-findings.md) for the model, settings-path selection and matching model hashes; no user store was opened.

**Observed, PROFILE-07.** `_PS824registerBOANotification` (`0x10003eb9c`, lines 64429–64451) registers on a shared center; `_PS824postBOANotification` (`0x10003ec2c`, lines 64467–64537) builds or augments a dictionary with optional `Receiver`, `Command`, `VID`, `PID`, `MID`, `Transport` fields, and posts fixed notification `jp.plentycom.smcs` with `deliverImmediately=true`. Objective-C metadata (`helper-objc.txt`, line 6025) identifies the class reference as `NSDistributedNotificationCenter`; this agrees with the linked imports. It accepts an object argument and caller-supplied extra dictionary. This pass did not post any notification.

The receiving `-[AppControllerClass(JpPlentycom120) boaNotification:]` (`0x10003db5c`, lines 63367–63634) filters nonempty `Receiver` against its main-bundle ID. It contains a special Accessibility-prompt command and then a trust gate; settings-preview and app-launched handling have separate branches. The general reload branch at `0x10003ddf0` calls `releaseAllActions`, `openMOC:`, `loadMOC`, and `reloadSnappingAppList`, before command-specific cursor/device operations. This statically connects a settings notification to safe release of actions and a rebuilt configuration view; execution, reload latency and synchronization races were not measured.

Decoded operation literals include `Cursor Speed Cmd`, `Cursor Speed Activate Cmd`, `Auto Cursor Snapping Cmd`, `Upload Cursor Speed Cmd`. Exact argument semantics and the complete command vocabulary were not reconstructed here. The notification name alone is not evidence of authentication or a security boundary.

## Reproduction and coverage

Run `python3 scripts/research-profile-constants.py > .local/evidence/static/profile-constants.json` to reproduce the selected fixed-string decoding. It verifies the full helper executable hash, selects the arm64 fat-binary slice, maps Mach-O sections and decodes only the listed CFString records using the target-specific low-32-bit offset observation described in STATIC-07. It is intentionally not a general fixup decoder. Its output is ignored raw evidence. This pass reuses prior REA/native captures rather than claiming a new REA decompilation.

Answered statically: the four-field settings lookup; alias normalization before lookup; supported packaged alias format; definition scoring and bounded tie behavior; user-folder loader construction; process-key derivation; application/default fallback; binary-store setup; notification-triggered release/reload chain.

Partially answered: application data generation and default-object derivation; shared persistence across all helper/main call sites; notification command protocol; effects of equal-score/equal-key enumeration; definition cache invalidation and error handling. Unresolved: actual user records, current device-selected definition, all migration behavior, dynamic races, x86_64 equivalence, and what each physical button emits. No hardware tests or fixes are part of these findings.
