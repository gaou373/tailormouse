# TailorMouse

An independently written macOS mouse customization app, informed by an evidence-based investigation of [SteerMouse](docs/research/README.md) using [REA](https://github.com/morluto/rea). TailorMouse has its own Swift source, interface, icon and JSON profiles. It contains no SteerMouse executable, assets, registration logic or imported preferences.

## Download for a friend

[Download TailorMouse 0.4.5 for Apple Silicon and Intel Macs](https://github.com/gaou373/tailormouse/releases/download/v0.4.5/TailorMouse-0.4.5-universal.dmg) · Requires macOS 13 or later.

Open the DMG, drag TailorMouse into Applications, eject the image, then open the app. Approve Accessibility and Input Monitoring and press Start when ready. **This preview is not Apple notarized**, so macOS may require a trusted-app review at first launch. Choose **TailorMouse → Check for Updates…** for future releases; no GitHub account or developer tools are needed. [Installation, signing and update details](docs/distribution.md).

## Features

- Compact tabbed window with profile/device menus and a separate button editor.
- Default and application-specific profiles, with import/export.
- Twelve Naga Pro side-button slots, ordinary mouse buttons and modifier-specific mappings.
- Preset actions, recorded or dropdown-selected keyboard shortcuts (F1–F24), mouse clicks and scroll actions.
- Mouse-button chords with clear click names, per-button recording, paired routing and recovery.
- Separate horizontal/vertical wheel speed and direction controls.
- Live native acceleration and sensitivity sliders with numeric controls, with original tracking restored on Stop.
- Wired Naga Pro hardware DPI slider with verified writes, backups and Restore.
- Recovery for older wheel assignments; physical DPI-button remapping is disabled pending hardware verification.
- Ordered action categories, roll-direction assignments and physical modifier highlighting.
- Read-only button identification while hovering over the mouse illustration.
- Device discovery.
- One Naga Pro family across Bluetooth, wired USB and the wireless receiver.
- One device row per physical connection, with transport calibration for custom onboard keys.
- Persistent last-side-button press and release indicators.
- Explicit Start/Stop and a menu-bar Stop control. Input handling starts stopped.

This is an initial functional recreation of common controls, not full SteerMouse parity. Physical Naga buttons still require testing on every transport. Ordinary buttons and USB/receiver keyboard input use Quartz events. While Running, the original Bluetooth Naga also has a scoped raw reader for its numbered side-button reports, covering a connection that provides HID input without Quartz keyboard events. Missing/unknown report formats and vendor firmware initialization remain outside the implementation. Cursor tracking uses native macOS HID service parameters for supported mice; trackpads are excluded. See [implementation and validation](docs/implementation.md).

## Build and install

Requires macOS 13+, Swift and Xcode command-line tools. Scripts prefer full Xcode when available.

```sh
npm ci
npm test
npm run build:app
npm run install:app
```

Build output: `.local/build/TailorMouse.app`. Installation copies an ad hoc signed local build to `/Applications/TailorMouse.app` and backs up an existing copy locally. Quit TailorMouse before installing an update.

Ad hoc signing identifies the exact build: macOS can retain an enabled-looking permission entry that no longer matches after an update. Remove that stale TailorMouse entry, add the installed copy in Accessibility and Input Monitoring, then quit and reopen. The user authorized the assistant to handle this native Settings refresh after future installations; this remains a separate runtime step rather than a build/test action. User authentication or unavailable native UI may still require a handoff. A targeted `tccutil reset Accessibility dev.tailormouse.app` / `tccutil reset ListenEvent dev.tailormouse.app` clears only this app's prior approvals; approval must then be renewed in Settings. Builds/installers never run these resets automatically. For a reusable certificate already configured in Keychain, set `TAILORMOUSE_SIGNING_IDENTITY` when building; no certificate or key is uploaded.

In **Chords**, choose **Scroll → Scroll Up / Down / Left / Right** as an input alongside a mouse button. Hold the button and scroll to repeat the action; **Record** can capture a direction too. See [scroll chords](docs/chord-recording.md#0313-scroll-inputs).

Choose **Default** or an application in the top profile menu; **Edit** adds/removes application profiles and imports/exports settings. In **Buttons**, click an assignment to open its editor. **OK** saves; **Cancel** leaves the mapping unchanged. The page dots select ordinary buttons, side buttons 1–6 and side buttons 7–12. Only physically observed extra buttons appear; hidden saved mappings are preserved. The shortcut editor's dropdown chooses keys without pressing them, including F1–F24. F21–F24 require receiving-app support for AppKit function characters; see [Fix Request 2](docs/fix-request-2.md). The modifier strip selects mappings for keys held while clicking. Configure mappings, then press **Start** when ready. Active handling requires Accessibility and Input Monitoring permission. The app checks permissions and refuses to start while SteerMouse Manager runs; it never quits that manager. Builds, tests and installation do not enable handling, grant permissions or add login items.

Unassigned Naga side buttons use **No action** while running, preventing unintended typing and alert sounds. Explicit **Passthrough** forwards their native keys. If ordinary clicks appear in activity but the side panel does not, exclude the Naga in Karabiner-Elements → Devices; its virtual keyboard can hide the physical sender. See the [wired diagnosis](docs/research/wired-runtime.md) and [Bluetooth report investigation](docs/research/bluetooth-runtime.md).

Settings live separately at `~/Library/Application Support/TailorMouse/profiles.json`. Application profiles initially copy the default profile, then keep their own settings. Import replaces TailorMouse profiles after backing up the previous file; it does not import SteerMouse formats.

Transport calibration is stored separately from action profiles in `nagaKeyboardLayouts`. It supports individual key overrides, captured two-key onboard sequences, and their calibrated double-click prefixes. Prefix recognition delays ordinary left clicks on that calibrated Naga connection by up to 12 ms; unmatched clicks replay normally. The Device tab can restore the standard layout after the mouse itself emits standard single-key assignments. That control changes TailorMouse calibration only; it does not reprogram onboard mouse profiles. A local `runtime-status.json` snapshot provides status and aggregate Naga transition counts without recording ordinary keyboard input.

Version 0.2.8 implements [Fix Request 1](docs/fix-request-1.md). Wheel speed sits above Roll Up/Down assignments (or Left/Right). Hold ⌘, ⇧, ⌥ or ⌃ to highlight the modifier strip and select that mapping. Hover over the mouse illustration and press a mouse button to identify its row without activating remapping. The editor groups commands into Click, Scroll, Keyboard Shortcut, System Control, Zoom, Mission Control, Music Control, Application Switcher, Cursor Snapping, Open and No Action.

Cursor has live Acceleration and Sensitivity sliders plus numeric fields and step controls; there is no Apply button. Version 0.2.9 refreshes native service snapshots after reconnect. The wired Naga DPI slider applies on release; enter a DPI and press Return or choose a preset. Read/Restore retain verified hardware backup and recovery. Hardware DPI is mouse-wide, independent of Start/Stop, and unavailable over Bluetooth/receiver. Settings take effect while Running and follow the active application profile. Sensitivity is a relative 0.25–4× multiplier on tracking captured at Start. Stop and normal quit restore those native parameters. Native pointer events are never rescaled or warped by the tracking engine. The backend requires a dynamically resolved macOS SPI; unsupported services stay disabled. Abrupt termination and another mouse manager changing the same parameters are limitations. Legacy `pointerSpeed` remains readable but inactive.

The original wired Naga Pro has separate explicit [onboard diagnostics](docs/research/wired-runtime.md): a read-only inspector and a bounded side-10/11 correction with private backups, readback and recovery. Neither runs automatically during builds or installation. This unit now reads back single-key `0`/`-` assignments; physical hold and reconnect verification are still pending.

Version 0.2.7 reads original Naga Pro Bluetooth keyboard report 6 directly while Running. Repeated snapshots are filtered, held keys retain their matching releases, and the existing shared profiles still choose actions. Recognized native Quartz copies are consumed when the raw reader owns that endpoint; generated Passthrough events are tagged so they are not handled again. Stop/disconnect attempts a release for every synthetic Passthrough key still held. The reader uses shared access and stops with handling; it never changes mouse firmware, keyboard rules or pointer movement.

Physical **DPI Up** and **DPI Down** remapping is disabled in 0.4.5: the earlier implementation incorrectly addressed the scroll wheel. Saved actions are retained, and legacy wheel restoration remains available; see [verification and recovery details](docs/dpi-buttons.md). The Cursor hardware-DPI slider and presets remain separate.

## Research

```sh
npm run research
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/hid-inventory.swift
```

`rea-agents` is pinned to 6.4.0. Raw evidence stays in ignored `.local/evidence/`. Research notes distinguish static observations, inferred behavior and unanswered hardware questions. No proprietary binaries, user settings, account data or decompiler databases are uploaded.

In **Chords**, click a gray function row to open its editor. Expand **Chord buttons & note** to choose Left/Right/Middle Click, use the Side buttons submenu, add a note, or use **Record** beside First or Second. Recording stops handling; press Start to resume afterward. Escape or Cancel abandons the capture. The table's + button adds a chord; OK commits editor changes and Cancel discards them. See [recording behavior and validation](docs/chord-recording.md).

## Naga V2 HyperSpeed preview

The `0.4.6-hyperspeed.1` preview adds device selection and side-button reading for the Naga V2 HyperSpeed USB receiver (`1532:00b4`). Choose that mouse in the mouse menu before pressing Start. Physical button verification is pending; see [scope, evidence and testing steps](docs/naga-v2-hyperspeed.md).
