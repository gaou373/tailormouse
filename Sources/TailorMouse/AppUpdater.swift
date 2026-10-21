import AppKit
import Combine
import Sparkle
import SwiftUI
import TailorMouseCore

/// Sparkle owns download verification, replacement, recovery and relaunch.
/// Input handling is never started by this object, including after an update.
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var available = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var message = "Updates are unavailable in this development build."
    private var controller: SPUStandardUpdaterController?
    private var deferredInstall: Timer?
    private var stopHandling: () -> Void = {}
    private var started = false

    func start(stopHandling: @escaping () -> Void) {
        guard !started else { return }; started = true
        self.stopHandling = stopHandling
        let bundle = Bundle.main
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              UpdateConfiguration(feedURL: feed, publicKey: key) != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$available)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main).assign(to: &$automaticChecks)
        controller.startUpdater()
        message = "Updates are verified before installation. Reopening follows your automatic-start preference; profiles stay on this Mac."
    }
    func checkForUpdates() { controller?.checkForUpdates(nil) }
    func setAutomaticChecks(_ value: Bool) { controller?.updater.automaticallyChecksForUpdates = value }
    private var hasOpenEditor: Bool {
        NSApp.windows.contains { $0.title == "TailorMouse" && $0.attachedSheet != nil }
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if let reason = UpdateConfiguration.installationBlocker(bundleURL: Bundle.main.bundleURL, hasOpenEditor: hasOpenEditor) {
            throw NSError(domain: "dev.tailormouse.update", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
        }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { stopHandling() }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        stopHandling()
        guard hasOpenEditor else { return false }
        message = "Update ready. Finish the open editor with OK or Cancel to continue installation."
        deferredInstall?.invalidate()
        deferredInstall = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard !self.hasOpenEditor else { return }
            timer.invalidate(); self.deferredInstall = nil
            self.stopHandling(); installHandler()
        }
        return true
    }
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { stopHandling() }
    deinit { deferredInstall?.invalidate() }
}

struct AppUpdateControls: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Check for Updates…", action: updater.checkForUpdates).disabled(!updater.available)
            Toggle("Automatically check for updates", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
                .disabled(!updater.available)
            Text(updater.message).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct UpdateMenuItem: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates).disabled(!updater.available)
    }
}
