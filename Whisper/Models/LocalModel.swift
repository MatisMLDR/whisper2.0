import Foundation

/// Modèle d'IA local disponible pour la transcription
struct LocalModel: LocalAudioModel, Hashable {
    /// Identifiant unique du modèle
    let id: String

    /// Nom affiché dans l'interface
    let name: String

    /// Description du modèle (langues supportées, performances, etc.)
    let description: String

    /// Taille du fichier (pour affichage, ex: "612 MB")
    let fileSize: String

    /// Type de provider utilisé pour ce modèle
    let providerType: ProviderType

    /// Variant WhisperKit (ex: "base", "small", "large-v3-turbo") — nil pour les modèles non-WhisperKit
    let whisperKitVariant: String?

    /// Langue principale ou "Multilingue"
    let language: String

    /// URL d'information (optionnel)
    let infoURL: URL?

    // MARK: - LocalAudioModel Conformance

    var isReady: Bool {
        switch providerType {
        case .whisperKit:
            return isWhisperKitModelDownloaded()
        case .coreML:
            return areCoreMLModelsDownloaded()
        case .generic:
            return false
        }
    }

    /// Indique si le modèle est téléchargé (prêt à l'emploi)
    var isDownloaded: Bool {
        isReady
    }

    // MARK: - Legacy Properties

    /// Chemin local du modèle une fois téléchargé (pour CoreML)
    var localPath: URL? {
        guard providerType == .coreML else { return nil }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Whisper", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)

        guard let modelsDir = appSupport else { return nil }
        return modelsDir.appendingPathComponent("\(id).mlmodelc")
    }

    /// Vérifie si le modèle WhisperKit est téléchargé
    private func isWhisperKitModelDownloaded() -> Bool {
        guard let variant = whisperKitVariant else { return false }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let modelBasePath = documentsDir?
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true) else {
            return false
        }

        let modelName = "openai_whisper-\(variant)"
        let modelPath = modelBasePath.appendingPathComponent(modelName, isDirectory: true)
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    /// Vérifie si les modèles CoreML Parakeet sont téléchargés
    private func areCoreMLModelsDownloaded() -> Bool {
        guard providerType == .coreML else { return false }

        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }

        let fluidAudioDir = appSupport.appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)

        guard FileManager.default.fileExists(atPath: fluidAudioDir.path) else {
            return false
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(at: fluidAudioDir, includingPropertiesForKeys: nil) else {
            return false
        }

        for folder in contents where folder.hasDirectoryPath {
            if folder.lastPathComponent.contains("parakeet") {
                if let modelContents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                    let mlmodelcFiles = modelContents.filter { $0.pathExtension == "mlmodelc" }
                    if !mlmodelcFiles.isEmpty {
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case fileSize
        case providerType
        case whisperKitVariant
        case language
        case infoURL
    }
}

// MARK: - Catalog Loading

extension LocalModel {
    /// Structure interne pour décoder le fichier JSON de catalogue
    private struct ModelCatalog: Codable {
        let models: [LocalModel]
    }

    /// Charge tous les modèles depuis le fichier ModelCatalog.json bundlé dans l'app
    static func loadFromCatalog() -> [LocalModel] {
        guard let url = Bundle.main.url(forResource: "ModelCatalog", withExtension: "json") else {
            print("⚠️ ModelCatalog.json introuvable dans le bundle")
            return fallbackModels()
        }

        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(ModelCatalog.self, from: data)
            return catalog.models
        } catch {
            print("⚠️ Erreur de décodage ModelCatalog.json: \(error)")
            return fallbackModels()
        }
    }

    /// Modèles de secours si le fichier JSON est introuvable
    private static func fallbackModels() -> [LocalModel] {
        [
            LocalModel(
                id: "whisperkit-small",
                name: "Whisper Small",
                description: "Modèle multilingue avec un bon compromis vitesse/précision.",
                fileSize: "~244 MB",
                providerType: .whisperKit,
                whisperKitVariant: "small",
                language: "Multilingue (FR, EN, ...)",
                infoURL: nil
            ),
            LocalModel(
                id: "parakeet-tdt-0.6b-v3",
                name: "Parakeet TDT 0.6B v3",
                description: "Modèle NVIDIA multilingue ultra-rapide.",
                fileSize: "~620 MB",
                providerType: .coreML,
                whisperKitVariant: nil,
                language: "Multilingue (EN, FR, ...)",
                infoURL: nil
            )
        ]
    }

    /// Tous les modèles disponibles (alias pour loadFromCatalog)
    static func allModels() -> [LocalModel] {
        loadFromCatalog()
    }
}
