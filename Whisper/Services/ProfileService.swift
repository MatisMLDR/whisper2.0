import Foundation

@MainActor
final class ProfileService: ObservableObject {
    static let shared = ProfileService()

    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfileId: UUID?

    var activeProfile: Profile? {
        guard let activeProfileId else { return nil }
        return profiles.first(where: { $0.id == activeProfileId })
    }

    var canDeleteProfiles: Bool {
        profiles.count > 1
    }

    private let fileManager = FileManager.default
    private let activeProfileDefaultsKey = "activeProfileId"
    private let legacyModeDefaultsKey = "selectedTranscriptionMode"

    private var fileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let whisperDirectory = appSupport.appendingPathComponent("Whisper", isDirectory: true)
        return whisperDirectory.appendingPathComponent("profiles.json")
    }

    private init() {
        load()
    }

    func createProfile(name: String? = nil, basedOn profile: Profile? = nil) -> Profile {
        let baseProfile = profile ?? activeProfile
        let newProfile = Profile(
            name: sanitizedName(name ?? nextProfileName()),
            transcriptionMode: baseProfile?.transcriptionMode ?? .local,
            selectedLocalModelId: baseProfile?.selectedLocalModelId ?? preferredLocalModelId()
        )

        profiles.append(newProfile)
        setActiveProfile(id: newProfile.id)
        save()

        return newProfile
    }

    func setActiveProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileDefaultsKey)
    }

    func updateName(_ name: String, for profileID: UUID) {
        updateProfile(id: profileID) { profile in
            profile.name = sanitizedName(name, fallback: profile.name)
        }
    }

    func updateTranscriptionMode(_ mode: TranscriptionMode, for profileID: UUID) {
        updateProfile(id: profileID) { profile in
            profile.transcriptionMode = mode
            if mode == .api {
                profile.selectedLocalModelId = nil
            } else if profile.selectedLocalModelId == nil {
                profile.selectedLocalModelId = preferredLocalModelId()
            }
        }
    }

    func updateSelectedLocalModelId(_ localModelId: String?, for profileID: UUID) {
        updateProfile(id: profileID) { profile in
            profile.selectedLocalModelId = localModelId
        }
    }

    func deleteProfile(id: UUID) {
        guard profiles.count > 1 else { return }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        profiles.remove(at: index)

        if activeProfileId == id {
            activeProfileId = profiles.first?.id
            if let activeProfileId {
                UserDefaults.standard.set(activeProfileId.uuidString, forKey: activeProfileDefaultsKey)
            }
        }

        save()
    }

    func profile(with id: UUID) -> Profile? {
        profiles.first(where: { $0.id == id })
    }

    private func updateProfile(id: UUID, mutate: (inout Profile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        var updatedProfile = profiles[index]
        mutate(&updatedProfile)
        updatedProfile.touch()
        profiles[index] = updatedProfile
        save()
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            initializeDefaultProfiles()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            profiles = try JSONDecoder().decode([Profile].self, from: data)
            guard !profiles.isEmpty else {
                initializeDefaultProfiles()
                return
            }
            restoreActiveProfile()
        } catch {
            initializeDefaultProfiles()
        }
    }

    private func restoreActiveProfile() {
        if let savedID = UserDefaults.standard.string(forKey: activeProfileDefaultsKey),
           let uuid = UUID(uuidString: savedID),
           profiles.contains(where: { $0.id == uuid }) {
            activeProfileId = uuid
        } else {
            activeProfileId = resolveDefaultActiveProfileID()
        }

        if let activeProfileId {
            UserDefaults.standard.set(activeProfileId.uuidString, forKey: activeProfileDefaultsKey)
        }

        save()
    }

    private func initializeDefaultProfiles() {
        profiles = Profile.defaultProfiles(preferredLocalModelId: preferredLocalModelId())
        activeProfileId = resolveDefaultActiveProfileID()

        if let activeProfileId {
            UserDefaults.standard.set(activeProfileId.uuidString, forKey: activeProfileDefaultsKey)
        }

        save()
    }

    private func resolveDefaultActiveProfileID() -> UUID? {
        let legacyMode = UserDefaults.standard.string(forKey: legacyModeDefaultsKey)
        let hasAPIKey = KeychainHelper.shared.hasAPIKey
        let hasReadyLocalModel = LocalModel.allModels().contains(where: \.isReady)

        if legacyMode == TranscriptionMode.local.rawValue {
            return profiles.first(where: { $0.transcriptionMode == .local })?.id
        }

        if legacyMode == TranscriptionMode.api.rawValue, hasAPIKey {
            return profiles.first(where: { $0.transcriptionMode == .api })?.id
        }

        if hasReadyLocalModel {
            return profiles.first(where: { $0.transcriptionMode == .local })?.id
        }

        if hasAPIKey {
            return profiles.first(where: { $0.transcriptionMode == .api })?.id
        }

        return profiles.first(where: { $0.transcriptionMode == .local })?.id ?? profiles.first?.id
    }

    private func preferredLocalModelId() -> String? {
        if let savedModelId = UserDefaults.standard.string(forKey: "selectedLocalModelId") {
            return savedModelId
        }

        return LocalModel.allModels().first?.id
    }

    private func nextProfileName() -> String {
        var index = profiles.count + 1

        while profiles.contains(where: { $0.name == "Profil \(index)" }) {
            index += 1
        }

        return "Profil \(index)"
    }

    private func sanitizedName(_ name: String, fallback: String = "Profil") -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let data = try JSONEncoder().encode(profiles)
            try data.write(to: fileURL, options: .atomic)
        } catch {
        }
    }
}
