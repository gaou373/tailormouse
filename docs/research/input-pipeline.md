# SteerMouse input pipeline: assembly-derived map

This pass investigates the shipped app before any fix or customization. Findings are static observations of the helper's arm64 slice, not executed behavior or recovered original source. No input capture, HID write, permission grant, preference read, target launch, or process modification was performed.

## Identity and evidence boundary

Target: SteerMouse 5.8, nested **SteerMouse Manager** executable, SHA-256 `b2070391939b6f3f5431cb3fc1c7d89040b5a667ab89917cb653c6f0aca1f30c`. Every address below is an unslid helper arm64 virtual address. Native `otool -arch arm64 -tvV` output and `nm -arch arm64 -nm` output were reused from ignored `.local/evidence/static/`.

Package context is REA artifact inventory Evidence `ev_2dde61a09d55ffe8ae6789bce1236c0bd57b300d09a30f6954c2252e03c233cd` and Apple application graph Evidence `ev_37a1afa6b9d037507715517d52a20e373b3a7416773d06f24e5f9a33ec11227b`. Those IDs support package context only; the assembly conclusions below use local finding IDs `INPUT-01` through `INPUT-06`, **not REA-issued evidence**. The deep-provider limitation and full artifact identity are recorded in [static-findings.md](static-findings.md).

## Components and two input routes

Surviving implementation names identify `AppControllerClass`, `MouseClass`, `PS834DeviceDefinition`, `PS802DeviceClass`, `PS803AppClass`, `PS804ActionClass`, and `PS805CursorSpeedClass`. This names a controller, runtime device object, device definitions, and managed settings objects; responsibility assignments are an inference until their methods are traced.

Two traced routes coexist:

1. `MouseClass` configures model-specific HID interfaces. Keyboard report callbacks filter report IDs, run device setup/status processing, and call the currently installed model callback. The Razer callback translates selected keyboard report bytes into button-state changes and calls `postClickEvent:pressed:senderID:proxy:`.
2. `AppControllerClass` installs a Quartz event tap. `_Eventtap_Callback` dispatches accepted events to `eventProc:type:ButtonIX:clickStatus:proxy:mouse:`. That method updates button/chord state, selects compiled action data, and invokes click or scroll processing. Output paths can mutate an event, post an additional event, or return a null event pointer.

These routes are observed call edges, not proof of which route a particular physical Naga Pro button currently uses. The precise path from every synthesized HID click back into the tap has not been exhaustively traced.

## INPUT-01: HID callback registration and adapter lifecycle

`startKBInterfaceReportCallback:` (`0x10003fc54`) reads the stored callback, returns if absent, opens the selected HID device with options `0`, and registers `_KBInterface_Report_Callback` (`0x10003fcbc`) with a `0x80`-byte buffer and `MouseClass` context. This is a directly traced registration path, beyond imported API presence.

The wrapper returns immediately on a nonzero callback result. Otherwise it calls `getKBReportIDFromDevice:`, compares the incoming report ID, marks a running flag, saves the callback pointer, and calls `processDeviceReport`. It invokes the saved callback only if it is nonnull **and still equals the current stored pointer after setup**; it then clears the running flag. This guards against dispatching to an adapter callback replaced during setup. Report length is forwarded to that callback. The selected Razer decoder described below does not visibly use that length before its byte reads; validity of upstream framing is an unresolved boundary.

`processDeviceReport` (`0x10003c248`) checks an elapsed-time condition, can add status bit `2`, updates access time, checks device/controller state, and conditionally calls `setupDevice`. The method name should not be mistaken for a generic byte decoder: the traced body manages setup/status.

`setupDevice` (`0x10003c320`) branches on vendor values to Microsoft (`0x045e`), Logitech (`0x046d`), Kensington (`0x047d`), Mad Catz (`0x0738` / `0x12cf`), Razer (`0x1532`), or miscellaneous setup. Other surviving symbols include COM and consumer/system-interface report and value callback variants. Their existence is symbol evidence; this pass traced the keyboard report wrapper, not every sibling wrapper or failure path.

## INPUT-02: original Naga Pro uses the Trinity adapter

`setupDeviceRazer` (`0x100015cc0`) routes product IDs `0x008f` and `0x0090` to `razerNagaTrinity` (`0x100015dec`). Packaged personality summaries independently name these as **Naga Pro (Wired)** and **Naga Pro (USB)**. Naga V2 Pro is a separate packaged identity and must not be substituted for the original model.

The adapter installs `_RazerNagaTrinity_Callback` (`0x1000160b4`) on a keyboard report interface and on a COM interface selected with usage-page/page arguments `1` / `0x80`. It also calls report-setting and device-control methods. For `pid == 0x0090`, a timed setup branch uses a stored byte flag and elapsed intervals selected as `0.5` or `2.0` seconds. This establishes setup retry/state handling, not the reason for that timing or a guaranteed successful wireless handshake.

The callback has three distinct byte-processing branches:

- A report beginning `05 09 03 01` sets a device status bit and clears the timed setup flag. Calling it an acknowledgement is an inference from its effect.
- For a nonnull sender and report ID `4`, it checks two bytes at offsets `1` and `2`: `0x20` / `0x57` set internal mask bit `7`; `0x21` / `0x52` set bit `8`. Other button bits are preserved.
- For report ID `0` and a nonnull sender, it clears mask bits `9–20`, scans up to six bytes starting at offset `2`, and uses a jump table to set those twelve bits. A zero byte ends scanning. With a null sender, it instead transfers two bits from the first report byte to mask bits `5–6`.

The report-ID-zero mapping is:

| Byte value | Internal button index | Mask bit |
| --- | ---: | --- |
| `0x1e` | 9 | `0x200` |
| `0x1f` | 10 | `0x400` |
| `0x20` | 11 | `0x800` |
| `0x21` | 12 | `0x1000` |
| `0x22` | 13 | `0x2000` |
| `0x23` | 14 | `0x4000` |
| `0x24` | 15 | `0x8000` |
| `0x25` | 16 | `0x10000` |
| `0x26` | 17 | `0x20000` |
| `0x27` | 18 | `0x40000` |
| `0x2d` | 19 | `0x80000` |
| `0x2e` | 20 | `0x100000` |

Do not equate an internal button index with the printed side-panel number without a report capture. The twelve distinct masks establish decoder capacity, not physical button availability on Bluetooth, USB, or dongle.

After any branch computes a new mask, the callback XORs it with the previous mask. For changed bits in internal indices `5–20`, it calls `postClickEvent:pressed:senderID:proxy:` with `pressed` taken from the new mask, then stores that mask. Thus this particular path emits transitions for both presses and releases rather than posting a press for every repeated report. Six input slots also bound this path's simultaneous-key representation; they do not establish the mouse's hardware rollover limit.

## INPUT-03: Quartz admission, chords, and paired actions

`installEventTap` (`0x10002f1a0`) checks Accessibility trust, calls `CGEventTapCreate` with `_Eventtap_Callback` (`0x10002f378`), and attaches a run-loop source. This was already traced in `STATIC-03`.

The callback reads integer event field `0x57` (kept numeric here because this pass does not verify SDK naming), has a type `10–12` branch calling `isTargetedKBSenderID:`, and returns a null event for targeted senders on that branch. Its high-event-type branch checks trust and calls `CGEventTapEnable` except for the `-1` case. Other branches extract button fields, handle proxy key-up/hotkey paths, and dispatch to `eventProc...` at `0x10002f794`. It is not a universal forwarder: its return pointer is conditional.

`eventProc...` (`0x10002fc90`) reads event flags, calls `changeButtonStatus:click:`, and obtains a chord-participation mask through `chordingButtonForModkeysVal:list:` (`0x10001c008`). That helper starts with a default mask and can select an exact normalized-modifier mask from a list of 16-byte entries.

For a participating first button with click status `1` and one pressed button, the dispatcher stores `chording1stButtonIX`, clears `chordingIgnore1stButton`, and returns null. If that same first button is later released and was not ignored, it resolves the single-button action, synthesizes a press through click processing, posts it, and then processes release. **Inference:** this delays a potential chord prefix while preserving an ordinary click when no chord consumes it. Static branches establish the mechanism, but the entire chord cancellation and multi-button precedence policy remains partially traced.

The normal press path resolves action data and stores its pointer in `buttonActData[buttonIX]`. Subsequent processing retrieves that stored pointer; after click status `2`, it clears the slot. This is evidence of press/release action pairing and avoids assuming release always rematches the current modifiers. Global release/recovery methods survive as implementation symbols; their complete lifecycle coverage is not yet established.

## INPUT-04: compiled action records and exact fallback order

`actDataObjWithAction:` (`0x100048a20`) writes `buttonVal`, `scrollIX`, `modkeysVal`, and `selectorIX` into offsets `0x00`, `0x08`, `0x10`, and `0x18`. Action-specific payload fields follow. `appDataObjWithActionList:` (`0x100048d04`) allocates a 16-byte header, appends 128-byte records, sorts them with `qsort_b`, stores a count at header offset `8`, and appends chord metadata. This is an in-memory dispatch representation, not the on-disk settings format.

`searchActDataForButtonIX:scrollIX:modkeys:` (`0x100048f18`) uses `bsearch_b` with record size `0x80`. All six comparison blocks compare the first three 64-bit fields in order after byte reversal. A candidate whose selector at offset `0x18` equals `2` falls through or is treated as null; the user-visible meaning of selector `2` is not established here.

The following is **handwritten explanatory pseudocode derived from assembly**, not decompiler output or original source:

```text
m = usedModkeys(inputModifiers)
search (currentHeldButtonMask, requestedScroll, m)
if absent and m != 0: retry with modifiers = 0
if candidate exists and selector != 2: return candidate

if requestedScroll == MAX_SIGNED_64:
    if currentHeldButtonMask == (1 << requestedButton): return null
else:
    if currentHeldButtonMask == 0: return null

if requestedButton <= 31:
    search (1 << requestedButton, MAX_SIGNED_64, m)
    if absent and m != 0: retry with modifiers = 0
    if candidate exists: return null if selector == 2, else candidate

if requestedScroll <= 8:
    search (0, requestedScroll, m)
    if absent and m != 0: retry with modifiers = 0
    if candidate exists: return null if selector == 2, else candidate
return null
```

The full held-button mask is attempted before a single-button or scroll-only fallback. A modifier-zero retry is triggered by **absence**, not by selector `2`; that distinction matters to inheritance/matching interpretation. Button/scroll comparisons are unsigned at the bounds shown above. The sentinel is `0x7fffffffffffffff`.

`usedModkeys:` (`0x10001c504`) computes `((input >> 13) & 1) | (input & 0x2b) | ((input >> 1) & 0x2a)`. This collapses some source bits into a smaller match key. The exact named modifier semantics are deliberately left unanswered until corroborated with the conversion routines.

## INPUT-05: click and scroll action destinations

`mouseClickProc...` (`0x100044a10`) returns null immediately when action data is absent. Its selector/payload branches call routines for mouse click mutation, modifier posting/release delays, line scrolling, auto-scroll, shortcut/macro posting, app activation/file opening, snapping, model control, zoom/swipe gestures, media/system keys, and repeat scheduling. Representative traced call sites:

| Destination | Call-site address |
| --- | --- |
| `postKeyForShortcut:...` | `0x100045104` |
| `postLineScrollAxis1:axis2:...` | `0x10004529c` |
| `postKeyMacro:...` | `0x100045478` |
| `autoScroll:pressed:...` | `0x100044c24` |
| `deviceControl:pressed:` | `0x100045160` |
| `activateAppInAction:` / `openFileList:` | `0x100045050` / `0x100045064` |
| `postNavigationSwipe:proxy:` | `0x100045804` |

These are calls observed inside dispatch branches; their callee algorithms and every selector enum value are not fully recovered. Repeat paths call `NXKeyRepeatThreshold`, `NXKeyRepeatInterval`, and `dispatch_after`. This establishes dependencies, not exact effective repeat timing.

`mouseRollProc...` (`0x100045ab8`) resolves an action using the button sentinel and requested scroll index. It compares the current event timestamp and direction to previous scroll state. One selector `6` branch computes line/point outputs from a payload magnitude, with sign selection and a factor of ten between two integer outputs. Other branches set scroll sensitivity, route to zoom gestures, or mutate output axes/flags. The caller in `eventProc...` compares returned line, point, fixed-axis, and modifier values with originals and writes only changed fields through `CGEventSetIntegerValueField`, `CGEventSetDoubleValueField`, and `CGEventSetFlags`.

Therefore wheel processing includes action matching and multi-representation axis mutation. The complete acceleration equation, exact units for all payloads, horizontal-scroll policy, and smooth/auto-scroll timer behavior remain unresolved.

## INPUT-06: app-profile compilation versus activation

`buildAppDataList:` (`0x1000487a4`) obtains a default action list, builds compiled data for default/system actions, iterates nondefault applications, calls `SM702appActionListForApp:defActionList:`, compiles the merged result, and inserts it keyed by `matchingKey`. It finishes with `setAppDataList:`. This statically establishes per-application compiled lookup data and a default-action merge call.

The active-application selection method `changeApplicationToProc:matchingKeyForSytemPref:deviceIndex:` survives at `0x10003c978`. Its complete selection precedence is outside this pass and should not be inferred merely from the compiled dictionary. Shared transport identities and storage are investigated separately.

## Finding ledger and reproducible local references

Line numbers refer to the reused `.local/evidence/static/helper-arm64-disassembly.txt`; raw disassembly is ignored and not included in this report.

| Finding | Native evidence lines / auxiliary file | Status |
| --- | --- | --- |
| INPUT-01 | 65514–65620; 61693–61792 | Keyboard report registration/wrapper and vendor dispatch traced; sibling wrappers partial |
| INPUT-02 | 21581–22009; `naga/callback-jump-table.json`; `naga/razer-personalities.json` | Naga original USB decoder traced; physical side-button and Bluetooth correspondence unresolved |
| INPUT-03 | 48102–48378; 48689–49101; 28100–28135; symbol ivars `chording1stButtonIX`, `buttonActData` | Dispatch and pairing traced; complete chord recovery partial |
| INPUT-04 | 74878–75197; 75198–75471; 28439–28447 | Packed layout and complete search routine traced |
| INPUT-05 | 70666–72340; focused beginnings 70666–70770 and 71737–71860 | Call destinations and selected axis mutations traced; many callee semantics unresolved |
| INPUT-06 | 74715–74876 | Per-app compilation traced; activation/fallback precedence partial |

This is a bounded functional map, not a completed whole-app reverse engineering effort. Remaining high-value questions include HID interface discovery/activation failure handling, transport identity normalization, all action selector names, chord cancellation and global release recovery, app switching during held actions, output-event provenance/recursion control, and cursor/scroll acceleration equations. Static results alone cannot establish whether the installed helper is currently processing a physical button.
