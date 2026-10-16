# Profile management and shared Cursor settings

Version 0.3.12 adds these commands to the profile **Edit** menu:

| Command | Result |
| --- | --- |
| Copy current profile… | Copies buttons, modifier mappings, wheel settings and chords to the chosen application; the source stays intact. |
| Transfer current profile… | Copies those settings to the destination, then resets the source’s mappings and wheel settings. The source application association remains. |
| Reset current profile… | Restores the selected profile’s factory mappings and wheel settings. |

Choose an existing application profile or select another `.app` to create one. The dialog identifies the source and destination and warns when destination settings will be replaced. Cancel makes no changes. Existing destination profile identity/name/application association are preserved. Copying/transferring to the same source is rejected. A confirmed change first saves a private backup under `~/Library/Application Support/TailorMouse/Profile Backups/`; these JSON files can be restored through Edit → Import profiles. A backup or save failure prevents the change from being applied.

Cursor acceleration and sensitivity are shared across all application profiles. The Cursor tab labels this **Speed · All Applications**. Profile selection and the active application affect button/wheel/chord mappings, while the tracking controller always reads the global values. Profile copy/transfer/reset leaves these values, the wired tracking reference, device calibration and hardware DPI intact. Reset Tracking Adjustments in Cursor explicitly resets the global adjustments. Hardware DPI continues to be a separate wired-device control.

Existing schema 1/2 files initialize the global values from Default, preserving its current tracking. Application-specific legacy tracking fields remain readable but are ignored by the controller. The first settings save preserves the original file before writing schema 3. Exports include the shared settings; older imports migrate in the same way.

Validation covers identity/payload preservation, new destinations, rejected operations without partial mutations, legacy migration, shared settings round trips, held shortcut releases and retained chord snapshots across reset/transfer. UI renders are isolated in memory and never save user settings. Installed UI verification uses Cancel; actual user profiles are not replaced as a test.
