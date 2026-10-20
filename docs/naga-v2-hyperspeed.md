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
