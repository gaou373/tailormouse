import Foundation

/// Only public release metadata belongs in the bundle. Private signing keys
/// stay in the publisher's Keychain and are never needed by recipients.
public struct UpdateConfiguration: Equatable {
    public let feedURL: URL
    public let publicKey: String
    public init?(feedURL: String, publicKey: String) {
        guard let url = URL(string: feedURL), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, Data(base64Encoded: publicKey)?.count == 32 else { return nil }
        self.feedURL = url; self.publicKey = publicKey
    }
    public static func installationBlocker(bundleURL: URL, hasOpenEditor: Bool) -> String? {
        if bundleURL.pathExtension != "app" || bundleURL.path.hasPrefix("/Volumes/") || bundleURL.path.contains("/AppTranslocation/") {
            return "Drag TailorMouse into Applications, eject the disk image, and open the installed copy before checking for updates."
        }
        if hasOpenEditor { return "Finish the open editor with OK or Cancel before checking for updates." }
        return nil
    }
}
