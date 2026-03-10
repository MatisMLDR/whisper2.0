import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastError: String?
    @Published var hasAPIKey: Bool
    @Published var transcriptionMode: TranscriptionMode {
        didSet {
            UserDefaults.standard.set(transcriptionMode.rawValue, forKey: Self.transcriptionModeDefaultsKey)
        }
    }
    @Published private(set) var hasAccessibilityPermission: Bool

    let localModelProvider = LocalModelProvider.shared
    let audioRecorder = AudioRecorder()
    let keyboardService = KeyboardService()
    let historyService = HistoryService.shared
    let microphoneService = MicrophoneService.shared

    private var cancellables = Set<AnyCancellable>()

    private static let transcriptionModeDefaultsKey = "selectedTranscriptionMode"

    var currentProvider: TranscriptionProvider {
        switch transcriptionMode {
        case .api:
            return OpenAITranscriptionProvider.shared
        case .local:
            guard let provider = localModelProvider.currentProvider else {
                return WhisperKitTranscriptionProvider.shared
            }
            return provider
        }
    }

    var hasHistoryEntries: Bool {
        !historyService.entries.isEmpty
    }

    var recentHistoryEntries: [TranscriptionEntry] {
        Array(historyService.entries.prefix(5))
    }

    var activeModeSummary: String {
        transcriptionMode.subtitle
    }

    var providerSummary: String {
        switch transcriptionMode {
        case .api:
            return "OpenAI · \(Constants.openAIModel)"
        case .local:
            return localModelProvider.selectedModel?.name ?? "Aucun modèle local sélectionné"
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
        if let selectedModel = localModelProvider.selectedModel, selectedModel.isReady {
            return selectedModel.name
        }
        return "Aucun modèle prêt"
    }

    var currentModeConfigurationIssue: String? {
        if transcriptionMode == .api && !hasAPIKey {
            return "Passe en mode Local ou configure une clé API."
        }

        if transcriptionMode == .local && !(localModelProvider.selectedModel?.isReady ?? false) {
            return "Choisis un modèle local ou passe en mode Clé API."
        }

        return nil
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
            return "Mode à choisir"
        }

        if blockingIssue != nil {
            return "Configuration requise"
        }

        return "Prêt à dicter"
    }

    var statusDetail: String {
        if isTranscribing {
            return "L’audio est en train d’être converti en texte."
        }

        if isRecording {
            return "Relâche Fn pour lancer la transcription."
        }

        if let currentModeConfigurationIssue {
            return currentModeConfigurationIssue
        }

        if let blockingIssue {
            return blockingIssue
        }

        return "Maintiens Fn, parle, puis relâche pour coller le texte."
    }

    var statusIconName: String {
        if isTranscribing {
            return "waveform.and.magnifyingglass"
        }

        if isRecording {
            return "mic.fill"
        }

        if currentModeConfigurationIssue != nil {
            return "arrow.left.arrow.right.circle"
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

    var shouldAnimateMenuBarIcon: Bool {
        isTranscribing || isRecording
    }

    init() {
        let savedMode = UserDefaults.standard.string(forKey: Self.transcriptionModeDefaultsKey)
        let initialHasAPIKey = KeychainHelper.shared.hasAPIKey
        let hasReadyLocalModel = LocalModelProvider.shared.selectedModel?.isReady == true

        hasAPIKey = initialHasAPIKey
        transcriptionMode = Self.preferredInitialTranscriptionMode(
            savedMode: savedMode,
            hasAPIKey: initialHasAPIKey,
            hasReadyLocalModel: hasReadyLocalModel
        )
        hasAccessibilityPermission = TextInjector.hasAccessibilityPermission()

        bindChildState()
        configureKeyboardMonitoring()
        refreshUIState()

        keyboardService.startMonitoring()

        if !hasAccessibilityPermission {
            TextInjector.requestAccessibilityPermission()
        }

        if let selectedModel = localModelProvider.selectedModel, selectedModel.isReady {
            Task {
                await prewarmSelectedModel(selectedModel)
            }
        }
    }

    func refreshUIState() {
        hasAPIKey = KeychainHelper.shared.hasAPIKey
        hasAccessibilityPermission = TextInjector.hasAccessibilityPermission()
        audioRecorder.refreshPermissionStatus()
        microphoneService.refreshDevices()
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

    func setTranscriptionMode(_ mode: TranscriptionMode) {
        guard transcriptionMode != mode else { return }

        transcriptionMode = mode
        lastError = nil

        guard mode == .local,
              let selectedModel = localModelProvider.selectedModel,
              selectedModel.isReady else {
            return
        }

        Task {
            await prewarmSelectedModel(selectedModel)
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

    private func bindChildState() {
        forwardChanges(from: localModelProvider.objectWillChange)
        forwardChanges(from: audioRecorder.objectWillChange)
        forwardChanges(from: microphoneService.objectWillChange)
        forwardChanges(from: historyService.objectWillChange)

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
        keyboardService.onFnPressed = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }

        keyboardService.onFnReleased = { [weak self] in
            Task { @MainActor in
                self?.stopRecordingAndTranscribe()
            }
        }
    }

    private func prewarmSelectedModel(_ model: LocalModel) async {
        switch model.providerType {
        case .coreML, .generic:
            await ParakeetTranscriptionProvider.shared.prewarm()
        case .whisperKit:
            if let whisperModel = whisperKitModel(for: model) {
                await WhisperKitTranscriptionProvider.shared.prewarmModel(whisperModel)
            } else {
                await WhisperKitTranscriptionProvider.shared.prewarmModel()
            }
        }
    }

    private static func preferredInitialTranscriptionMode(
        savedMode: String?,
        hasAPIKey: Bool,
        hasReadyLocalModel: Bool
    ) -> TranscriptionMode {
        if let savedMode,
           let mode = TranscriptionMode(rawValue: savedMode) {
            return mode
        }

        if hasReadyLocalModel {
            return .local
        }

        if hasAPIKey {
            return .api
        }

        return .local
    }

    private func whisperKitModel(for model: LocalModel) -> WhisperKitTranscriptionProvider.WhisperModel? {
        switch model.id {
        case "whisperkit-base":
            return .base
        case "whisperkit-small":
            return .small
        default:
            return nil
        }
    }

    private func startRecording() {
        if transcriptionMode == .api {
            guard hasAPIKey else {
                lastError = "Configure ta clé API dans les réglages."
                SoundService.shared.playErrorSound()
                return
            }
        } else {
            guard let selectedModel = localModelProvider.selectedModel,
                  selectedModel.isReady else {
                lastError = "Télécharge un modèle local dans les réglages."
                SoundService.shared.playErrorSound()
                return
            }
        }

        guard !isTranscribing else { return }
        guard !isRecording else { return }

        do {
            try audioRecorder.startRecording()
            isRecording = true
            lastError = nil
            SoundService.shared.playStartSound()
        } catch {
            lastError = error.localizedDescription
            SoundService.shared.playErrorSound()
        }
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
                let text = try await currentProvider.transcribe(audioURL: audioURL)

                await MainActor.run {
                    historyService.add(text)
                    TextInjector.shared.inject(text: text)
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                    isTranscribing = false
                    SoundService.shared.playErrorSound()
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
