# Bluetooth side-button recurrence — 2026-10-13

This is native runtime evidence and independent TailorMouse implementation work, not a new SteerMouse artifact analysis. SteerMouse target context remains configuration executable SHA-256 `8829a0c3544b76def71808b7ed09af2fd6049bf110a30bab52eaa5571e4dc9f5`, helper SHA-256 `b2070391939b6f3f5431cb3fc1c7d89040b5a667ab89917cb653c6f0aca1f30c`, REA Apple graph `ev_37a1afa6b9d037507715517d52a20e373b3a7416773d06f24e5f9a33ec11227b`. No new REA Evidence ID is claimed; no target binary, registration logic or preferences were modified.

## Observed

The user reported side buttons no longer detected. TailorMouse 0.2.6 was Running, its selected family was `razer.naga.pro`, ordinary Bluetooth mouse clicks appeared in activity, and no side-button transitions had appeared. No SteerMouse manager process was running. The active Karabiner profile still excluded all previously configured original-Naga wired, receiver and Bluetooth keyboard/pointing variants. These checks did not require modifying any settings or quitting other managers.

Metadata identified one original Naga Pro `1532:0092` Bluetooth Low Energy endpoint exposing keyboard report 6. A shared read-only HID callback received numbered-key press/release snapshots. The observed side-1 packet was `06 00 00 1e 00 00 00 00`, with a subsequent zero-key report on release. The concurrent session-head listen-only Quartz probe saw neither Naga-attributed keyboard events nor number-row/numpad-1 events from another sender. The requested initial side-1 test was followed by additional button input during the capture. Replaying the entire capture through the new decoder produced 22 matched down/up pairs spanning all twelve logical side buttons, including 10–12.

The Razer physical HID extension remained activated/disabled and its virtual extension remained enabled. The Naga endpoint was an IOHIDUserDevice with AppleUserHIDEventService descendants. Neither these facts nor the missing Quartz events establishes which component caused the missing keyboard translation. No driver, Karabiner configuration, hardware assignment or calibration was changed for this recurrence.

Ignored raw outputs: `.local/evidence/naga-recurrence-hid-20261013.json`, `naga-recurrence-tree-20261013.txt`, `naga-recurrence-quartz-20261013.txt`, `naga-recurrence-raw-20261013.txt`, `naga-recurrence-replay-20261013.txt`, `naga-recurrence-listener-check-20261013.txt`.

## Original implementation and verification

Version 0.2.7 adds a shared Bluetooth reader, scoped to original Naga vendor/product and Bluetooth transport, opened only by the explicit Start flow. It polls endpoint presence, detaches callbacks on Stop/removal, and sends report-6 number-row/numpad snapshot differences into the existing keyboard decoder and button router. It does not seize devices or write feature reports. When an initial input GET is supported, it primes the current snapshot so an already-held key does not become a new press. Otherwise the first valid observed edge is handled normally.

Repeated snapshots do not repeat actions; independent button holds release separately. Rollover/malformed reports preserve prior state until valid input arrives. Existing down-time profile/modifier snapshots govern matching releases. The exact raw endpoint can supply metadata before the catalog's next refresh. When raw ownership is active, positively identified native Quartz copies of supported layout keys are suppressed to avoid duplicate actions/Passthrough output. Unknown keyboard senders and unrelated keyboard input remain untouched. Generated output retains the existing tag. Stop/removal clears state and attempts matching ups for raw Passthrough keys still posted; that cleanup is idempotent.

All 62 Swift tests pass, including nine added report/route/recovery cases. The capture replay performs no event posting. A separate read-only listener smoke check exercises shared attachment and teardown without starting remapping. Actual mapped actions, held-state display, permission recovery and reconnect behavior in the installed build require user acceptance. The reader currently covers the original numbered key banks and supported macro suffixes, not arbitrary firmware keyboard usages or every possible Bluetooth report format.


Installed 0.2.7 build 9 passed strict code-signature verification and reopened with handling stopped. Executable SHA-256: `4a469493c89bf776e225544f048326708667794c9fd0374568157e2044aa31d8`. Saved profile JSON content was unchanged. The latest-only runtime snapshot now includes `bluetoothRawEndpointCount`, without recording ordinary keyboard history. User Start and physical action verification remain pending.
