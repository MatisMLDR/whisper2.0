import Foundation
import AVFoundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// Provider de transcription utilisant le modèle Parakeet TDT 0.6B v3 via FluidAudio SDK.
/// Gère automatiquement le téléchargement et le chargement des modèles CoreML.
@MainActor
final class ParakeetTranscriptionProvider: TranscriptionProvider {
    static let shared = ParakeetTranscriptionProvider()

    /// Stockage thread-safe pour l'état de téléchargement (accessible depuis n'importe quel contexte)
    nonisolated(unsafe) private(set) static var isModelsDownloaded: Bool = false

    #if canImport(FluidAudio)
    private var asrManager: AsrManager?
    private var isInitializing = false
    private var modelsLoaded = false
    #endif

    private init() {}

    func transcribe(audioURL: URL) async throws -> String {
        #if canImport(FluidAudio)
        // Initialiser l'ASR si pas déjà fait
        if asrManager == nil && !isInitializing {
            try await initializeASR()
        }

        // Attendre que l'initialisation soit terminée
        while isInitializing {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconde
        }

        guard let asrManager = asrManager else {
            throw TranscriptionError.initializationFailed
        }

        // Transcrire directement depuis l'URL (FluidAudio gère la conversion de format)
        do {
            let result = try await asrManager.transcribe(audioURL, source: .system)

            guard !result.text.isEmpty else {
                throw TranscriptionError.emptyTranscription
            }

            return result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        } catch {
            print("Erreur de transcription FluidAudio: \(error)")
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
        #else
        // FluidAudio n'est pas disponible - lancer une erreur avec instructions
        throw TranscriptionError.fluidAudioNotAvailable
        #endif
    }

    #if canImport(FluidAudio)
    /// Initialise l'ASR Manager avec les modèles Parakeet
    /// Les modèles sont téléchargés automatiquement via FluidAudio SDK
    private func initializeASR() async throws {
        isInitializing = true
        defer { isInitializing = false }

        do {
            // Télécharger et charger les modèles (mis en cache après le premier téléchargement)
            // v3 = multilingue (FR, EN, etc.), v2 = anglais uniquement
            let models = try await AsrModels.downloadAndLoad(version: .v3)

            // Créer et initialiser l'ASR Manager avec configuration par défaut
            asrManager = AsrManager(config: .default)
            try await asrManager?.initialize(models: models)
            modelsLoaded = true
            Self.isModelsDownloaded = true

            print("Parakeet ASR initialisé avec succès")
        } catch {
            print("Erreur d'initialisation Parakeet: \(error)")
            throw TranscriptionError.initializationFailed
        }
    }
    #endif

    // MARK: - Public Methods

    /// Pré-charge l'ASR pour un démarrage plus rapide
    func prewarm() async {
        #if canImport(FluidAudio)
        if asrManager == nil && !isInitializing {
            try? await initializeASR()
        }
        #endif
    }

    /// Libère les ressources
    func cleanup() {
        #if canImport(FluidAudio)
        asrManager?.cleanup()
        asrManager = nil
        modelsLoaded = false
        #endif
    }

    // MARK: - Error Types

    enum TranscriptionError: LocalizedError {
        case initializationFailed
        case emptyTranscription
        case transcriptionFailed(String)
        case fluidAudioNotAvailable

        var errorDescription: String? {
            switch self {
            case .initializationFailed:
                return "Impossible d'initialiser le moteur de transcription. Vérifiez votre connexion Internet pour le premier téléchargement."
            case .emptyTranscription:
                return "Aucun texte n'a pu être transcrit à partir de l'audio."
            case .transcriptionFailed(let message):
                return "Erreur de transcription: \(message)"
            case .fluidAudioNotAvailable:
                return "FluidAudio SDK n'est pas installé. Ajoutez le package https://github.com/FluidInference/FluidAudio.git (version 0.7.9) au projet Xcode."
            }
        }
    }
}
