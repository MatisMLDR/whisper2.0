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

    /// Variant actuel sélectionné (ex: "base", "small", "large-v3-turbo")
    private(set) var currentVariant: String = "small"

    private init() {}

    func transcribe(audioURL: URL, language: String?) async throws -> String {
        #if canImport(WhisperKit)
        // Initialiser WhisperKit si pas déjà fait
        if whisperKitInstance == nil && !isInitializing {
            try await initializeWhisperKit(variant: currentVariant)
        }

        // Attendre que l'initialisation soit terminée
        while isInitializing {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconde
        }

        guard let whisperKitInstance = whisperKitInstance else {
            throw TranscriptionError.initializationFailed
        }

        // Transcrire avec les paramètres par défaut
        let decodeLanguage = language ?? (currentVariant.contains(".en") ? "en" : "fr")
        let results = try await whisperKitInstance.transcribe(
            audioPath: audioURL.path,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                language: decodeLanguage,
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

    /// Initialise WhisperKit avec le variant spécifié
    private func initializeWhisperKit(variant: String) async throws {
        isInitializing = true
        defer { isInitializing = false }

        let modelName = "openai_whisper-\(variant)"

        do {
            whisperKitInstance = try await WhisperKit(
                model: modelName,
                verbose: false,
                download: true
            )
        } catch {
            print("Erreur d'initialisation WhisperKit: \(error)")
            throw TranscriptionError.initializationFailed
        }
    }
    #endif

    /// Change le variant utilisé pour la transcription
    func setVariant(_ variant: String) {
        guard variant != currentVariant else { return }

        currentVariant = variant
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

    /// Vérifie si un variant est déjà téléchargé
    func isVariantDownloaded(_ variant: String) -> Bool {
        #if canImport(WhisperKit)
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let modelName = "openai_whisper-\(variant)"
        guard let modelPath = documentsDir?
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(modelName, isDirectory: true) else { return false }

        return FileManager.default.fileExists(atPath: modelPath.path)
        #else
        return false
        #endif
    }

    /// Télécharge un variant spécifique
    func downloadVariant(_ variant: String) async throws {
        #if canImport(WhisperKit)
        if isVariantDownloaded(variant) { return }
        _ = try await WhisperKit.download(variant: variant)
        #else
        throw TranscriptionError.whisperKitNotAvailable
        #endif
    }

    /// Pré-charge le modèle pour le télécharger si nécessaire
    func prewarmModel() async {
        #if canImport(WhisperKit)
        if whisperKitInstance == nil && !isInitializing {
            try? await initializeWhisperKit(variant: currentVariant)
        }
        #endif
    }

    /// Pré-charge un variant spécifique
    func prewarmVariant(_ variant: String) async {
        #if canImport(WhisperKit)
        currentVariant = variant
        whisperKitInstance = nil
        try? await initializeWhisperKit(variant: variant)
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
