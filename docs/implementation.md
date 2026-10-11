# TailorMouse 0.2 implementation and validation

Version 0.2.4 adds actual cursor-position application to the pointer speed control. Physical connection grouping, quiet unassigned Naga buttons, transport calibration and persistent press/release labels remain available. See the [wired investigation](research/wired-runtime.md) for the input conflict and the direct macOS correction of this unit's onboard 10/11 macros. All 49 tests pass, including independent standard-layout holds and pointer movement across fractional coordinates, profile changes, other input devices, reset and display boundaries. Physical verification of the new holds and cursor speed remains pending.

The user requested an original recreation and installation after the static research milestone. This document describes TailorMouse behavior, not recovered SteerMouse source or verified feature parity.

## Relationship to evidence

The target helper SHA-256 is `b2070391939b6f3f5431cb3fc1c7d89040b5a667ab89917cb653c6f0aca1f30c`; configuration app SHA-256 is `8829a0c3544b76def71808b7ed09af2fd6049bf110a30bab52eaa5571e4dc9f5`. See [research index](research/README.md) for complete evidence identifiers and target inventory.

| Observed target fact | Evidence | Independent TailorMouse decision |
| --- | --- | --- |
| Configuration app and nested manager divide UI and processing responsibilities | REA Apple graph `ev_37a1afa6b9d037507715517d52a20e373b3a7416773d06f24e5f9a33ec11227b`; `STATIC-01/02` | Single SwiftUI app with a stopped-by-default processor; no login helper |
| Helper installs a Quartz event tap and reads numeric field `0x57` | `STATIC-03`, `INPUT-02`, [input pipeline](research/input-pipeline.md) | Session event tap; field 87 used as a candidate sender identity, strictly matched to IOKit device metadata |
| Razer report callback dispatches changed button presses and releases | `INPUT-01`, same hash-pinned input report | Independent router snapshots down mappings and handles matching up/drag; no copied report parser or vendor initialization |
| Compiled profiles use application matching | `INPUT-06`; REA UI graph `ev_b67425e6ce1700aa3d666cbca72bbd1e0bc65128033196775eb24c11fab83eb5` | Bundle-identifier lookup and original Codable JSON schema |

These observations support design choices but do not establish that field 87 is stable or that TailorMouse receives every physical button. The app's keyboard translator covers original Naga number-row and numpad default mappings only for positively identified Naga senders. An unrelated keyboard is never translated. Unknown senders pass through in the default Naga mode.

## Implemented behavior

Profiles include button bindings, exact modifier combinations, side-button chords, separate discrete wheel axes and pointer gain. Naga product IDs `0x008f`, `0x0090`, and `0x0092` under vendor `0x1532` share `razer.naga.pro`; connection-specific state remains separate so one mouse cannot complete another mouse's chord. One profile set follows those transports. Device discovery enumerates metadata without opening/seizing HID devices or registering input report callbacks.

Mappings fire complete shortcut/click pairs on press. Chord prefixes defer their individual actions until resolved; an unmatched prefix replays its captured single action. Repeated downs cannot duplicate an action. A press retains its original mapping across profile switches and edits. Stop, tap disable, permission loss, manager conflict and device disappearance clear internal state; synthetic actions never leave a held key or button. Changing the selected device family stops active handling.

Default and per-app profiles are independent snapshots. Legacy v1 TailorMouse profiles migrate to v2; missing, corrupt and imported settings are validated and preserved in separate backups before replacement. All-mice mode is encoded explicitly as null and survives reload.

Discrete scroll ticks preserve fractional scaling, independently per axis. Continuous scrolling passes through. Pointer gain scales changes in the actual global pointer coordinates above macOS tracking, preserving fractional movement. The first movement seeds the baseline. Subsequent movement uses the last applied cursor position; untouched movement from another device rebases that shared position. Display-edge clamping uses the nearest screen rectangle. The session event is updated and the public `CGWarpMouseCursorPosition` API applies the visible cursor position without generating another event. Relative deltas are restored after updating location. Warp failure leaves the native event untouched and stops handling. Start/Stop reset the baseline. This does not change hardware DPI or replace macOS acceleration.

The explicit `scripts/naga-onboard-read.swift` diagnostic reads bounded vendor GET commands on one original wired Naga Pro control interface. The separate `scripts/naga-onboard-correction.swift --apply` diagnostic backs up and changes only normal-layer side-10/11 functions in the active profile and effective mirror; `--restore <backup.json>` restores saved function blocks after validating device location, active profile and slot scope. These tools are not invoked by the app, build, tests or installer. User device settings and results remain ignored.

## Validation and remaining acceptance work

Repository `swift test` passes all 49 tests on this Mac. Coverage includes twelve Naga logical buttons in both default key banks, identity aliases, migration, configuration round trips, modifier fallback, matched down/up/drag across edits, repeats, chord snapshots, unmatched-prefix recovery, source isolation, reset, scrolling fractions, finite speed limits and pointer profile changes. Diagnostic self-checks additionally validate read/write framing, reverse-order recovery after a simulated landed-write failure, no-op writes and private backup serialization without opening devices. Release packaging uses the host architecture and an ad hoc signature.

Metadata enumeration identified the attached Bluetooth Razer Naga Pro and its event-service candidates. This validates discovery only. UI and installation checks leave processing stopped; active physical-input checks are intentionally pending:

1. With TailorMouse permissions enabled and competing managers stopped by the user, verify ordinary buttons and side buttons 1–12 over Bluetooth, wired USB and receiver.
2. Confirm sender attribution on every transport, including separate USB keyboard interfaces and reconnects. Unknown or ambiguous attribution must pass through.
3. Verify app switching while holding a mapped button, modifier mappings, matched chord releases and incomplete chord recovery.
4. Verify wheel direction/speed and pointer movement across all connected displays. Confirm Stop restores pass-through.
5. Confirm no duplicate actions, unexpected typing, permission-loss capture or resumed interception after tap disable.

Vendor-specific raw HID report decoding, hardware initialization, button reports absent from macOS, acceleration curves, smooth-scroll synthesis, held-action dragging, SteerMouse-format import and complete target parity are not implemented. The original Bluetooth 10–12 and USB/dongle hardware issues are not claimed fixed.
