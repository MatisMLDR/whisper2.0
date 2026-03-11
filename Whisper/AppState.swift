import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastError: String?
    @Published var hasAPIKey: Bool
    @Published private(set) var hasAccessibilityPermission: Bool

    @Published var recordingShortcut: AppShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(recordingShortcut) {
                UserDefaults.standard.set(data, forKey: "recordingShortcut")
            }
            keyboardService.shortcut = recordingShortcut
        }
    }

    @Published var recordingMode: RecordingMode {
        didSet {
            UserDefaults.standard.set(recordingMode.rawValue, forKey: "recordingMode")
        }
    }

    let profileService = ProfileService.shared
    let localModelProvider = LocalModelProvider.shared
    let audioRecorder = AudioRecorder()
    let keyboardService = KeyboardService()
    let historyService = HistoryService.shared
    let microphoneService = MicrophoneService.shared
    let overlayWindow = RecordingOverlayWindow()

    private var cancellables = Set<AnyCancellable>()

    var profiles: [Profile] {
        profileService.profiles
    }

    var activeProfileId: UUID? {
        profileService.activeProfileId
    }

    var activeProfile: Profile? {
        profileService.activeProfile
    }

    var activeProfileName: String {
        activeProfile?.name ?? "Profil"
    }

    var transcriptionMode: TranscriptionMode {
        activeProfile?.transcriptionMode ?? .local
    }

    var currentProvider: TranscriptionProvider {
        switch transcriptionMode {
        case .api:
            return OpenAITranscriptionProvider.shared
        case .local:
            guard let model = activeReadyLocalModel else {
                return WhisperKitTranscriptionProvider.shared
            }

            localModelProvider.selectModel(model)
            return localModelProvider.getProvider(for: model)
        }
    }

    var hasHistoryEntries: Bool {
        !historyService.entries.isEmpty
    }

    var recentHistoryEntries: [TranscriptionEntry] {
        Array(historyService.entries.prefix(5))
    }

    var availableMicrophones: [MicrophoneDevice] {
        microphoneService.availableDevices
    }

    var activeModeSummary: String {
        switch transcriptionMode {
        case .api:
            return "Ce profil utilise la clé API OpenAI configurée sur ce Mac."
        case .local:
            guard let activeLocalModel else {
                return "Choisis un modèle local pour ce profil."
            }

            if activeLocalModel.isReady {
                return "\(activeLocalModel.name) est prêt pour ce profil."
            }

            return "\(activeLocalModel.name) est sélectionné, mais pas encore téléchargé."
        }
    }

    var providerSummary: String {
        switch transcriptionMode {
        case .api:
            return hasAPIKey ? "OpenAI · \(Constants.openAIModel)" : "Clé API OpenAI manquante"
        case .local:
            guard let activeLocalModel else {
                return "Aucun modèle local choisi"
            }

            return activeLocalModel.isReady ? activeLocalModel.name : "\(activeLocalModel.name) · à télécharger"
        }
    }

    var selectedMicrophoneSummary: String {
        guard !microphoneService.availableDevices.isEmpty else {
            return "Aucun microphone détecté"
        }

        guard let selectedDevice = microphoneService.selectedDevice else {
            return "Micro par défaut du système"
        }

        if microphoneService.isSelectedDeviceAvailable {
            return selectedDevice.displayName
        }

        return "\(selectedDevice.displayName) indisponible"
    }

    var localModelSummary: String {
        guard transcriptionMode == .local else {
            return "Ce profil utilise la clé API OpenAI"
        }

        guard let activeLocalModel else {
            return "Aucun modèle local choisi"
        }

        return activeLocalModel.isReady ? activeLocalModel.name : "\(activeLocalModel.name) · non téléchargé"
    }

    var currentModeConfigurationIssue: String? {
        switch transcriptionMode {
        case .api:
            return hasAPIKey ? nil : "Configure une clé API pour ce profil ou choisis un profil local."
        case .local:
            guard let activeLocalModel else {
                return "Choisis un modèle local pour ce profil."
            }

            return activeLocalModel.isReady ? nil : "Télécharge le modèle \(activeLocalModel.name) ou choisis-en un autre."
        }
    }

    var blockingIssue: String? {
        if currentModeConfigurationIssue != nil {
            return nil
        }

        if audioRecorder.permissionStatus != .authorized {
            return "Autorise l’accès au microphone pour enregistrer."
        }

        if !hasAccessibilityPermission {
            return "Autorise l’accessibilité pour coller le texte automatiquement."
        }

        return lastError
    }

    var statusTitle: String {
        if isTranscribing {
            return "Transcription en cours"
        }

        if isRecording {
            return "Enregistrement en cours"
        }

        if currentModeConfigurationIssue != nil {
            return "Profil à finaliser"
        }

        if blockingIssue != nil {
            return "Configuration requise"
        }

        return "Prêt à dicter"
    }

    var statusDetail: String {
        if isTranscribing {
            return "Le profil \(activeProfileName) est en train de traiter l’audio."
        }

        if isRecording {
            if recordingMode == .toggle {
                return "Appuie à nouveau sur \(recordingShortcut.displayString) pour lancer la transcription avec \(activeProfileName)."
            } else {
                return "Relâche \(recordingShortcut.displayString) pour lancer la transcription avec \(activeProfileName)."
            }
        }

        if let currentModeConfigurationIssue {
            return currentModeConfigurationIssue
        }

        if let blockingIssue {
            return blockingIssue
        }

        if recordingMode == .toggle {
            return "Profil actif: \(activeProfileName). Appuie sur \(recordingShortcut.displayString), parle, puis ré-appuie pour coller le texte."
        } else {
            return "Profil actif: \(activeProfileName). Maintiens \(recordingShortcut.displayString), parle, puis relâche pour coller le texte."
        }
    }

    var statusIconName: String {
        if isTranscribing {
            return "waveform.and.magnifyingglass"
        }

        if isRecording {
            return "mic.fill"
        }

        if currentModeConfigurationIssue != nil {
            return "person.crop.circle.badge.exclamationmark"
        }

        if blockingIssue != nil {
            return "exclamationmark.circle"
        }

        return "checkmark.circle"
    }

    var menuBarIconName: String {
        if isTranscribing {
            return "ellipsis.circle"
        } else if isRecording {
            return "waveform.circle.fill"
        } else if blockingIssue != nil {
            return "exclamationmark.circle"
        } else {
            return "waveform.circle"
        }
    }

    init() {
        hasAPIKey = KeychainHelper.shared.hasAPIKey
        hasAccessibilityPermission = TextInjector.hasAccessibilityPermission()

        if let data = UserDefaults.standard.data(forKey: "recordingShortcut"),
           let shortcut = try? JSONDecoder().decode(AppShortcut.self, from: data) {
            self.recordingShortcut = shortcut
        } else if let savedModifier = UserDefaults.standard.string(forKey: "recordingModifier") {
            let flags: NSEvent.ModifierFlags
            switch savedModifier {
            case "command": flags = .command
            case "option": flags = .option
            case "control": flags = .control
            case "shift": flags = .shift
            default: flags = .function
            }
            self.recordingShortcut = AppShortcut(keyCode: nil, modifiers: flags)
        } else {
            self.recordingShortcut = .defaultShortcut
        }
        
        let savedMode = UserDefaults.standard.string(forKey: "recordingMode") ?? RecordingMode.pushToTalk.rawValue
        let mode = RecordingMode(rawValue: savedMode) ?? .pushToTalk
        self.recordingMode = mode

        bindChildState()
        configureKeyboardMonitoring()
        syncActiveProfileConfiguration()
        refreshUIState()

        keyboardService.shortcut = recordingShortcut
        keyboardService.startMonitoring()

        if !hasAccessibilityPermission {
            TextInjector.requestAccessibilityPermission()
        }

        if let activeReadyLocalModel {
            Task {
                await prewarmSelectedModel(activeReadyLocalModel)
            }
        }
    }

    func refreshUIState() {
        hasAPIKey = KeychainHelper.shared.hasAPIKey
        hasAccessibilityPermission = TextInjector.hasAccessibilityPermission()
        audioRecorder.refreshPermissionStatus()
        microphoneService.refreshDevices()
        syncActiveProfileConfiguration()
    }

    func requestMicrophonePermission() {
        switch audioRecorder.permissionStatus {
        case .notDetermined:
            audioRecorder.refreshPermissionStatus(requestIfNeeded: true)
        case .authorized:
            break
        case .denied, .restricted:
            openPrivacySettings(.microphone)
        }
    }

    func requestAccessibilityPermission() {
        guard !hasAccessibilityPermission else { return }

        TextInjector.requestAccessibilityPermission()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor in
                self?.refreshUIState()
            }
        }
    }

    func openMicrophonePrivacySettings() {
        openPrivacySettings(.microphone)
    }

    func openAccessibilityPrivacySettings() {
        openPrivacySettings(.accessibility)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func selectMicrophone(_ device: MicrophoneDevice?) {
        microphoneService.selectedDevice = device
    }

    func refreshMicrophones() {
        microphoneService.refreshDevices()
    }

    func setActiveProfile(id: UUID) {
        profileService.setActiveProfile(id: id)
        lastError = nil
        syncActiveProfileConfiguration()
    }

    func createProfile() {
        _ = profileService.createProfile()
        lastError = nil
        syncActiveProfileConfiguration()
    }

    func deleteProfile(id: UUID) {
        profileService.deleteProfile(id: id)
        lastError = nil
        syncActiveProfileConfiguration()
    }

    func updateProfileName(_ name: String, for profileID: UUID) {
        profileService.updateName(name, for: profileID)
    }

    func updateProfileMode(_ mode: TranscriptionMode, for profileID: UUID) {
        profileService.updateTranscriptionMode(mode, for: profileID)
        if profileID == activeProfileId {
            lastError = nil
            syncActiveProfileConfiguration()
        }
    }

    func updateProfileLocalModel(_ localModelId: String?, for profileID: UUID) {
        profileService.updateSelectedLocalModelId(localModelId, for: profileID)
        if profileID == activeProfileId {
            lastError = nil
            syncActiveProfileConfiguration()
        }
    }

    func updateProfileLanguage(_ language: String?, for profileID: UUID) {
        profileService.updateLanguage(language, for: profileID)
        if profileID == activeProfileId {
            lastError = nil
            syncActiveProfileConfiguration()
        }
    }

    func updateAPIKey(_ key: String) async -> Bool {
        let isValid = await OpenAITranscriptionProvider.shared.validateAPIKey(key)
        await MainActor.run {
            if isValid {
                _ = KeychainHelper.shared.save(apiKey: key)
                hasAPIKey = true
                lastError = nil
            }
        }
        return isValid
    }

    func clearAPIKey() {
        KeychainHelper.shared.delete()
        hasAPIKey = false
        lastError = nil
    }

    func profileSummary(for profile: Profile) -> String {
        switch profile.transcriptionMode {
        case .api:
            return "Clé API OpenAI"
        case .local:
            guard let localModel = localModelProvider.availableModels.first(where: { $0.id == profile.selectedLocalModelId }) else {
                return "Modèle local à choisir"
            }

            return localModel.isReady ? localModel.name : "\(localModel.name) · à télécharger"
        }
    }

    private var activeLocalModel: LocalModel? {
        guard transcriptionMode == .local else { return nil }
        return localModelProvider.availableModels.first(where: { $0.id == activeProfile?.selectedLocalModelId })
    }

    private var activeReadyLocalModel: LocalModel? {
        guard let activeLocalModel, activeLocalModel.isReady else { return nil }
        return activeLocalModel
    }

    private func bindChildState() {
        forwardChanges(from: audioRecorder.objectWillChange)
        forwardChanges(from: microphoneService.objectWillChange)
        forwardChanges(from: historyService.objectWillChange)
        forwardChanges(from: localModelProvider.objectWillChange)

        profileService.$profiles
            .combineLatest(profileService.$activeProfileId)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.syncActiveProfileConfiguration()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        localModelProvider.$availableModels
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncActiveProfileConfiguration()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshUIState()
            }
            .store(in: &cancellables)
    }

    private func forwardChanges<P: Publisher>(from publisher: P) where P.Output == Void, P.Failure == Never {
        publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func configureKeyboardMonitoring() {
        keyboardService.onModifierPressed = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.recordingMode == .toggle {
                    if self.isRecording {
                        self.stopRecordingAndTranscribe()
                    } else {
                        self.startRecording()
                    }
                } else {
                    // Push to talk
                    self.startRecording()
                }
            }
        }

        keyboardService.onModifierReleased = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if self.recordingMode == .pushToTalk {
                    self.stopRecordingAndTranscribe()
                }
            }
        }

        keyboardService.onEscapePressed = { [weak self] in
            Task { @MainActor in
                self?.cancelRecording()
            }
        }
    }

    private func syncActiveProfileConfiguration() {
        if let activeReadyLocalModel {
            localModelProvider.selectModel(activeReadyLocalModel)
            Task {
                await prewarmSelectedModel(activeReadyLocalModel)
            }
        }
    }

    private func prewarmSelectedModel(_ model: LocalModel) async {
        switch model.providerType {
        case .coreML, .generic:
            await ParakeetTranscriptionProvider.shared.prewarm()
        case .whisperKit:
            if let variant = model.whisperKitVariant {
                await WhisperKitTranscriptionProvider.shared.prewarmVariant(variant)
            } else {
                await WhisperKitTranscriptionProvider.shared.prewarmModel()
            }
        }
    }

    private func startRecording() {
        if let currentModeConfigurationIssue {
            lastError = currentModeConfigurationIssue
            SoundService.shared.playErrorSound()
            return
        }

        guard !isTranscribing else { return }
        guard !isRecording else { return }

        do {
            try audioRecorder.startRecording()
            isRecording = true
            lastError = nil
            SoundService.shared.playStartSound()
            overlayWindow.show(appState: self)
        } catch {
            lastError = error.localizedDescription
            SoundService.shared.playErrorSound()
        }
    }

    func cancelRecording() {
        guard isRecording else { return }

        _ = audioRecorder.stopRecording()
        isRecording = false
        audioRecorder.cleanup()
        overlayWindow.hide()
        SoundService.shared.playErrorSound()
    }

    private func stopRecordingAndTranscribe() {
        guard isRecording else { return }

        guard let audioURL = audioRecorder.stopRecording() else {
            lastError = "Aucun enregistrement trouvé."
            isRecording = false
            SoundService.shared.playErrorSound()
            return
        }

        isRecording = false
        isTranscribing = true
        SoundService.shared.playStopSound()

        Task {
            do {
                let text = try await currentProvider.transcribe(audioURL: audioURL, language: activeProfile?.language)

                await MainActor.run {
                    historyService.add(text)
                    TextInjector.shared.inject(text: text)
                    isTranscribing = false
                    overlayWindow.hide()
                }
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    isTranscribing = false
                    SoundService.shared.playErrorSound()
                    overlayWindow.hide()
                }
            }

            audioRecorder.cleanup()
        }
    }

    private func openPrivacySettings(_ pane: PrivacyPane) {
        let urlString: String
        switch pane {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private extension AppState {
    enum PrivacyPane {
        case microphone
        case accessibility
    }
}
