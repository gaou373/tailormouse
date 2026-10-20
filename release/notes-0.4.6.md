Add Naga V2 HyperSpeed receiver support from PR #2, including the held-modifier bridge for shortcut listeners. Follow-up fixes isolate hardware calibration by model and recover per-interface holds on disconnect, including baseline-only endpoints.

Mouse handling now starts automatically once when TailorMouse opens. Support has an option to disable this. Stop remains effective until Start or a fresh launch; missing permissions or a competing mouse manager keep handling stopped. No login item is added.

Add opt-in physical DPI Up/Down mappings for the original Naga Pro over USB cable or receiver. The implementation uses actual DPI slots 11/12, leaving wheel slots 9/10 untouched except for recovery of old private journals. Live writes are backed up and verified, and Stop/Quit restores original assignments. Existing old opt-ins do not enable the new feature; turn it on under Buttons while stopped. Bluetooth and HyperSpeed DPI-button remapping are outside this release’s supported scope. Hardware write/readback and restoration were verified on the connected receiver; physical button hold acceptance remains pending.

Validation: 239 core tests, four native tracking-worker checks and four unposted-event keyboard bridge checks pass. Builds and tests do not activate handling or program hardware. The separate bounded runtime DPI trial restored its original assignments.

Ad hoc signed preview, not Apple notarized. macOS may require refreshing TailorMouse’s existing Accessibility and Input Monitoring entries after an update.
