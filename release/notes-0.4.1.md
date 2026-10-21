TailorMouse 0.4.1 fixes held keyboard modifiers being dropped from mapped shortcuts, including Command + a Backspace chord in Finder.

When a base button, chord or wheel shortcut has no matching modifier-specific override, held keyboard modifiers now combine with its configured shortcut. A modifier-specific assignment consumes its selector keys, preserving mappings such as Option + Side Button 2 → O. Configured output modifiers are preserved, and repeated/held output keeps matched press/release snapshots.

All 187 tests pass, including eight new regression cases. The previous routing reproduction sent Backspace with no Command flag; it now produces matched Command + Backspace edges. Physical Finder acceptance is separate from these tests. No profile migration or automatic input activation is required.

[Download the universal DMG](https://github.com/gaou373/tailormouse/releases/download/v0.4.1/TailorMouse-0.4.1-universal.dmg) for macOS 13+, Apple Silicon and Intel. Existing 0.4.0 users can choose **TailorMouse → Check for Updates…**. Version 0.3.13 and earlier require the DMG because they predate the updater.

This remains an ad hoc signed preview without Apple notarization. macOS may require a first-launch review and a refresh of TailorMouse's existing Accessibility/Input Monitoring entries. Updates preserve local profiles and reopen stopped.
