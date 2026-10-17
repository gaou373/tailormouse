TailorMouse 0.4.0 adds in-app updates and a drag-to-Applications installer.

**Download `TailorMouse-0.4.0-universal.dmg` below.** It supports Apple Silicon and Intel Macs running macOS 13 or later. No GitHub account or developer tools are required.

1. Open the DMG and drag TailorMouse onto Applications.
2. Eject the image and open TailorMouse from Applications.
3. Approve TailorMouse in Accessibility and Input Monitoring, choose mappings, then press Start.

**Preview signing:** this build is ad hoc signed and is not Apple notarized. macOS may block its first launch. If you trust this download, review Apple's [trusted-app instructions](https://support.apple.com/102445). Future preview updates may require refreshing TailorMouse's two existing permission entries. No security settings are changed automatically.

Choose **TailorMouse → Check for Updates…** or open **Support** for future versions. Automatic checks are optional; installation needs your approval. The feed and update archive are signed with a separate Ed25519 update key. Updates preserve local profiles and reopen with handling stopped.

This release includes the existing Naga Pro side-button mappings, held/repeating shortcuts, button and scroll chords, profile Copy/Transfer/Reset, and shared cursor settings. Full side-panel support is currently verified for the original Naga Pro over USB cable, receiver and Bluetooth; other Naga models remain unverified.

Validation: 179 tests, universal compilation, strict nested code-signature verification, DMG checksum and read-only contents checks. Intel execution on physical hardware and a complete installed old-to-new update cycle are not claimed tested here. The download contains no publisher settings or account data.

For publishing another version, see [the distribution guide](https://github.com/gaou373/tailormouse/blob/feat/native-mouse-app/docs/distribution.md).
