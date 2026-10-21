# Fix Request 2 — TailorMouse 0.3.0

Implemented from the user's private note and Stream Deck reference screenshots. The note and third-party artwork remain outside the repository.

The keyboard shortcut recorder now has an adjacent dropdown. Groups are Alphanumerics, Navigation, Numpad, F-Keys and Others. Choosing a key requires no physical keypress and preserves selected modifiers. Recording and Clear remain; the dropdown is disabled during active recording to prevent navigation keys from being captured as the new shortcut. All F1–F24 choices are included and displayed by name. The shared editor covers ordinary buttons, Naga side buttons, wheel actions and chords.

## Function-key representation

F1–F20 use native macOS virtual key codes. F21–F24 use AppKit's reserved characters U+F718–U+F71B, paired down/up events and the function flag. Their explicit optional profile field distinguishes them from any native key using the same placeholder code. Import rejects mismatched codes, out-of-range function numbers and invalid modifier bits; legacy shortcut JSON still decodes unchanged.

Observed primary facts: Apple's [USB-to-ADB mapping](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDFamily/Cosmo_USB2ADB.c) marks USB F21–F24 as `DEADKEY`. Apple's [AppKit function-key documentation](https://developer.apple.com/documentation/appkit/function-key-unicode-values) defines reserved characters usable in key events. A local non-posting CGEvent/NSEvent check preserved F21/F24 characters and modifier flags. Ignored source evidence is `.local/evidence/apple-usb2adb.c`; the event check is `.local/function-key-event-check.swift`.

Inference and limit: apps that recognize character-based AppKit hotkeys can receive these extended keys; software requiring native virtual key codes or raw HID keyboard reports may not. The editor exposes this limit when F21–F24 is selected. No driver, virtual HID keyboard, global key-map change or security expansion is installed. Universal receiving-app compatibility is unverified.

## Extra mouse buttons

The ordinary page starts with Left, Right and Middle. Additional rows appear only after an actual scoped mouse-button down is observed while Running or using the read-only hover inspector. Extra observed rows beyond the first eight are available in a detected-buttons menu; the old unconditional Button 4–32 list is removed. Naga side-button pages remain. A different device-family selection clears observed ordinary rows. Saved mappings for hidden buttons remain intact, and discovery never activates remapping.

## Verification

84 unit tests pass. New coverage verifies all 24 distinct function choices, native key-code mapping, extended characters, paired output/modifiers, legacy and extended profile round trips, invalid import/emission rejection, mapping snapshots/repeats/releases/reset, and observed-only button visibility. Release packaging and isolated editor/button layouts pass. Physical receiving-app hotkey behavior, especially F21–F24, remains acceptance testing after the user presses Start.

Installed build 12 executable SHA-256: `17b814b825513ab483cb25038d1cc0c434f862d387fbd79afe757d89da7ca783`. Strict signature verification passed. TailorMouse's existing Accessibility and Input Monitoring approvals were refreshed through native Settings and verified enabled. Native UI inspection confirmed three ordinary rows, all grouped menu choices and F24 selection. The temporary verification mapping was removed through Use Default Mapping; full saved configuration content then matched the private pre-install backup. The app remains stopped.
