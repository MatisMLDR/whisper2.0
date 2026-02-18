import Foundation
import AVFoundation
#if canImport(WhisperKit)
import WhisperKit
#endif

/// Provider de transcription utilisant WhisperKit.
/// WhisperKit gère automatiquement le téléchargement et le chargement des modèles.
@MainActor
final class WhisperKitTranscriptionProvider: TranscriptionProvider {
    static let shared = WhisperKitTranscriptionProvider()

    /// Modèles WhisperKit disponibles
    enum WhisperModel: String, CaseIterable {
        case base = "openai_whisper-base"
        case baseEn = "openai_whisper-base.en"
        case small = "openai_whisper-small"
        case smallEn = "openai_whisper-small.en"

        var displayName: String {
            switch self {
            case .base: return "Whisper Base (Multilingue)"
            case .baseEn: return "Whisper Base (Anglais)"
            case .small: return "Whisper Small (Multilingue)"
            case .smallEn: return "Whisper Small (Anglais)"
            }
        }

        var fileSize: String {
            switch self {
            case .base, .baseEn: return "~74 MB"
            case .small, .smallEn: return "~244 MB"
            }
        }

        var language: String {
            switch self {
            case .base, .small: return "Multilingue (FR, EN, ...)"
            case .baseEn, .smallEn: return "Anglais uniquement"
            }
        }
    }

    /// Modèle actuel sélectionné
    private(set) var currentModel: WhisperModel = .base

    private init() {}

    func transcribe(audioURL: URL) async throws -> String {
        #if canImport(WhisperKit)
        // Initialiser WhisperKit si pas déjà fait
        if whisperKitInstance == nil && !isInitializing {
            try await initializeWhisperKit(model: currentModel)
        }

        // Attendre que l'initialisation soit terminée
        while isInitializing {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconde
        }

        guard let whisperKitInstance = whisperKitInstance else {
            throw TranscriptionError.initializationFailed
        }

        // Transcrire avec les paramètres par défaut
        let language = currentModel.rawValue.contains(".en") ? "en" : "fr"
        let results = try await whisperKitInstance.transcribe(
            audioPath: audioURL.path,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                language: language,
                temperatureFallbackCount: 0,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: false,
                clipTimestamps: [0]
            )
        )

        // Extraire le texte des résultats
        let text = results.map { $0.text }.joined(separator: " ")
        guard !text.isEmpty else {
            throw TranscriptionError.emptyTranscription
        }

        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        #else
        // WhisperKit n'est pas disponible - lancer une erreur avec instructions
        throw TranscriptionError.whisperKitNotAvailable
        #endif
    }

    #if canImport(WhisperKit)
    private var whisperKitInstance: WhisperKit?
    private var isInitializing = false

    /// Initialise WhisperKit avec le modèle spécifié
    private func initializeWhisperKit(model: WhisperModel) async throws {
        isInitializing = true
        defer { isInitializing = false }

        do {
            // Créer WhisperKit avec le modèle spécifié
            whisperKitInstance = try await WhisperKit(
                model: model.rawValue,
                verbose: false,
                download: true
            )
        } catch {
            print("Erreur d'initialisation WhisperKit: \(error)")
            throw TranscriptionError.initializationFailed
        }
    }
    #endif

    /// Change le modèle utilisé pour la transcription
    func setModel(_ model: WhisperModel) async throws {
        guard model != currentModel else { return }

        currentModel = model
        #if canImport(WhisperKit)
        whisperKitInstance = nil  // Force la réinitialisation avec le nouveau modèle
        #endif
    }

    /// Retourne la taille du cache WhisperKit
    func getCacheSize() -> UInt64 {
        #if canImport(WhisperKit)
        guard let cachePath = getCachePath() else { return 0 }
        return getDirectorySize(path: cachePath)
        #else
        return 0
        #endif
    }

    /// Supprime le cache WhisperKit
    func clearCache() throws {
        #if canImport(WhisperKit)
        guard let cachePath = getCachePath() else {
            throw TranscriptionError.cacheNotFound
        }
        try FileManager.default.removeItem(at: cachePath)
        whisperKitInstance = nil
        #else
        throw TranscriptionError.whisperKitNotAvailable
        #endif
    }

    /// Vérifie si un modèle est déjà téléchargé
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        #if canImport(WhisperKit)
        // WhisperKit stocke les modèles dans ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let modelPath = documentsDir?
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(model.rawValue, isDirectory: true) else { return false }

        return FileManager.default.fileExists(atPath: modelPath.path)
        #else
        return false
        #endif
    }

    /// Télécharge un modèle spécifique
    func downloadModel(_ model: WhisperModel) async throws {
        #if canImport(WhisperKit)
        // Si déjà téléchargé, pas besoin de retélécharger
        if isModelDownloaded(model) { return }

        // Extraire le variant du modèle (base, small, etc.)
        let variant = model.rawValue.replacingOccurrences(of: "openai_whisper-", with: "")

        // Télécharger le modèle via WhisperKit
        _ = try await WhisperKit.download(variant: variant)
        #else
        throw TranscriptionError.whisperKitNotAvailable
        #endif
    }

    /// Pré-charge le modèle pour le télécharger si nécessaire
    func prewarmModel() async {
        #if canImport(WhisperKit)
        if whisperKitInstance == nil && !isInitializing {
            try? await initializeWhisperKit(model: currentModel)
        }
        #endif
    }

    /// Pré-charge un modèle spécifique
    func prewarmModel(_ model: WhisperModel) async {
        #if canImport(WhisperKit)
        currentModel = model
        whisperKitInstance = nil
        try? await initializeWhisperKit(model: model)
        #endif
    }

    // MARK: - Private Helpers

    private func getCachePath() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface")
    }

    private func getDirectorySize(path: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += UInt64(fileSize)
        }
        return totalSize
    }

    enum TranscriptionError: LocalizedError {
        case initializationFailed
        case emptyTranscription
        case cacheNotFound
        case whisperKitNotAvailable

        var errorDescription: String? {
            switch self {
            case .initializationFailed:
                return "Impossible d'initialiser WhisperKit. Vérifiez votre connexion Internet."
            case .emptyTranscription:
                return "Aucun texte n'a pu être transcrit à partir de l'audio."
            case .cacheNotFound:
                return "Cache WhisperKit introuvable."
            case .whisperKitNotAvailable:
                return "WhisperKit n'est pas installé."
            }
        }
    }
}
