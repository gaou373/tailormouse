Replace the internal DPI-button signals with F19/F20 to avoid macOS F14 brightness shortcuts. Preserve the corrected physical directions, saved DPI actions and profile settings. Older temporary assignments restore using their versioned recovery backups before the new signals are installed.

Validation: 247 core tests and 8 native checks pass, covering matched holds/releases, repeated HID snapshots, disconnect recovery and prior journal versions. Receiver originals were restored and read back; reconnecting the receiver cleared the reported lingering brightness repetition. Physical direction/hold acceptance on this build remains a user check.

Ad hoc signed preview, not Apple notarized.
