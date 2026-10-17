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
    let updater = AppUpdater()
    let devices = DeviceCatalog()
    let sensitivity = NagaSensitivity()
    let pointer = NativePointer()
    let indicators = InputIndicators()
    private let interceptor = MouseInterceptor()
    private let settingsURL: URL
    private let preview: Bool
    private var saveSubscription: AnyCancellable?
    private var terminationObserver: NSObjectProtocol?
    private var hasEdits = false
    private var originalNeedsBackup = false
    private var sideButtonDownEvents: [String: Int] = [:]
    private var sideButtonUpEvents: [String: Int] = [:]
    private var mouseButtonDownEvents: [String: Int] = [:]
    private var mouseButtonUpEvents: [String: Int] = [:]

    init(preview: Bool = false) {
        self.preview = preview
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TailorMouse", isDirectory: true)
        settingsURL = directory.appendingPathComponent("profiles.json")
        selectedID = configuration.defaultProfile.id
        // UI rendering uses an isolated in-memory model. It never loads/saves
        // user settings, writes runtime status or starts input interception.
        if preview { indicators.monitoringEnabled = false; sensitivity.hardwareEnabled = false; return }
        indicators.devices = { [weak self] in self?.devices.devices ?? [] }
        indicators.family = { [weak self] in self?.configuration.selectedDeviceFamily }
        indicators.beginModifiers()
        pointer.configuration = { [weak self] in self?.configuration ?? ProfileConfiguration() }
        pointer.profile = { [weak self] in self?.configuration.trackingProfile ?? MouseProfile() }
        pointer.captureWiredReference = { [weak self] values in
            guard let self, values.isValidReference, self.configuration.nagaWiredTrackingReference == nil else { return }
            self.hasEdits = true
            self.configuration.nagaWiredTrackingReference = values
        }
        pointer.failed = { [weak self] message in self?.stop(); self?.status = message; self?.writeRuntimeStatus() }
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do {
                let data = try Data(contentsOf: settingsURL)
                let loaded = try Self.decodeConfiguration(data)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                originalNeedsBackup = (json?["schemaVersion"] as? Int) != 3
                configuration = loaded
                selectedID = loaded.defaultProfile.id
            } catch {
                originalNeedsBackup = true
                status = "Saved profiles could not be read. The original will be backed up before saving edits."
            }
        }
        interceptor.configuration = { [weak self] in self?.configuration ?? ProfileConfiguration() }
        interceptor.devices = { [weak self] in self?.devices.devices ?? [] }
        interceptor.keyboardModifiers = { [weak self] in self?.indicators.modifiers ?? [] }
        interceptor.observed = { [weak self] value in self?.lastInput = value; self?.writeRuntimeStatus() }
        interceptor.observedButton = { [weak self] button, phase in
            guard let self else { return }
            self.indicators.observed(button: button, phase: phase)
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
        interceptor.stopped = { [weak self] message in self?.pointer.stop(); self?.isRunning = false; self?.status = message; self?.writeRuntimeStatus() }
        saveSubscription = $configuration.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { [weak self] value in
            guard self?.hasEdits == true else { return }
            self?.save(value)
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.interceptor.stop()
            self.pointer.stop()
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
        pointer.edited()
    }

    func updateCursorTracking(_ settings: CursorTrackingSettings) {
        guard settings.isValid else { return }
        hasEdits = true; configuration.cursorTracking = settings; pointer.edited()
    }

    func chooseApplicationTarget() -> ApplicationProfileTarget? {
        let panel = NSOpenPanel()
        panel.title = "Choose a destination application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent
        return ApplicationProfileTarget(name: name, bundleIdentifier: identifier)
    }

    func manageProfile(_ action: ProfileManagementAction, sourceID: UUID, target: ApplicationProfileTarget?) throws {
        var next = configuration
        let selected = try next.manageProfile(action, sourceID: sourceID, target: target)
        if preview { configuration = next; selectedID = selected; return }
        // Back up the complete in-memory configuration before applying a
        // reset/replacement, including edits still waiting for autosave.
        let directory = settingsURL.deletingLastPathComponent().appendingPathComponent("Profile Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backup = directory.appendingPathComponent("profiles-\(UUID().uuidString).json")
        let data = try encoded(configuration)
        guard FileManager.default.createFile(atPath: backup.path, contents: data, attributes: [.posixPermissions: 0o600]),
              try Data(contentsOf: backup) == data else {
            throw NSError(domain: "TailorMouse", code: 3, userInfo: [NSLocalizedDescriptionKey: "The existing profiles could not be backed up."])
        }
        let previous = configuration; let previousSelected = selectedID; let previousHasEdits = hasEdits
        hasEdits = true; configuration = next; selectedID = selected
        guard save(next) else {
            configuration = previous; selectedID = previousSelected; hasEdits = previousHasEdits
            throw NSError(domain: "TailorMouse", code: 4, userInfo: [NSLocalizedDescriptionKey: "The profile change could not be saved. Your previous settings are retained."])
        }
        status = action == .reset ? "Profile reset. Shared cursor settings are unchanged." : "Profile \(action == .copy ? "copied" : "transferred") to \(target?.name ?? "application")."
        writeRuntimeStatus()
    }

    func setDeviceFamily(_ family: String?) {
        guard family != configuration.selectedDeviceFamily else { return }
        if isRunning { stop() }
        indicators.resetDetectedButtons()
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
        if indicators.recording { indicators.cancelRecording() }
        devices.refresh()
        if let error = interceptor.start() { status = error; writeRuntimeStatus(); return }
        isRunning = true
        pointer.start()
        guard isRunning else { return }
        sideButtonDownEvents.removeAll(); sideButtonUpEvents.removeAll()
        mouseButtonDownEvents.removeAll(); mouseButtonUpEvents.removeAll()
        lastSideButtonPress = "None yet"; lastSideButtonRelease = "None yet"
        lastInput = "No input observed yet."
        status = "Running. Application profiles switch automatically."
        writeRuntimeStatus()
    }
    func stop() {
        if indicators.recording { indicators.cancelRecording() }
        interceptor.stop()
        pointer.stop()
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
            "bluetoothRawEndpointCount": interceptor.bluetoothEndpointCount,
            "rawKeyboardEndpointCount": interceptor.rawKeyboardEndpointCount,
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
              let version = json["schemaVersion"] as? Int, (1...3).contains(version) else {
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
            (binding.shortcut.map { $0.isValid } ?? true) && (binding.action != .modifierKey || binding.modifierKey != nil) &&
            (binding.snapDestination.map { ["screen", "window"].contains($0) } ?? true) &&
            (binding.openTarget.map { $0.count <= 4096 && ($0.hasPrefix("/") || ["http", "https"].contains(URL(string: $0)?.scheme ?? "")) } ?? true)
        }
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              [profile.wheelSpeed, profile.horizontalWheelSpeed, profile.pointerSpeed].allSatisfy({ $0.isFinite && (0.25...4).contains($0) }),
              profile.pointerAcceleration.map({ $0.isFinite && (0...5).contains($0) }) ?? true,
              profile.pointerSensitivity.map({ $0.isFinite && (0.25...4).contains($0) }) ?? true,
              profile.wheelBindings.allSatisfy({ key, value in
                  let parts = key.split(separator: ":")
                  return (1...2).contains(parts.count) && WheelDirection(rawValue: String(parts[0])) != nil &&
                      (parts.count == 1 || UInt(parts[1]).map { $0 <= 15 } == true) && validBinding(value)
              }),
              profile.bindings.allSatisfy({ key, value in Int(key).map(validButton) == true && validBinding(value) }),
              profile.modifierBindings.allSatisfy({ key, value in
                  let parts = key.split(separator: ":")
                  return parts.count == 2 && Int(parts[0]).map(validButton) == true && UInt(parts[1]).map { $0 <= 15 } == true && validBinding(value)
              }),
              Set(profile.chords.map(\.id)).count == profile.chords.count,
              profile.chords.allSatisfy({ $0.isValid && $0.modifiers.rawValue <= 15 && ($0.note?.count ?? 0) <= 1000 && validBinding($0.binding) }) else { return false }
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
