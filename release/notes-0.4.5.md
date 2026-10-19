Fix incorrect DPI-button remapping that affected Scroll Up and Scroll Down. The previous implementation used wheel slots; physical DPI remapping is now disabled pending hardware verification. Saved mappings are preserved, and old wheel recovery remains available under Buttons → DPI setup… → Restore Wheel Assignments while stopped.

Includes the Blender navigation performance correction tested locally in 0.4.4: periodic HID discovery and tracking reconciliation run off the input loop, with lightweight motion/drag handling and coalesced updates. The user confirmed smooth Blender navigation.

Preserves shared tracking, modifier mappings, held shortcuts, repeated chords and explicit Start/Stop. Hardware DPI adjustment in Cursor remains available.

Validation: 219 core tests, four native tracking-worker checks and 18 isolated UI renders pass.

Preview build: ad hoc signed, not Apple notarized. macOS may require refreshing TailorMouse’s existing Accessibility and Input Monitoring entries after installation.
