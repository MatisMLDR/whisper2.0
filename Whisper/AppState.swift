import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastError: String?
    @Published var hasAPIKey: Bool
    @Published var transcriptionMode: TranscriptionMode = .api

    /// Gestionnaire des modèles locaux
    @Published var localModelProvider = LocalModelProvider.shared

    let audioRecorder = AudioRecorder()
    let keyboardService = KeyboardService()

    /// Provider de transcription actuel selon le mode choisi
    var currentProvider: TranscriptionProvider {
        switch transcriptionMode {
        case .api:
            return OpenAITranscriptionProvider.shared
        case .local:
            // Utiliser LocalModelProvider pour obtenir le bon provider
            guard let provider = localModelProvider.currentProvider else {
                // Fallback sur WhisperKit si aucun modèle sélectionné
                return WhisperKitTranscriptionProvider.shared
            }
            return provider
        }
    }

    init() {
        hasAPIKey = KeychainHelper.shared.hasAPIKey

        // Push-to-talk: Fn pressé = enregistre, Fn relâché = transcrit
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

        // Démarrer le monitoring du clavier
        keyboardService.startMonitoring()

        // Vérifier les permissions d'accessibilité
        if !TextInjector.hasAccessibilityPermission() {
            TextInjector.requestAccessibilityPermission()
        }
    }

    private func startRecording() {
        // Vérifier les prérequis selon le mode de transcription
        if transcriptionMode == .api {
            guard hasAPIKey else {
                lastError = "Configure ta clé API dans les préférences"
                SoundService.shared.playErrorSound()
                return
            }
        } else {
            // Mode local: vérifier qu'un modèle est sélectionné et prêt
            guard let selectedModel = localModelProvider.selectedModel,
                  selectedModel.isReady else {
                lastError = "Téléchargez un modèle local dans les préférences"
                SoundService.shared.playErrorSound()
                return
            }
        }

        guard !isTranscribing else { return }
        guard !isRecording else { return }

        // Démarrer l'enregistrement EN PREMIER pour capturer les premiers mots
        do {
            try audioRecorder.startRecording()
            isRecording = true
            lastError = nil
            SoundService.shared.playStartSound()
        } catch {
            lastError = error.localizedDescription
            SoundService.shared.playErrorSound()
            return
        }

        // Note: La capture de l'app cible se fait maintenant automatiquement
        // dans TextInjector.inject() au moment du collage, pas ici
    }

    private func stopRecordingAndTranscribe() {
        guard isRecording else { return }

        guard let audioURL = audioRecorder.stopRecording() else {
            lastError = "Aucun enregistrement trouvé"
            isRecording = false
            SoundService.shared.playErrorSound()
            return
        }

        isRecording = false
        isTranscribing = true
        SoundService.shared.playStopSound()

        Task {
            do {
                // Utiliser le provider actuel
                let text = try await currentProvider.transcribe(audioURL: audioURL)

                await MainActor.run {
                    // Sauvegarder dans l'historique
                    HistoryService.shared.add(text)
                    // Coller le texte
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

            // Nettoyer le fichier audio temporaire
            audioRecorder.cleanup()
        }
    }

    func updateAPIKey(_ key: String) async -> Bool {
        let isValid = await OpenAITranscriptionProvider.shared.validateAPIKey(key)
        await MainActor.run {
            if isValid {
                _ = KeychainHelper.shared.save(apiKey: key)
                hasAPIKey = true
            }
        }
        return isValid
    }

    func clearAPIKey() {
        KeychainHelper.shared.delete()
        hasAPIKey = false
    }
}
