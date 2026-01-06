import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastError: String?
    @Published var hasAPIKey: Bool

    let audioRecorder = AudioRecorder()
    let keyboardService = KeyboardService()

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
        guard hasAPIKey else {
            lastError = "Configure ta clé API dans les préférences"
            SoundService.shared.playErrorSound()
            return
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

        // Capturer l'app qui a le focus APRÈS (en parallèle de l'enregistrement)
        TextInjector.shared.captureTargetApp()
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
                let text = try await TranscriptionService.shared.transcribe(audioURL: audioURL)
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
        let isValid = await TranscriptionService.shared.validateAPIKey(key)
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
