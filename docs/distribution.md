# Sharing TailorMouse and publishing updates

TailorMouse 0.4.0 adds Sparkle 2.9.6 (pinned in `Package.resolved`) and a universal DMG for macOS 13+. Recipients do not need Git, Node, Xcode, or a GitHub account. The public download is:

https://github.com/gaou373/tailormouse/releases/download/v0.4.6/TailorMouse-0.4.6-universal.dmg

Open the DMG, drag TailorMouse onto Applications, eject it, then open the installed app and approve Accessibility/Input Monitoring. Handling starts automatically after permission approval when the app opens; Support can disable this. Original Naga Pro support spans its three connections, and HyperSpeed receiver support has initial contributor acceptance. The image includes installation instructions, actual signing status, the application, and an Applications symlink. User settings, calibration, diagnostics, publisher credentials and research artifacts are not packaged.

## Preview signing versus Apple distribution signing

This first shared build is **ad hoc signed and not Apple notarized**. The user chose a preview because no Developer ID identity is available on this Mac. Gatekeeper may block its first launch; Apple documents the user's trusted-app review process at https://support.apple.com/102445. Ad hoc app updates can also require refreshing TailorMouse's existing Accessibility/Input Monitoring entries. The updater cannot grant these permissions for a recipient.

Sparkle update signing is independent: the archive and appcast have Ed25519 signatures, and the bundled public key verifies them. The private key lives only in the publisher's login Keychain, under account `dev.tailormouse.updates`; only its public key is committed in `release/update-config.json`. Back up that Keychain securely. Do not rotate/remove this key casually: the app refuses unsigned feeds and does not fall back after signature failures. Never put private keys or GitHub tokens in the app, repository, feed or release files.

For a future Apple-signed release, configure an existing Developer ID identity as `TAILORMOUSE_SIGNING_IDENTITY` and a previously stored notarytool Keychain profile as `TAILORMOUSE_NOTARY_PROFILE`. The packaging script signs nested Sparkle code inside out, submits the DMG, waits for acceptance, staples and validates it. That path is provided but is not verified here without a Developer ID/account. It never accepts account passwords on command lines or creates certificates automatically.

## Recipient update behavior

Choose **TailorMouse → Check for Updates…**, or use **Support**. Automatic checking is opt-in and can be toggled in Support. Silent/automatic installation is disabled; the recipient chooses Install. The stable HTTPS appcast URL is embedded in the bundle and points at the latest GitHub release asset `appcast.xml`. Sparkle validates the signed feed and downloaded archive before extraction/replacement. System profiling and release-note JavaScript remain disabled.

Checks are blocked when running directly from the usual mounted image or App Translocation, and while the main window has an editor sheet open. If an editor opens after an update check, installation waits until that editor is finished; handling stops before installation/relaunch. Sparkle owns replacement and recovery, and the relaunched app honors the automatic-start preference. Automatic start defaults on and can be disabled in Support. The update contains no profiles, so local configuration stays separate in Application Support.

## Preparing the next release

1. Increase the package/Info.plist version and the monotonically increasing `CFBundleVersion` in `scripts/build-app.sh`. Keep the bundle ID and signing public key unchanged.
2. Run `npm test` and `npm run release:prepare` on the publisher Mac. Keychain may ask permission for Sparkle's `sign_update` tool. The default creates an Apple Silicon + Intel build, verifies nested code, builds/verifies the DMG, signs/verifies the archive and feed, and writes checksums. Output goes to ignored `.local/releases/<version>/`. Nothing uploads automatically.
3. Review the image, release notes and signing status. Commit/push the corresponding source, tag that commit as `v<version>`, and publish a GitHub release with the DMG, `appcast.xml` and `SHA256SUMS.txt` as assets. Select it as the latest release. A prerelease excluded from GitHub's latest URL will not reach this stable channel.
4. Fetch the public assets without authentication and verify their hashes and signatures. Confirm an installed app can check the live feed. Do not modify signed XML or DMG bytes after signing; regenerate signatures/checksums if either changes.

The DMG file name includes the version. For future versions, share the release page or the version's direct link, rather than a version-specific link. A release must include its full appcast and archive together. Keep old versioned assets available for clients that already fetched an older feed.

## Verification scope

179 core tests pass, including HTTPS/key validation, open-editor protection and common disk-image/translocation paths. Both architectures build with a macOS 13 minimum; the packaged app embeds Sparkle with a bundle-relative runpath and passes recursive strict code-signature checks. The DMG checksum verifies, and read-only mounting confirms the expected files and Applications symlink. Isolated UI rendering never starts the updater or input handling. Physical hardware support on a friend's Mac and the future Developer ID/notarization path are separate acceptance checks.

Public release verification on 2026-10-17: the repository was made public under the user's explicit instruction and `v0.4.0` was published as the latest release. Unauthenticated downloads of the feed and DMG match the local SHA-256 values. Independent CryptoKit verification with only the committed public key accepts both signatures and rejects single-byte changes to both payloads. An isolated Sparkle probe (no AppModel, input capture or settings access) with build 25 loaded the live signed feed and found 0.4.0/build 26. The current user-installed app was not replaced or restarted. DMG SHA-256: `38038eec2f272caa8c17048c9b7dcd5ed7a9d8d7704d054b8a788bbe1a885cb8`.

Version 0.4.1/build 27 is now the latest public release and fixes held keyboard modifier inheritance. The same signature/public-download checks pass; an isolated Sparkle build-26 probe finds the signed build-27 update. The local app was updated from 0.3.13 without changing profile bytes; both existing permissions were refreshed and the app reopened stopped. The complete old-to-new Sparkle installation cycle is still not claimed tested.
