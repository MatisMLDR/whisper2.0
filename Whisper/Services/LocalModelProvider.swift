import Foundation
import Combine

/// Service Factory qui gère les modèles locaux et retourne le provider approprié.
/// Permet d'ajouter facilement de nouveaux modèles sans modifier AppState.
@MainActor
final class LocalModelProvider: ObservableObject {
    static let shared = LocalModelProvider()

    // MARK: - Published Properties

    /// Liste des modèles disponibles
    @Published var availableModels: [LocalModel] = LocalModel.allModels()

    /// Modèle sélectionné pour la transcription
    @Published var selectedModel: LocalModel?

    /// État de téléchargement pour chaque modèle (ID: progression 0.0 à 1.0)
    @Published var downloadProgress: [String: Double] = [:]

    /// Indique si un modèle est en cours de téléchargement
    @Published var isDownloading: [String: Bool] = [:]

    /// Message d'erreur si téléchargement échoue
    @Published var errorMessage: String?

    /// Erreur détaillée pour chaque modèle
    @Published var downloadErrors: [String: String] = [:]

    private var downloadTask: Task<Void, Never>?

    private init() {
        // Restaurer la sélection précédente
        restoreSelectedModel()
    }

    private func restoreSelectedModel() {
        if let savedModelId = UserDefaults.standard.string(forKey: "selectedLocalModelId"),
           let model = availableModels.first(where: { $0.id == savedModelId }) {
            // Ne sélectionner que si le modèle est téléchargé (pour CoreML) ou si c'est WhisperKit
            if model.providerType == .whisperKit || model.isReady {
                selectedModel = model
            }
        }

        // Si aucun modèle sélectionné, prendre le premier modèle téléchargé ou WhisperKit par défaut
        if selectedModel == nil {
            if let firstReady = availableModels.first(where: { $0.isReady }) {
                selectedModel = firstReady
            }
        }
    }

    /// Sauvegarde le modèle sélectionné dans UserDefaults
    private func saveSelectedModelId() {
        if let modelId = selectedModel?.id {
            UserDefaults.standard.set(modelId, forKey: "selectedLocalModelId")
        }
    }

    // MARK: - Public Methods

    /// Retourne le provider approprié pour un modèle donné
    func getProvider(for model: LocalModel) -> TranscriptionProvider {
        switch model.providerType {
        case .whisperKit:
            return WhisperKitTranscriptionProvider.shared
        case .coreML:
            return ParakeetTranscriptionProvider.shared
        case .generic:
            return ParakeetTranscriptionProvider.shared
        }
    }

    /// Retourne le provider actuel basé sur le modèle sélectionné
    var currentProvider: TranscriptionProvider? {
        guard let model = selectedModel else { return nil }
        return getProvider(for: model)
    }

    /// Sélectionne un modèle s'il est téléchargé
    func selectModel(_ model: LocalModel) {
        guard model.isReady else { return }
        selectedModel = model
        saveSelectedModelId()
    }

    /// Télécharge un modèle
    func downloadModel(_ model: LocalModel) {
        guard !isDownloading[model.id, default: false] else { return }

        // Lancer le téléchargement de manière asynchrone pour éviter
        // "Publishing changes from within view updates"
        Task { @MainActor in
            errorMessage = nil
            isDownloading[model.id] = true
            downloadProgress[model.id] = 0.0
        }

        downloadTask = Task {
            switch model.providerType {
            case .whisperKit:
                await downloadWhisperKitModel(model)
            case .coreML:
                await downloadCoreMLModel(model)
            case .generic:
                break
            }
        }
    }

    /// Annule le téléchargement d'un modèle
    func cancelDownload(_ model: LocalModel) {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading[model.id] = false
        downloadProgress[model.id] = nil
    }

    /// Réessaie le téléchargement après un échec
    func retryDownload(_ model: LocalModel) {
        downloadErrors[model.id] = nil
        downloadModel(model)
    }

    /// Supprime un modèle téléchargé
    func deleteModel(_ model: LocalModel) {
        switch model.providerType {
        case .whisperKit:
            try? WhisperKitTranscriptionProvider.shared.clearCache()
        case .coreML:
            // FluidAudio gère son propre cache, on libère juste les ressources
            ParakeetTranscriptionProvider.shared.cleanup()
        case .generic:
            break
        }

        // Si le modèle supprimé était sélectionné, changer la sélection
        if selectedModel?.id == model.id {
            selectedModel = availableModels.first(where: { $0.isReady })
            saveSelectedModelId()
        }
    }

    /// Retourne les modèles WhisperKit disponibles
    var whisperKitModels: [LocalModel] {
        availableModels.filter { $0.providerType == .whisperKit }
    }

    /// Retourne les modèles CoreML disponibles
    var coreMLModels: [LocalModel] {
        availableModels.filter { $0.providerType == .coreML }
    }

    /// Retourne la taille du cache pour un type de provider
    func getCacheSize(for providerType: ProviderType) -> UInt64 {
        switch providerType {
        case .whisperKit:
            return WhisperKitTranscriptionProvider.shared.getCacheSize()
        case .coreML:
            guard let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Whisper", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true) else {
                return 0
            }
            return getDirectorySize(path: modelsDir)
        case .generic:
            return 0
        }
    }

    // MARK: - Private Methods

    private func downloadWhisperKitModel(_ model: LocalModel) async {
        // Pour WhisperKit, le téléchargement se fait via le provider
        // On simule une progression car WhisperKit gère ça en interne
        for progress in stride(from: 0.1, through: 0.9, by: 0.1) {
            guard !Task.isCancelled else {
                await MainActor.run {
                    isDownloading[model.id] = false
                }
                return
            }
            await MainActor.run {
                downloadProgress[model.id] = progress
            }
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        }

        // Pré-charger WhisperKit pour forcer le téléchargement réel
        // WhisperKit va télécharger le modèle si nécessaire
        await WhisperKitTranscriptionProvider.shared.prewarmModel()

        // Marquer comme terminé
        await MainActor.run {
            isDownloading[model.id] = false
            downloadProgress[model.id] = 1.0
        }
    }

    private func downloadCoreMLModel(_ model: LocalModel) async {
        downloadErrors[model.id] = nil

        do {
            // Si déjà téléchargé, juste initialiser
            if model.isReady {
                downloadProgress[model.id] = 1.0
                isDownloading[model.id] = false
                await ParakeetTranscriptionProvider.shared.prewarm()
                return
            }

            // Progression pendant le téléchargement SDK
            for progress in stride(from: 0.1, through: 0.9, by: 0.1) {
                guard !Task.isCancelled else {
                    isDownloading[model.id] = false
                    downloadProgress[model.id] = nil
                    return
                }
                downloadProgress[model.id] = progress
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }

            // Télécharger via FluidAudio SDK
            await ParakeetTranscriptionProvider.shared.prewarm()

            // Vérifier si le modèle est bien téléchargé (vérification disque)
            await MainActor.run {
                // Recharger la liste pour rafraîchir isReady
                availableModels = LocalModel.allModels()
            }

            if model.isReady {
                downloadProgress[model.id] = 1.0
                isDownloading[model.id] = false

                // Rafraîchir la sélection
                restoreSelectedModel()
                saveSelectedModelId()
            } else {
                throw NSError(domain: "LocalModelProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Le téléchargement a échoué"])
            }
        } catch {
            downloadErrors[model.id] = error.localizedDescription
            isDownloading[model.id] = false
            downloadProgress[model.id] = nil
        }
    }

    private var cancellables = Set<AnyCancellable>()

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
}
