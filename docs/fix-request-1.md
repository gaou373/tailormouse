# Fix Request 1 — TailorMouse 0.2.8

Implemented from the user's private note and reference screenshots; no private note or reference artwork is committed.

| Request | Implementation |
| --- | --- |
| Wheel layout | Speed sliders above vertical Roll Up/Down or horizontal Left/Right action rows; independent direction, reverse and modifier bindings |
| Physical modifiers | Live ⌘ ⇧ ⌥ ⌃ highlighting, combined with manually selected modifiers; editors capture their destination mapping before recording keys |
| Cursor controls | Independent acceleration and sensitivity sliders, applied while Running, with no Apply button |
| Button identification | Hover the original mouse illustration and press a button to highlight its row, diagram location and page; temporary listeners are read-only and stop on leaving |
| Action categories | Click, Scroll, Keyboard Shortcut, System Control, Zoom, Mission Control, Music Control, Application Switcher, Cursor Snapping, Open, separator, No Action |

## Tracking evidence and limits

Observed on this Mac: the dynamically resolved `IOHIDEventSystemClientCreate` default client exposed effective resolution 90112000 and acceleration 52429. A separate, reversible runtime check accepted resolution 99123200 and acceleration 49152, read both back, then restored and verified the original values. Raw evidence remains ignored at `.local/evidence/native-pointer-default-write-restore-20261013.txt`.

Changing resolution requires reapplying acceleration to commit the tracking curve, including during recovery. The independently written transaction journals attempted writes, restores resolution before acceleration, and verifies recovery. This ordering was informed by maintained [LinearMouse PointerDevice code](https://github.com/linearmouse/linearmouse/blob/843d9a070cc64d56b07fc7f16d03b0f34ff33412/Modules/PointerKit/Sources/PointerKit/PointerDevice.swift), pinned to commit `843d9a070cc64d56b07fc7f16d03b0f34ff33412`.

The client constructor is macOS SPI, resolved at runtime; service property calls use SDK APIs. Unsupported services are excluded, and trackpads are excluded. Native event coordinates and deltas pass through untouched. Sensitivity scales the baseline resolution inversely (0.25–4×); acceleration is 0–5 in native fixed-point units. Parameters follow the active profile while Running. Stop/normal quit restore captured per-service values. Reconnect obtains a fresh baseline. Crash recovery and concurrent writes from another manager are not guaranteed. Accepted property readback establishes configuration, not physical comfort; physical acceptance remains user testing.

## Verification

75 unit tests cover legacy decoding, new-field round trips, exact category order, wheel routing and modifier fallback, unchanged native/continuous wheel events, paired action routing across edits/reset, independent tracking baselines, commit ordering, landed-write failures and failed recovery. Release packaging and six isolated UI renders pass. Wheel, Cursor, shortcut editor and side-button highlight layouts were visually inspected. Preview models disable all input monitors and never write user settings or runtime status.

Runtime acceptance: press Start yourself; check wheel assignments, held modifier highlighting, hover identification, modest sensitivity changes and Stop restoration. Settings backup and permission refresh occur separately after packaging; no build or test enables handling.

Installed build 10: executable SHA-256 `19d49f6cd7d96fdc6b625034bb53669a8e6d2f00e2d860ba680bcddf9879b477`. Strict signature verification passed. Only TailorMouse permission entries were removed/re-added through System Settings and verified enabled; the app reopened stopped. The final read-only inventory reported no Razer interfaces, so physical slider acceptance requires reconnecting the mouse.

## 0.2.9 reconnect and control correction

The user reported excessive movement and immovable sliders. Observed: the installed UI remained unsupported after Bluetooth reconnect, while a fresh native client read that mouse's tracking successfully. The profile had no acceleration/sensitivity override. Native acceleration remained 98304 (1.5) after Stop. A separately authorized runtime adjustment changed only the connected original Bluetooth Naga's acceleration to 32768 (0.5), preserved resolution, verified readback and retained a private backup. The user confirmed movement became manageable. This does not establish what originally set the higher acceleration.

The controller now obtains fresh service snapshots on inspection/update, polls while Cursor is visible, and displays the current baseline while stopped. Tracking has numeric fields and 0.05-step controls as well as sliders. Two added tests prove neutral Bluetooth profiles do not write tracking and sensitivity changes preserve independent acceleration; all 77 tests pass. A read-only check using the actual controller returned supported=true and baseline=0.5.

Hardware DPI is restored for the original wired Naga Pro. Its logarithmic slider applies once on release, numeric entry applies on Return, and presets apply directly. Private backup/readback/recovery and Restore previous DPI remain. No Apply button is required. DPI is mouse-wide and separate from Start/Stop tracking restoration; Bluetooth/receiver hardware DPI remains unsupported. Isolated previews explicitly disable hardware reads/writes. Physical DPI changes were not exercised as part of builds/tests.

Ignored evidence: `.local/evidence/pointer-too-fast-readonly.txt`, `pointer-comfort-fix.txt`, `pointer-reconnect-controller.txt`. These are native runtime observations, not new SteerMouse artifact findings.
