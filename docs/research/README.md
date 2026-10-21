# SteerMouse / Naga Pro investigation

The initial milestone investigated SteerMouse before fixes or customization. The user subsequently requested an original recreation and installation on 2026-10-11. TailorMouse implements common customization controls; [implementation details and limits](../implementation.md) distinguish its behavior from the target. These research findings remain static evidence, rather than proof of hardware compatibility.

Target: installed SteerMouse 5.8(0920), `/Applications/SteerMouse.app`. REA npm package is pinned to 6.4.0. The supplied upstream repository was inspected at commit `3ad5782dfdc8864879a887dc63fef682ffeb5839`.

## Evidence and findings

- [Recovered architecture map](architecture.md): component diagram, question coverage and REA native evidence.
- [Input pipeline](input-pipeline.md): HID adapters, event routing and action matching.
- [Profile architecture](profile-architecture.md): identity normalization, application lookup and persistence.
- [UI-to-code map](ui-architecture.md): compiled control connections and matching native implementations.
- [Static binary findings](static-findings.md): target hashes, methods, imported input APIs, Core Data schema and bounded assembly observations.
- [Naga diagnosis](naga-pro.md): transport identity, driver conflict and profile investigation.
- [Wired runtime findings](wired-runtime.md): Karabiner attribution conflict, composite interfaces, and captured side-button assignments.
- [Bluetooth runtime findings](bluetooth-runtime.md): side-button HID reports present without Quartz keyboard events, and the original raw-report path.
- Raw REA records and native-tool captures are local, ignored files under `.local/evidence/`.

REA inventory observed 175 occurrences and 153 distinct content nodes. The Apple graph recognized the main app and nested login-item manager, with complete coverage within the supplied inventory. The UI decoder read five compiled nib documents (3,783 graph nodes, 2,899 edges). This describes packaged connections; it does not prove runtime button behavior.

| Operation | Evidence ID |
| --- | --- |
| Artifact inspection | `ev_fb3796420edd63980209c029cbb5371edc1ab541acb1ea17a97053c761015eb8` |
| Artifact inventory | `ev_2dde61a09d55ffe8ae6789bce1236c0bd57b300d09a30f6954c2252e03c233cd` |
| Apple application graph | `ev_37a1afa6b9d037507715517d52a20e373b3a7416773d06f24e5f9a33ec11227b` |
| Dylib resolution | `ev_73c1bb85d41d8cc641755005fe9f32d9f2b0f66873f500683da93da33bd4544a` |
| Interface Builder decoding | `ev_b67425e6ce1700aa3d666cbca72bbd1e0bc65128033196775eb24c11fab83eb5` |

Native REA commands initially returned `execution_failure` with `file` / `io`. Selecting the installed full Xcode toolchain using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` resolved the failure; Mach-O, plist and signature inspection now succeed. The reproduction script selects that toolchain when present. macOS `file`, `nm`, `otool`, and plist tools independently supplied focused assembly observations, labeled native-tool evidence rather than REA Evidence. No deep provider is configured: Hopper is absent, Ghidra is unconfigured, and IDA is unconfigured. Original source and decompiler pseudocode have not been recovered.

## Reproduce

```sh
npm ci
npm run research -- /Applications/SteerMouse.app
node scripts/capture-static.mjs
node scripts/ui-map.mjs
python3 scripts/research-profile-constants.py > .local/evidence/static/profile-constants.json
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/hid-inventory.swift > .local/evidence/hid-current.json
```

`research` inventories the bundle, projects its Apple graph, traces library loads and decodes UI resources. It runs no target application code. The HID inventory reports metadata and element descriptors without opening or seizing devices or observing key presses. Capture each transport separately; static descriptors alone cannot establish which reports a physical button emits.

## Unanswered

1. Do Bluetooth side buttons 10–12 now work after disabling the conflicting Razer HID driver?
2. Do all twelve buttons work over USB/dongle with that conflict removed?
3. Which actual HID reports correspond to each side button on each transport?
4. Can a supported user device-definition alias unify existing profiles without losing mappings?

Do not mark these answered until user tests and exact-device observations corroborate them.
