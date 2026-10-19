# Physical DPI-button remapping: withdrawn pending verification

The implementation released in 0.4.3 and installed locally with 0.4.4 incorrectly identified the scroll-wheel slots as DPI buttons. The user confirmed that enabling it affected scrolling. The earlier capture of F13/F14 did not isolate physical DPI presses from wheel movement and was insufficient evidence. Claims that it verified the physical DPI buttons are withdrawn.

0.4.5 disables the opt-in, ignores saved opt-ins for input aliases, and removes the programming path. Existing profile actions are retained, but physical DPI remapping is unavailable until hardware verification is complete. The Cursor hardware-DPI slider is separate and unchanged.

## Observations and remaining question

The pinned [OpenSnek original Naga Pro slot table](https://github.com/gh123man/OpenSnek/blob/1af99c711035842e2896cd2d0b666b41dc022a1d/OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift) identifies slot 9 as Scroll Up, 10 as Scroll Down, 11 as DPI Down and 12 as DPI Up. Its writable-slot allowlist excludes 11 and 12. That exclusion does not establish that the firmware rejects all possible remapping methods; physical DPI remapping remains unanswered.

Read-only GET queries on the connected receiver returned normal-layer slot 11 block `0c010100000000` and slot 12 block `00000000000000`. Neither proves writable support or matched physical press/release reports. No writes to these slots were attempted. Native captures and diagnostic sources remain ignored under `.local/evidence/`; these are not SteerMouse REA findings.

## Legacy wheel recovery

The user's connected mouse was restored by Stop, and the old opt-in was unchecked. Recovery support remains for older installations interrupted while the incorrect feature was enabled. Reconnect the same mouse at the same USB location and onboard profile, stop handling, then choose **Buttons → DPI setup… → Restore Wheel Assignments**. The recovery journal contains the original blocks and is kept private in Application Support/TailorMouse/DPI Button Recovery.

Recovery checks product, location, available serial, active profile, packet scope and current ownership before writing the journaled originals. External changes are preserved and ambiguous records retained. The historical F13/F14 wheel targets are recognized only for ownership checks; new writes of those targets are rejected. No new lease can be created. Builds and tests never program the mouse or start handling.

Regression tests cover saved opt-ins on every connection, forbidden physical-slot/legacy-target writes, matched key input without false DPI dispatch, invalid journals, partial/idempotent restoration, external changes, and logical held-action cleanup.
