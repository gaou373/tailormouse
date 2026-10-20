# Naga V2 HyperSpeed USB receiver preview

## Diagnosis and scope

The installed 0.4.5 app was stopped with `selectedDeviceFamily` set to
`razer.naga.pro`. The connected mouse identifies as Razer Naga V2 HyperSpeed,
USB vendor/product `1532:00b4`, so its events failed that selection filter.
The raw keyboard discovery and Quartz translation paths also accepted only
original Naga Pro IDs. Selecting All mice alone could not enable this reader.

Read-only IORegistry metadata collected on macOS 27.0.1 on 2026-10-20 shows
three interfaces at the same USB location: a mouse, a boot keyboard and a
composite keyboard. No device opens, input capture or feature writes were used
for this observation. Raw metadata stays in ignored `.local/evidence/`.

The keyboard descriptors declare:

- Report 0: eight bytes, modifier byte, reserved byte, six keyboard usage slots.
- Report 1: sixteen bytes including report ID, modifier byte, fourteen keyboard
  usage slots. The same composite interface has unrelated reports (including
  mouse report 10), which are rejected by the keyboard normalizer.

The IOHID element API returned an empty list during this observation, although
nested IORegistry `Elements` described the keyboard inputs. Discovery now uses
those read-only input element records as a fallback; opening for runtime input
still requires macOS permission and a successful shared device open.

## Implementation

`1532:00b4` has its own `razer.naga.v2.hyperspeed` family and a named mouse-menu
selection. The original Naga Pro family and hardware-writing allowlists remain
separate. Start reports a disconnected selected model instead of silently
running against no matching mouse.

Both receiver keyboard interfaces normalize into the existing side-key decoder.
Snapshots are retained per interface and unioned per physical connection, so
one interface's empty report cannot release another interface's held button,
and duplicate snapshots do not emit duplicate presses. Discovery is restricted
to the selected family. Existing matched release, pre-Start hold, Stop and
permission-loss recovery paths remain in use.

This preview supports the connected USB receiver. HyperSpeed Bluetooth reports,
DPI programming, arbitrary onboard macros and nonstandard keyboard assignments
have not been verified. The twelve numbered/default keypad assignments use the
existing Naga key map. Descriptor evidence establishes packet layout, not the
reports actually emitted by each physical button.

## Validation and physical acceptance

`npm test` passes 225 core tests and four fake-backend native tracking checks.
Six new tests cover identity/transport boundaries, both packet formats, nested
registry discovery, twelve simultaneous side-key slots, matched release across
profile changes, duplicate/composite ownership, rollover, baseline and reset.
The scripts explicitly select SwiftPM's native build system because Xcode 27's
new default places modules/objects differently from these packaging scripts.

To test the preview:

1. Choose **Razer Naga V2 HyperSpeed · USB receiver** in the mouse menu.
2. Check TailorMouse's Accessibility and Input Monitoring permissions.
3. Press Start explicitly. Test an assigned ordinary button and wheel mapping.
4. Open the side-button pages. Test all twelve side buttons, including holding
   and releasing one. Check the Support diagnostics for paired down/up counts.
5. Stop, reconnect the receiver, and Start again; verify there are no stuck keys.

The preview was installed locally with the HyperSpeed family selected. After
the user refreshed permissions and pressed Start, the diagnostic snapshot
reported Running with two raw keyboard endpoints open. No side-button edges
had been observed at that point.

Physical input and reconnect acceptance must be confirmed by the user before
claiming the mouse is fixed. Builds and automated tests never start remapping.

## User feedback

The user confirmed that bindings appear to work on the HyperSpeed trial.
The user also confirmed that Side Button 1 held as Command works with C.
Command+Space inside Premiere remains unresolved; the expected action and
keyboard-only comparison are pending. macOS Spotlight hotkeys 64/65 were
disabled during local inspection. Full twelve-button and reconnect acceptance
remain unverified.

## Preview 2: held modifiers and Excalibur

The user confirmed keyboard Command+Space opens Excalibur, while Side Button 1
held as Command plus keyboard Space did not. Mouse Command+C did work.

Static inspection of the installed shared Spell Book helper (`spell_mac`,
SHA-256 `5bc302eecfb77c1eec45f37a1e6b5220bb216e39b167b7fdd9fb5377b5afe1bf`)
shows imports for `CGEventTapCreate` and `CGEventGetFlags` (REA Evidence
`ev_e291baf2146744992725807149ddbd78b2d111234fb85bc4c300c2f22de45353`).
Independent arm64 disassembly at `0x1000043c0`–`0x1000043d4` passes location 1,
placement 0, options 0 and mask `0x400` to `CGEventTapCreate`: a session-stage,
head-insert active key-down listener. Its callback path reads the key code and
event flags at `0x10000515c`–`0x10000520c`. This is static evidence, not a live
trace of callback ordering. Raw disassembly remains ignored locally.

The Excalibur JavaScript graph was partial and a literal `spellcast` trace had
no matches; that negative result does not establish feature absence (REA
Evidence `ev_e9ad517b90c8e38e8d6c9e005614e0726ae205032f9044c59a30cf0267512982`,
`ev_ccc75865a3e3bdc5b78665c60e19a63a2a33d93db5719dab85eb0e4a8625535d`).

TailorMouse previously composed held modifiers only at its session-stage tap.
Competing session taps therefore expose a possible ordering dependency. Preview
`0.4.6-hyperspeed.2` adds a narrowly scoped HID-stage keyboard bridge that unions
held modifiers into the original key-down and key-up events before session
listeners. It neither records nor reposts keys. Mouse routing stays at the
session stage. Generated TailorMouse events are excluded, physical flags are
preserved, Stop removes the bridge, and tap disablement stops handling and
releases held output. No Excalibur files or shortcut settings are changed.

Validation adds four native bridge checks using unposted events (press/release,
Space key identity and physical flag preservation, generated-event exclusion,
and recovery), alongside the existing 225 core tests and four tracking checks.
The user confirmed that holding Side Button 1 and pressing keyboard Space now opens Excalibur in Premiere on preview 2. Runtime also confirms Running with both receiver keyboard endpoints open. This closes the reported Excalibur reproduction; all-twelve-button and reconnect acceptance remain unverified.
