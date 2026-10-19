Reduce input-loop stalls that could make Blender viewport navigation and other mouse-heavy apps lag while TailorMouse is Running. Periodic HID discovery and tracking reconciliation now run off the input run loop, and motion/drags use a lightweight path that preserves original deltas and press ownership.

- Coalesce tracking edits and UI/diagnostic updates; preserve matched holds and Stop restoration.
- Retain keyboard modifier mappings and repeated chords. The DPI-button feature was later withdrawn in 0.4.5 after the user identified that it affected scrolling.
- Preserve saved profiles, shared sensitivity values and existing Start/Stop behavior.

Validation: 221 core tests and four fake-backend native worker checks pass. The user confirmed Blender navigation is smooth with TailorMouse Running after installing this build.

Preview build: ad hoc signed, not Apple notarized. macOS may require refreshing TailorMouse's existing Accessibility and Input Monitoring entries after installation.
