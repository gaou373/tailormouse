import Foundation

public struct CursorTrackingSettings: Codable, Equatable {
    public var acceleration: Double?
    public var sensitivity: Double?
    public init(acceleration: Double? = nil, sensitivity: Double? = nil) {
        self.acceleration = acceleration; self.sensitivity = sensitivity
    }
    public var isValid: Bool {
        (acceleration.map { $0.isFinite && (0...5).contains($0) } ?? true) &&
        (sensitivity.map { $0.isFinite && (0.25...4).contains($0) } ?? true)
    }
}

public enum ProfileManagementAction: String, Identifiable {
    case copy, transfer, reset
    public var id: String { rawValue }
    public var title: String {
        switch self { case .copy: return "Copy Profile"; case .transfer: return "Transfer Profile"; case .reset: return "Reset Profile" }
    }
}
public struct ApplicationProfileTarget: Equatable, Identifiable {
    public let name: String
    public let bundleIdentifier: String
    public var id: String { bundleIdentifier }
    public init(name: String, bundleIdentifier: String) { self.name = name; self.bundleIdentifier = bundleIdentifier }
}
public enum ProfileManagementError: LocalizedError {
    case missingSource, missingDestination, sameProfile, invalidApplication
    public var errorDescription: String? {
        switch self {
        case .missingSource: return "The source profile no longer exists."
        case .missingDestination: return "Choose a destination application."
        case .sameProfile: return "Choose a different application profile."
        case .invalidApplication: return "The application name or identifier is invalid."
        }
    }
}

extension ProfileConfiguration {
    public var trackingProfile: MouseProfile {
        var profile = defaultProfile
        profile.pointerAcceleration = cursorTracking.acceleration
        profile.pointerSensitivity = cursorTracking.sensitivity
        return profile
    }
    public func profile(id: UUID) -> MouseProfile? {
        id == defaultProfile.id ? defaultProfile : appProfiles.first { $0.id == id }
    }
    private mutating func replaceProfile(_ profile: MouseProfile) {
        if profile.id == defaultProfile.id { defaultProfile = profile }
        else if let index = appProfiles.firstIndex(where: { $0.id == profile.id }) { appProfiles[index] = profile }
    }
    /// Resets application settings while retaining the profile's identity and
    /// all device/global settings. Held input keeps the router's press snapshot.
    public mutating func resetProfile(id: UUID) throws {
        guard let source = profile(id: id) else { throw ProfileManagementError.missingSource }
        var reset = MouseProfile(name: source.name, bundleIdentifier: source.bundleIdentifier)
        reset.id = source.id
        replaceProfile(reset)
    }
    @discardableResult public mutating func manageProfile(_ action: ProfileManagementAction, sourceID: UUID,
                                                          target: ApplicationProfileTarget? = nil) throws -> UUID {
        guard let source = profile(id: sourceID) else { throw ProfileManagementError.missingSource }
        if action == .reset { try resetProfile(id: sourceID); return sourceID }
        guard let target else { throw ProfileManagementError.missingDestination }
        guard !target.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !target.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProfileManagementError.invalidApplication }
        let existing = appProfiles.first { $0.bundleIdentifier == target.bundleIdentifier }
        guard existing?.id != sourceID, source.bundleIdentifier != target.bundleIdentifier else { throw ProfileManagementError.sameProfile }
        let destination = existing ?? MouseProfile(name: target.name, bundleIdentifier: target.bundleIdentifier)
        var copied = source
        copied.id = destination.id; copied.name = destination.name; copied.bundleIdentifier = destination.bundleIdentifier
        // Legacy profile tracking values remain readable for import/history;
        // copying settings must not move them or alter the global controls.
        copied.pointerSpeed = destination.pointerSpeed
        copied.pointerAcceleration = destination.pointerAcceleration
        copied.pointerSensitivity = destination.pointerSensitivity
        if existing == nil { appProfiles.append(copied) } else { replaceProfile(copied) }
        if action == .transfer { try resetProfile(id: sourceID) }
        return copied.id
    }
}
