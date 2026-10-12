# TailorMouse 0.2 implementation and validation

Version 0.2.5 removes the cursor-warp correction after physical use of 0.2.4 caused difficult movement and slider dragging. Native movement passes through untouched. A separate explicit USB DPI control backs up, writes, reads back and recovers the original wired Naga Pro's live sensitivity. A runtime check using the same transport code verified 3200 → 1600 → 3200 DPI and unchanged persisted DPI. All 62 tests pass; physical comfort with the replacement UI and fresh side-button holds remains pending.

Version 0.2.6 replaces the sidebar layout with a compact dark tabbed window based on the user's screenshots. The top row contains Start/Stop, profile selection, Edit and device selection. Button assignments use eight ordinary-button rows, two six-button side-panel pages and an additional-button menu. The modifier strip chooses mappings, and a separate editor keeps edits in a local draft until OK; Cancel discards them. Default restoration and inherited modifier mappings remain available. Other tabs retain wheel, chord, USB DPI, calibration and input activity controls. The first launch adopts a 680×510 content size before preserving future user resizing. The mouse illustration is independently drawn vector artwork. No input engine or profile schema changed. A separate AppKit renderer uses an in-memory preview model and exports ignored PNGs without reading/writing user settings, runtime status, activating interception or writing hardware.

Version 0.2.7 adds direct original-Naga Bluetooth side-button input after HID reports were observed without Quartz keyboard events. The [Bluetooth report investigation](research/bluetooth-runtime.md) documents scope, capture replay, deduplication, matched holds and recovery. The listener is active only after Start and uses shared device access; discovery itself stays metadata-only.

The user requested an original recreation and installation after the static research milestone. This document describes TailorMouse behavior, not recovered SteerMouse source or verified feature parity.

## Relationship to evidence

The target helper SHA-256 is `b2070391939b6f3f5431cb3fc1c7d89040b5a667ab89917cb653c6f0aca1f30c`; configuration app SHA-256 is `8829a0c3544b76def71808b7ed09af2fd6049bf110a30bab52eaa5571e4dc9f5`. See [research index](research/README.md) for complete evidence identifiers and target inventory.

| Observed target fact | Evidence | Independent TailorMouse decision |
| --- | --- | --- |
| Configuration app and nested manager divide UI and processing responsibilities | REA Apple graph `ev_37a1afa6b9d037507715517d52a20e373b3a7416773d06f24e5f9a33ec11227b`; `STATIC-01/02` | Single SwiftUI app with a stopped-by-default processor; no login helper |
| Helper installs a Quartz event tap and reads numeric field `0x57` | `STATIC-03`, `INPUT-02`, [input pipeline](research/input-pipeline.md) | Session event tap; field 87 used as a candidate sender identity, strictly matched to IOKit device metadata |
| Razer report callback dispatches changed button presses and releases | `INPUT-01`, same hash-pinned input report | Independent router snapshots down mappings and handles matching up/drag; no copied report parser or vendor initialization |
| Compiled profiles use application matching | `INPUT-06`; REA UI graph `ev_b67425e6ce1700aa3d666cbca72bbd1e0bc65128033196775eb24c11fab83eb5` | Bundle-identifier lookup and original Codable JSON schema |

These observations support design choices but do not establish that field 87 is stable or that TailorMouse receives every physical button. The app's keyboard translator covers original Naga number-row and numpad default mappings only for positively identified Naga senders or exact original-Naga Bluetooth report endpoints. An unrelated keyboard is never translated. Unknown senders pass through in the default Naga mode.

## Implemented behavior

Profiles include button bindings, exact modifier combinations, side-button chords, separate discrete wheel axes. Legacy pointer-gain fields remain readable but are inactive. Naga product IDs `0x008f`, `0x0090`, and `0x0092` under vendor `0x1532` share `razer.naga.pro`; connection-specific state remains separate so one mouse cannot complete another mouse's chord. One profile set follows those transports. Device discovery enumerates metadata without opening/seizing HID devices or registering input report callbacks.

Mappings fire complete shortcut/click pairs on press. Chord prefixes defer their individual actions until resolved; an unmatched prefix replays its captured single action. Repeated downs cannot duplicate an action. A press retains its original mapping across profile switches and edits. Stop, tap disable, permission loss, manager conflict and device disappearance clear internal state; synthetic actions never leave a held key or button. Changing the selected device family stops active handling.

Default and per-app profiles are independent snapshots. Legacy v1 TailorMouse profiles migrate to v2; missing, corrupt and imported settings are validated and preserved in separate backups before replacement. All-mice mode is encoded explicitly as null and survives reload.

Discrete scroll ticks preserve fractional scaling, independently per axis. Continuous scrolling passes through. Pointer positions and relative mouse deltas remain native, including drags. There is no cursor warp or global cursor disassociation. The Cursor page separately reads and changes live hardware DPI (100–20000, independent X/Y backup) on exactly one original wired `1532:008f` Naga Pro with exactly one 90-byte control interface. Operations run on a serial background queue with shared HID access and no input callbacks. Changes occur only through Apply/Restore; UI appearance performs reads only. The app verifies response framing/CRC and GET readback, backs up before sending a write, and attempts verified recovery after any write/readback error. Writes target storage 0 only; firmware profile banks, stage tables and button functions remain untouched. Restore refuses a reconnected interface or a live DPI that changed since Apply. Backups stay private in Application Support/TailorMouse/Hardware Backups. Sensitivity applies mouse-wide, independent of remapping Start/Stop and application profiles. BLE/receiver DPI control and reconnect persistence are not claimed.

The explicit `scripts/naga-onboard-read.swift` diagnostic reads bounded vendor GET commands on one original wired Naga Pro control interface. The separate `scripts/naga-onboard-correction.swift --apply` diagnostic backs up and changes only normal-layer side-10/11 functions in the active profile and effective mirror; `--restore <backup.json>` restores saved function blocks after validating device location, active profile and slot scope. These tools are not invoked by the app, build, tests or installer. User device settings and results remain ignored.

The visual preview can be reproduced with `bash scripts/render-ui.sh`; outputs are `.local/ui/buttons.png`, `button-editor.png` and `side-buttons.png`. Main-window, shortcut-editor and side-button layouts were visually inspected at their compact sizes. The first installation preserved the profile file byte-for-byte and reopened with handling stopped. Subsequent changes through the new UI remain saved; the installer does not overwrite settings.

## Validation and remaining acceptance work

Repository `swift test` passes all 62 tests on this Mac. Coverage includes twelve Naga logical buttons in both default key banks, identity aliases, migration, configuration round trips, modifier fallback, matched down/up/drag across edits, repeats, chord snapshots, unmatched-prefix recovery, source isolation, reset, scrolling fractions, finite legacy speed limits, live-DPI packet validation, write bounds, backup-before-write ordering, no-op behavior, landed-write recovery and failed-recovery reporting. Diagnostic self-checks additionally validate read/write framing, reverse-order recovery after a simulated landed-write failure, no-op writes and private backup serialization without opening devices. Release packaging uses the host architecture and an ad hoc signature.

Metadata enumeration identified the attached Bluetooth Razer Naga Pro and its event-service candidates. This validates discovery only. UI and installation checks leave processing stopped; active physical-input checks are intentionally pending:

1. With TailorMouse permissions enabled and competing managers stopped by the user, verify ordinary buttons and side buttons 1–12 over Bluetooth, wired USB and receiver.
2. Confirm sender attribution on every transport, including separate USB keyboard interfaces and reconnects. Unknown or ambiguous attribution must pass through.
3. Verify app switching while holding a mapped button, modifier mappings, matched chord releases and incomplete chord recovery.
4. Verify wheel direction/speed, native pointer movement and slider dragging with handling stopped and Running. Apply two distinct USB DPI values, confirm a physical difference, and verify Restore. Confirm Stop restores button pass-through.
5. Confirm no duplicate actions, unexpected typing, permission-loss capture or resumed interception after tap disable.

Raw report decoding beyond original Naga Bluetooth keyboard report 6, automatic hardware initialization, button reports absent from macOS, acceleration curves, smooth-scroll synthesis, held-action dragging, SteerMouse-format import and complete target parity are not implemented. The original Bluetooth 10–12 and USB/dongle hardware issues are not claimed fixed.
