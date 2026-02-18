import Foundation

/// Modèle d'IA local disponible pour la transcription
struct LocalModel: LocalAudioModel, Hashable {
    /// Identifiant unique du modèle
    let id: String

    /// Nom affiché dans l'interface
    let name: String

    /// Description du modèle (langues supportées, performances, etc.)
    let description: String

    /// URL de téléchargement du modèle
    let downloadURL: URL

    /// Taille du fichier (pour affichage, ex: "612 MB")
    let fileSize: String

    /// Type de provider utilisé pour ce modèle
    let providerType: ProviderType

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
            // Pour Parakeet via FluidAudio, vérifier si les modèles sont chargés
            return ParakeetTranscriptionProvider.shared.isModelsDownloaded
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

    /// Vérifie si le modèle WhisperKit est téléchargé dans le cache HuggingFace
    private func isWhisperKitModelDownloaded() -> Bool {
        guard let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
            .appendingPathComponent("models--argmaxinc--whisperkit-coreml")
            .appendingPathComponent("snapshots") else {
            return false
        }

        // Lister les snapshots et vérifier si un contient le modèle
        guard let snapshots = try? FileManager.default.contentsOfDirectory(at: cachePath, includingPropertiesForKeys: nil) else {
            return false
        }

        // Pour WhisperKit base/small, on vérifie si le dossier du modèle existe
        let modelName = id == "whisperkit-base" ? "openai_whisper-base" :
                        id == "whisperkit-small" ? "openai_whisper-small" : nil

        guard let modelName = modelName else { return false }

        return snapshots.contains { snapshot in
            let modelPath = snapshot.appendingPathComponent(modelName)
            return FileManager.default.fileExists(atPath: modelPath.path)
        }
    }

    // MARK: - Initializer

    init(
        id: String,
        name: String,
        description: String,
        downloadURL: URL,
        fileSize: String,
        providerType: ProviderType = .coreML,
        language: String = "Multilingue",
        infoURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.downloadURL = downloadURL
        self.fileSize = fileSize
        self.providerType = providerType
        self.language = language
        self.infoURL = infoURL
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case downloadURL
        case fileSize
        case providerType
        case language
        case infoURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        fileSize = try container.decode(String.self, forKey: .fileSize)
        providerType = try container.decodeIfPresent(ProviderType.self, forKey: .providerType) ?? .coreML
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "Multilingue"
        infoURL = try container.decodeIfPresent(URL.self, forKey: .infoURL)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(downloadURL, forKey: .downloadURL)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(providerType, forKey: .providerType)
        try container.encode(language, forKey: .language)
        try container.encodeIfPresent(infoURL, forKey: .infoURL)
    }
}

// MARK: - Predefined Models

extension LocalModel {
    /// Modèles WhisperKit disponibles
    static func whisperKitModels() -> [LocalModel] {
        [
            LocalModel(
                id: "whisperkit-base",
                name: "Whisper Base",
                description: "Modèle rapide multilingue (FR, EN, ...). Idéal pour l'usage quotidien.",
                downloadURL: URL(string: "https://github.com/argmaxinc/WhisperKit")!,
                fileSize: "~74 MB",
                providerType: .whisperKit,
                language: "Multilingue (FR, EN, ...)"
            ),
            LocalModel(
                id: "whisperkit-small",
                name: "Whisper Small",
                description: "Modèle plus précis multilingue. Un peu plus lent.",
                downloadURL: URL(string: "https://github.com/argmaxinc/WhisperKit")!,
                fileSize: "~244 MB",
                providerType: .whisperKit,
                language: "Multilingue (FR, EN, ...)"
            )
        ]
    }

    /// Modèles CoreML disponibles (Parakeet)
    static func coreMLModels() -> [LocalModel] {
        [
            LocalModel(
                id: "parakeet-tdt-0.6b-v3",
                name: "Parakeet TDT 0.6B v3",
                description: "Modèle NVIDIA multilingue ultra-rapide. 6 fichiers CoreML (~620 MB).",
                downloadURL: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!,
                fileSize: "~620 MB",
                providerType: .coreML,
                language: "Multilingue (EN, FR, ...)"
            )
        ]
    }

    /// Tous les modèles disponibles
    static func allModels() -> [LocalModel] {
        whisperKitModels() + coreMLModels()
    }
}
