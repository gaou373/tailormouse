# TailorMouse

Personal macOS mouse research project using [REA](https://github.com/morluto/rea) to reverse engineer the installed SteerMouse app. The current scope is understanding its architecture and implementation before fixing or customizing anything. The motivating requirements are Razer Naga Pro 12-button support and one profile shared across Bluetooth, wired and dongle connections.

The first confirmed issue was a conflicting Razer HID driver. It was disabled reversibly, and SteerMouse now reports the Bluetooth Naga as available. Physical button tests and cross-transport profile sharing are still pending. See the [investigation and evidence log](docs/research/README.md).

## Research

```sh
npm ci
npm run research
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/hid-inventory.swift
```

REA is pinned in `package-lock.json`. Raw analysis stays in `.local/evidence/` and is not uploaded. The repository contains independently written code and research notes, not SteerMouse binaries, assets or user settings.

## Original app starter

A disabled-by-default SwiftUI starter was created before the scope was clarified. It includes default/app-specific profiles, discrete wheel inversion/speed, side-button shortcut actions and explicit Start/Stop controls. It is **not a Naga Pro twelve-button fix** and is not activated. Further app development is deferred until reverse engineering is reviewed.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
npm run build:app
```

Build output: `.local/build/TailorMouse.app`. Builds and tests do not activate interception. The app refuses to enable while SteerMouse Manager runs. Its preferences live separately in Application Support/TailorMouse. Current input routing uses a session event tap and cannot attribute events to a specific physical mouse; Naga panel support needs device-specific HID handling first.
