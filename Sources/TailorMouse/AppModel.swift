import AppKit
import Combine
import TailorMouseCore
import UniformTypeIdentifiers

final class AppModel: ObservableObject {
    @Published var configuration = ProfileConfiguration()
    @Published var selectedID = UUID()
    @Published private(set) var isRunning = false
    @Published var status = "Ready. Choose your mappings, then press Start."
    @Published var lastInput = "No input observed yet."
    @Published private(set) var lastSideButtonPress = "None yet"
    @Published private(set) var lastSideButtonRelease = "None yet"
    let devices = DeviceCatalog()
    let sensitivity = NagaSensitivity()
    private let interceptor = MouseInterceptor()
    private let settingsURL: URL
    private var saveSubscription: AnyCancellable?
    private var terminationObserver: NSObjectProtocol?
    private var hasEdits = false
    private var originalNeedsBackup = false
    private var sideButtonDownEvents: [String: Int] = [:]
    private var sideButtonUpEvents: [String: Int] = [:]
    private var mouseButtonDownEvents: [String: Int] = [:]
    private var mouseButtonUpEvents: [String: Int] = [:]

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TailorMouse", isDirectory: true)
        settingsURL = directory.appendingPathComponent("profiles.json")
        selectedID = configuration.defaultProfile.id
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do {
                let data = try Data(contentsOf: settingsURL)
                let loaded = try Self.decodeConfiguration(data)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                originalNeedsBackup = (json?["schemaVersion"] as? Int) != 2
                configuration = loaded
                selectedID = loaded.defaultProfile.id
            } catch {
                originalNeedsBackup = true
                status = "Saved profiles could not be read. The original will be backed up before saving edits."
            }
        }
        interceptor.configuration = { [weak self] in self?.configuration ?? ProfileConfiguration() }
        interceptor.devices = { [weak self] in self?.devices.devices ?? [] }
        interceptor.observed = { [weak self] value in self?.lastInput = value; self?.writeRuntimeStatus() }
        interceptor.observedButton = { [weak self] button, phase in
            guard let self else { return }
            if (100...111).contains(button) {
                let label = String(button - 99)
                if phase == .down {
                    self.sideButtonDownEvents[label, default: 0] += 1
                    self.lastSideButtonPress = "Naga side \(label)"
                }
                if phase == .up {
                    self.sideButtonUpEvents[label, default: 0] += 1
                    self.lastSideButtonRelease = "Naga side \(label)"
                }
            } else if (0...31).contains(button) {
                let label = String(button + 1)
                if phase == .down { self.mouseButtonDownEvents[label, default: 0] += 1 }
                if phase == .up { self.mouseButtonUpEvents[label, default: 0] += 1 }
            }
        }
        interceptor.stopped = { [weak self] message in self?.isRunning = false; self?.status = message; self?.writeRuntimeStatus() }
        saveSubscription = $configuration.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { [weak self] value in
            guard self?.hasEdits == true else { return }
            self?.save(value)
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.interceptor.stop()
            self.isRunning = false
            self.status = "TailorMouse is closed."
            self.writeRuntimeStatus()
            if self.hasEdits { self.save(self.configuration) }
        }
        devices.refresh()
        writeRuntimeStatus()
    }

    deinit { if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) } }

    var selectedProfile: MouseProfile {
        configuration.appProfiles.first { $0.id == selectedID } ?? configuration.defaultProfile
    }

    func updateProfile(_ value: MouseProfile) {
        hasEdits = true
        if value.id == configuration.defaultProfile.id { configuration.defaultProfile = value }
        else if let index = configuration.appProfiles.firstIndex(where: { $0.id == value.id }) { configuration.appProfiles[index] = value }
    }

    func setDeviceFamily(_ family: String?) {
        guard family != configuration.selectedDeviceFamily else { return }
        if isRunning { stop() }
        hasEdits = true
        configuration.selectedDeviceFamily = family
    }

    func useStandardNagaLayout(transport: String) {
        if isRunning { stop() }
        hasEdits = true
        configuration.nagaKeyboardLayouts.removeValue(forKey: transport)
        status = "Standard \(transport) side-button layout selected. Press Start when ready."
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
        guard selectedID != configuration.defaultProfile.id else { return }
        hasEdits = true
        configuration.appProfiles.removeAll { $0.id == selectedID }
        selectedID = configuration.defaultProfile.id
    }

    func start() {
        devices.refresh()
        if let error = interceptor.start() { status = error; writeRuntimeStatus(); return }
        isRunning = true
        sideButtonDownEvents.removeAll(); sideButtonUpEvents.removeAll()
        mouseButtonDownEvents.removeAll(); mouseButtonUpEvents.removeAll()
        lastSideButtonPress = "None yet"; lastSideButtonRelease = "None yet"
        lastInput = "No input observed yet."
        status = "Running. Application profiles switch automatically."
        writeRuntimeStatus()
    }
    func stop() {
        interceptor.stop()
        isRunning = false
        status = "Stopped. Your mouse works normally."
        writeRuntimeStatus()
    }

    /// Local diagnostic snapshot: status and mouse-button labels only, never
    /// typed characters, general keyboard events or a history of input.
    private func writeRuntimeStatus() {
        let snapshot: [String: Any] = [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "isRunning": isRunning, "status": status, "lastInput": lastInput,
            "connectionCount": devices.connections.count,
            "sideButtonDownEvents": sideButtonDownEvents, "sideButtonUpEvents": sideButtonUpEvents,
            "mouseButtonDownEvents": mouseButtonDownEvents, "mouseButtonUpEvents": mouseButtonUpEvents,
            "lastSideButtonPress": lastSideButtonPress, "lastSideButtonRelease": lastSideButtonRelease,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let url = settingsURL.deletingLastPathComponent().appendingPathComponent("runtime-status.json")
        // Diagnostics must never interrupt input processing or profile saving.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
    func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    func importProfiles() {
        let panel = NSOpenPanel()
        panel.title = "Import TailorMouse profiles"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try Self.decodeConfiguration(Data(contentsOf: url))
            // Preserve the previous on-disk configuration before replacing it.
            try backupOriginal()
            if isRunning { stop() }
            hasEdits = true
            configuration = loaded
            selectedID = loaded.defaultProfile.id
            if save(loaded) { status = "Profiles imported. Press Start when you are ready." }
        } catch { status = "Import failed: \(error.localizedDescription)" }
    }

    func exportProfiles() {
        let panel = NSSavePanel()
        panel.title = "Export TailorMouse profiles"
        panel.nameFieldStringValue = "TailorMouse-profiles.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try encoded(configuration).write(to: url, options: .atomic)
            status = "Profiles exported."
        } catch { status = "Export failed: \(error.localizedDescription)" }
    }

    private static func decodeConfiguration(_ data: Data) throws -> ProfileConfiguration {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["schemaVersion"] as? Int, (1...2).contains(version) else {
            throw NSError(domain: "TailorMouse", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file is not a supported TailorMouse profile file."])
        }
        guard json["defaultProfile"] is [String: Any], json["appProfiles"] is [Any] else {
            throw NSError(domain: "TailorMouse", code: 2, userInfo: [NSLocalizedDescriptionKey: "This file is missing its default or application profiles."])
        }
        let loaded = try JSONDecoder().decode(ProfileConfiguration.self, from: data)
        let profiles = [loaded.defaultProfile] + loaded.appProfiles
        let applicationIDs = loaded.appProfiles.compactMap(\.bundleIdentifier)
        guard loaded.defaultProfile.bundleIdentifier == nil,
              applicationIDs.count == loaded.appProfiles.count,
              applicationIDs.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(applicationIDs).count == applicationIDs.count,
              Set(profiles.map(\.id)).count == profiles.count,
              profiles.allSatisfy(Self.validProfile) else {
            throw NSError(domain: "TailorMouse", code: 2, userInfo: [NSLocalizedDescriptionKey: "Profiles contain duplicate IDs or invalid names, speeds, buttons, shortcuts or chords."])
        }
        return loaded
    }

    private static func validProfile(_ profile: MouseProfile) -> Bool {
        func validButton(_ button: Int) -> Bool { (0...31).contains(button) || (100...111).contains(button) }
        func validBinding(_ binding: ActionBinding) -> Bool {
            (0...31).contains(binding.mouseButton) && (-50...50).contains(binding.scrollX) && (-50...50).contains(binding.scrollY) &&
            (binding.shortcut.map { $0.keyCode <= 127 && $0.modifiers.rawValue <= 15 } ?? true)
        }
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [profile.wheelSpeed, profile.horizontalWheelSpeed, profile.pointerSpeed].allSatisfy({ $0.isFinite && (0.25...4).contains($0) }),
              profile.bindings.allSatisfy({ key, value in Int(key).map(validButton) == true && validBinding(value) }),
              profile.modifierBindings.allSatisfy({ key, value in
                  let parts = key.split(separator: ":")
                  return parts.count == 2 && Int(parts[0]).map(validButton) == true && UInt(parts[1]).map { $0 <= 15 } == true && validBinding(value)
              }),
              Set(profile.chords.map(\.id)).count == profile.chords.count,
              profile.chords.allSatisfy({ $0.isValid && $0.modifiers.rawValue <= 15 && validBinding($0.binding) }) else { return false }
        return true
    }

    private func encoded(_ value: ProfileConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func backupOriginal() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { originalNeedsBackup = false; return }
        let backup = settingsURL.deletingLastPathComponent().appendingPathComponent("profiles-backup-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: settingsURL, to: backup)
        originalNeedsBackup = false
    }

    @discardableResult private func save(_ value: ProfileConfiguration) -> Bool {
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if originalNeedsBackup { try backupOriginal() }
            try encoded(value).write(to: settingsURL, options: .atomic)
            hasEdits = false
            return true
        } catch { status = "Could not save profiles: \(error.localizedDescription)"; return false }
    }
}
