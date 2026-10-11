# TailorMouse

An independently written macOS mouse customization app, informed by an evidence-based investigation of [SteerMouse](docs/research/README.md) using [REA](https://github.com/morluto/rea). TailorMouse has its own Swift source, interface, icon and JSON profiles. It contains no SteerMouse executable, assets, registration logic or imported preferences.

## Features

- Default and application-specific profiles, with import/export.
- Twelve Naga Pro side-button slots, ordinary mouse buttons and modifier-specific mappings.
- Preset actions, recorded keyboard shortcuts, mouse clicks and scroll actions.
- Side-button chords with paired press/release routing and recovery.
- Separate horizontal/vertical wheel speed and direction controls.
- Pointer-speed scaling and device discovery.
- One Naga Pro family across Bluetooth, wired USB and the wireless receiver.
- Explicit Start/Stop and a menu-bar Stop control. Input handling starts stopped.

This is an initial functional recreation of common controls, not full SteerMouse parity. Physical Naga buttons still require testing on every transport. The current processor handles events macOS exposes; it cannot recover buttons whose reports never become events or initialize vendor-specific firmware. Pointer scaling operates above macOS tracking rather than replacing its acceleration curve. See [implementation and validation](docs/implementation.md).

## Build and install

Requires macOS 13+, Swift and Xcode command-line tools. Scripts prefer full Xcode when available.

```sh
npm ci
npm test
npm run build:app
npm run install:app
```

Build output: `.local/build/TailorMouse.app`. Installation copies an ad hoc signed local build to `/Applications/TailorMouse.app` and backs up an existing copy locally. Quit TailorMouse before installing an update.

Open TailorMouse, configure mappings, then press **Start** when ready. Active handling requires Accessibility and Input Monitoring permission. The app checks permissions and refuses to start while SteerMouse Manager runs; it never quits that manager. Builds, tests and installation do not enable handling, grant permissions or add login items.

Settings live separately at `~/Library/Application Support/TailorMouse/profiles.json`. Application profiles initially copy the default profile, then keep their own settings. Import replaces TailorMouse profiles after backing up the previous file; it does not import SteerMouse formats.

## Research

```sh
npm run research
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/hid-inventory.swift
```

`rea-agents` is pinned to 6.4.0. Raw evidence stays in ignored `.local/evidence/`. Research notes distinguish static observations, inferred behavior and unanswered hardware questions. No proprietary binaries, user settings, account data or decompiler databases are uploaded.
