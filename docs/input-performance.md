# Input-loop responsiveness

Version 0.4.4 addresses the reported Blender viewport lag while TailorMouse is Running. The changes apply to all application profiles, with no Blender-specific sensitivity or mapping override.

## Findings

The user supplied two short viewport-orbit recordings and reported that stopping TailorMouse made interaction smooth. The installed app was still 0.4.2/build 28. A read-only four-second native process sample found the main thread in device-catalog enumeration, native tracking service/property reads, Naga discovery, repeated competing-app process enumeration and SwiftUI layout. These periodic operations shared the run loop that receives the event tap and raw HID callbacks. The source also resolved device/profile/modifier state for every movement/drag before returning an unchanged event. These are observed blocking mechanisms and unnecessary work; the sample and recordings do not prove a single exclusive cause or establish a Blender FPS measurement.

Native evidence stays ignored in `.local/evidence/blender-lag-20261019/`. The original sample has SHA-256 `bb61a5e9a3b0477898615daee71104d0862ca07afd17bb6b7fc42b4688e1c334`. No new SteerMouse analysis was performed.

## Changes

- Pure motion returns its original event immediately, adding only an actively held virtual modifier when needed. Positions, relative deltas and timestamps are untouched. Drags consult the original press's suppression decision without fetching a profile, hardware flags or foreground application. A pending calibrated mouse prefix is flushed first, preserving click-before-drag order.
- Native tracking reconciliation runs on a serial worker with immutable configuration snapshots. Slider edits coalesce to the latest value; identical observable values are not republished. Stop drains in-flight work and restores before returning. Generation/work IDs discard stale completions, including Stop followed immediately by Start. Tracking target calculations, wired reference and per-connection restoration remain unchanged.
- Periodic device and keyboard-interface discovery run on worker queues, with autorelease pools and unchanged-snapshot suppression. Endpoint identity is cached for raw reports. Explicit Start/Record may wait once for initial attribution; periodic checks stay off the input loop. Late discovery results cannot reopen interfaces after Stop. Raw-reader attachment transfers release ownership for keys already held by the native decoder, while still ignoring unowned keys held before Start.
- Competing mouse-manager detection uses application lifecycle notifications instead of a process-list walk each second. Initial conflict checks and stop-on-conflict remain.
- Repeated identical raw reports return before foreground-profile lookup. Unchanged modifier snapshots no longer republish UI state. Runtime diagnostic writes coalesce and serialize on a utility queue, with a final drain on normal termination. Profiles continue to save through their existing path.

## Validation and limits

221 core tests pass, including native/held drag ownership, chord release/reset, device attribution changes and raw-reader ownership handoff. Four checks exercise the actual tracking scheduler with a fake backend: a landed write followed by synchronous Stop/restoration; latest-edit coalescing; failure/Stop/restart generation handling; and elimination of duplicate Cursor inspections while tracking is active. These tests open no devices, request no permissions and activate no handling.

An isolated in-memory native callback check verifies unchanged motion coordinates/deltas, held modifier composition, mapped drag suppression and matched release without posting events. A 3,000-event synthetic pass-through microbenchmark measured mean move/drag callback costs around 1.65/1.12 microseconds before and 0.047/0.221 microseconds after. This is a callback lower-bound measurement in universal-device mode, not an end-to-end Blender benchmark; removal of periodic main-thread blocking is separate from those microsecond costs.

The universal app builds and installs with profiles preserved byte-for-byte. Both existing permissions were refreshed through native System Settings after user authentication, and the app reopened stopped. The user then pressed Start and confirmed Blender orbit/pan/zoom was “Smooth now.” No build, test, render or benchmark enables input handling or changes hardware tracking. This is qualitative physical acceptance on this Mac, not a measured FPS claim. The installed 0.4.4/build 30 executable has SHA-256 `03bd4ef97e256abe92a6df2ea4f8d8eb9b753334fbbc3b1cf765007707906609`. Handling was left in the Running state selected by the user.


0.4.5 retains this performance correction while withdrawing the incorrect wheel-based DPI remapping. The final suite passes 219 core tests and four native worker checks, with 18 isolated UI renders. The installed 0.4.5/build 31 executable has SHA-256 `e389540a2369b6a62e3d0431cffa5f4c6a1dbff11a044d8b5ce16a44f9699dd9`. Both existing permissions were refreshed through native System Settings and verified enabled; the app reopened stopped. Read-only GET checks confirm wheel slots 9/10 again contain their original Scroll Up/Down blocks. No pending legacy recovery journals remain on this Mac. Physical DPI-button remapping remains unverified and disabled.
