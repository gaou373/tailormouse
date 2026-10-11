import AppKit
import Combine
import TailorMouseCore
import UniformTypeIdentifiers

final class AppModel: ObservableObject {
    @Published var configuration = ProfileConfiguration()
    @Published var selectedID = UUID()
    @Published private(set) var isRunning = false
    @Published var status = "Stopped. Configure your profiles, then press Start."
    private let interceptor = MouseInterceptor()
    private let settingsURL: URL
    private var saveSubscription: AnyCancellable?
    private var terminationObserver: NSObjectProtocol?
    private var hasEdits = false

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TailorMouse", isDirectory: true)
        settingsURL = directory.appendingPathComponent("profiles.json")
        selectedID = configuration.defaultProfile.id
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do {
                let loaded = try JSONDecoder().decode(ProfileConfiguration.self, from: Data(contentsOf: settingsURL))
                guard loaded.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
                configuration = loaded
                selectedID = loaded.defaultProfile.id
            } catch {
                status = "Saved profiles could not be read. Your file is preserved until you edit a profile."
            }
        }
        interceptor.configuration = { [weak self] in self?.configuration ?? ProfileConfiguration() }
        interceptor.stopped = { [weak self] message in self?.isRunning = false; self?.status = message }
        saveSubscription = $configuration.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { [weak self] value in
            self?.save(value)
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.interceptor.stop()
            // Flush an edit even if Quit arrives during the debounce interval.
            if self.hasEdits { self.save(self.configuration) }
        }
    }

    var selectedProfile: MouseProfile {
        configuration.appProfiles.first { $0.id == selectedID } ?? configuration.defaultProfile
    }

    func updateProfile(_ value: MouseProfile) {
        hasEdits = true
        if value.id == configuration.defaultProfile.id { configuration.defaultProfile = value }
        else if let index = configuration.appProfiles.firstIndex(where: { $0.id == value.id }) { configuration.appProfiles[index] = value }
    }

    func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
        if let existing = configuration.appProfiles.first(where: { $0.bundleIdentifier == identifier }) {
            selectedID = existing.id
            return
        }
        var profile = configuration.defaultProfile
        profile.id = UUID()
        profile.name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent
        profile.bundleIdentifier = identifier
        hasEdits = true
        configuration.appProfiles.append(profile)
        selectedID = profile.id
    }

    func removeSelected() {
        hasEdits = true
        configuration.appProfiles.removeAll { $0.id == selectedID }
        selectedID = configuration.defaultProfile.id
    }

    func start() {
        if let error = interceptor.start() { status = error; return }
        isRunning = true
        status = "Running. The frontmost application's profile applies automatically."
    }
    func stop() {
        interceptor.stop()
        isRunning = false
        status = "Stopped. Mouse events pass through normally."
    }
    private func save(_ value: ProfileConfiguration) {
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: settingsURL, options: .atomic)
        } catch { status = "Could not save profiles: \(error.localizedDescription)" }
    }
}
