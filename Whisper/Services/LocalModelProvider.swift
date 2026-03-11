import Foundation

/// Service Factory qui gère les modèles locaux et retourne le provider approprié.
/// Permet d'ajouter facilement de nouveaux modèles sans modifier AppState.
@MainActor
final class LocalModelProvider: ObservableObject {
    static let shared = LocalModelProvider()

    // MARK: - Published Properties

    /// Liste des modèles disponibles (chargés depuis ModelCatalog.json)
    @Published var availableModels: [LocalModel] = LocalModel.allModels()

    /// Modèle sélectionné pour la transcription
    @Published var selectedModel: LocalModel?

    /// État de téléchargement pour chaque modèle (ID: progression 0.0 à 1.0)
    @Published var downloadProgress: [String: Double] = [:]

    /// Indique si un modèle est en cours de téléchargement
    @Published var isDownloading: [String: Bool] = [:]

    /// Temps restant estimé pour chaque téléchargement (ID: secondes)
    @Published var timeRemaining: [String: TimeInterval] = [:]

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
            if model.isReady {
                applySelection(model)
            }
        }

        // Si aucun modèle sélectionné, prendre le premier modèle téléchargé
        if selectedModel == nil {
            if let firstReady = availableModels.first(where: { $0.isReady }) {
                applySelection(firstReady)
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
        configureProvider(for: model)
        return getProvider(for: model)
    }

    /// Sélectionne un modèle s'il est téléchargé
    func selectModel(_ model: LocalModel) {
        guard model.isReady else {
            return
        }

        applySelection(model)
    }

    /// Télécharge un modèle
    func downloadModel(_ model: LocalModel) {
        guard !isDownloading[model.id, default: false] else { return }

        // Initialiser l'état de téléchargement
        errorMessage = nil
        downloadErrors[model.id] = nil
        isDownloading[model.id] = true
        downloadProgress[model.id] = 0.0

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
        timeRemaining[model.id] = nil
    }

    /// Réessaie le téléchargement après un échec
    func retryDownload(_ model: LocalModel) {
        downloadErrors[model.id] = nil
        downloadModel(model)
    }

    /// Supprime un modèle téléchargé
    func deleteModel(_ model: LocalModel) {
        print("🗑️ Suppression du modèle: \(model.name) (ID: \(model.id))")

        // S'assurer que le modèle n'est pas en cours d'utilisation
        if selectedModel?.id == model.id {
            print("⚠️ Le modèle à supprimer est actuellement actif. Désélection...")
            selectedModel = nil
            UserDefaults.standard.removeObject(forKey: "selectedLocalModelId")
        }

        switch model.providerType {
        case .whisperKit:
            // Forcer la libération de l'instance WhisperKit si c'est celle qu'on supprime
            WhisperKitTranscriptionProvider.shared.setVariant("", modelName: "")
            deleteWhisperKitModelFiles(model)
        case .coreML:
            ParakeetTranscriptionProvider.shared.cleanup()
            deleteCoreMLModelFiles()
        case .generic:
            break
        }

        // Un petit délai pour laisser le système de fichiers se mettre à jour
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔄 Rafraîchissement du catalogue après suppression")
            self.availableModels = LocalModel.allModels()

            // Si on a supprimé le modèle actif, on en cherche un autre
            if self.selectedModel == nil {
                if let nextModel = self.availableModels.first(where: { $0.isReady }) {
                    print("✅ Nouveau modèle sélectionné par défaut: \(nextModel.name)")
                    self.applySelection(nextModel)
                } else {
                    print("ℹ️ Aucun autre modèle local prêt à l'emploi.")
                }
            }
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

    /// Recharge le catalogue depuis le JSON
    func reloadCatalog() {
        availableModels = LocalModel.allModels()
        restoreSelectedModel()
    }

    // MARK: - Private Methods

    private func downloadWhisperKitModel(_ model: LocalModel) async {
        // Si déjà téléchargé, juste initialiser
        if model.isReady {
            downloadProgress[model.id] = 1.0
            isDownloading[model.id] = false
            return
        }

        guard let variant = model.whisperKitVariant else {
            downloadErrors[model.id] = "Variant WhisperKit inconnu"
            isDownloading[model.id] = false
            downloadProgress[model.id] = nil
            return
        }

        // Télécharger via WhisperKit avec le variant dynamique
        do {
            let startTime = Date()
            try await WhisperKitTranscriptionProvider.shared.downloadVariant(variant, modelName: model.modelName) { progress in
                self.downloadProgress[model.id] = progress

                let elapsed = Date().timeIntervalSince(startTime)
                if progress > 0 {
                    let totalEstimated = elapsed / progress
                    self.timeRemaining[model.id] = max(0, totalEstimated - elapsed)
                }
            }
        } catch {
            downloadErrors[model.id] = error.localizedDescription
            isDownloading[model.id] = false
            downloadProgress[model.id] = nil
            return
        }

        // Mettre à jour la progression et recharger
        downloadProgress[model.id] = 1.0
        timeRemaining[model.id] = nil
        availableModels = LocalModel.allModels()

        // Vérifier si le modèle est bien téléchargé
        if let updatedModel = availableModels.first(where: { $0.id == model.id }), updatedModel.isReady {
            SoundService.shared.playSuccessSound()
            isDownloading[model.id] = false
            restoreSelectedModel()
            saveSelectedModelId()
        } else {
            isDownloading[model.id] = false
        }
    }

    private func downloadCoreMLModel(_ model: LocalModel) async {
        downloadErrors[model.id] = nil

        // Si déjà téléchargé, juste initialiser
        if model.isReady {
            downloadProgress[model.id] = 1.0
            isDownloading[model.id] = false
            await ParakeetTranscriptionProvider.shared.prewarm()
            return
        }

        // Progression simulée en parallèle du téléchargement SDK (FluidAudio n'expose pas de callback de progression)
        let startTime = Date()
        let progressTask = Task {
            // On simule une progression qui va jusqu'à 95% de manière fluide
            for i in 1...100 {
                if Task.isCancelled { break }

                // Courbe de progression asymétrique : ralentit vers la fin
                let progress = 0.95 * (1.0 - exp(-Double(i) / 15.0))
                self.downloadProgress[model.id] = progress

                let elapsed = Date().timeIntervalSince(startTime)
                if progress > 0.05 {
                    let totalEstimated = elapsed / progress
                    self.timeRemaining[model.id] = max(1, totalEstimated - elapsed)
                }

                // Mise à jour toutes les 200ms pour une barre très fluide
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        // Télécharger via FluidAudio SDK (opération bloquante/longue)
        await ParakeetTranscriptionProvider.shared.prewarm()
        progressTask.cancel()

        // Recharger la liste pour rafraîchir isReady
        availableModels = LocalModel.allModels()

        // Vérifier si le modèle est bien téléchargé (depuis la liste actualisée)
        if let updatedModel = availableModels.first(where: { $0.id == model.id }), updatedModel.isReady {
            SoundService.shared.playSuccessSound()
            downloadProgress[model.id] = 1.0
            timeRemaining[model.id] = nil
            isDownloading[model.id] = false
            restoreSelectedModel()
            saveSelectedModelId()
        } else {
            downloadErrors[model.id] = "Le téléchargement a échoué"
            isDownloading[model.id] = false
            downloadProgress[model.id] = nil
            timeRemaining[model.id] = nil
        }
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

    private func applySelection(_ model: LocalModel) {
        selectedModel = model
        configureProvider(for: model)
        saveSelectedModelId()
    }

    private func configureProvider(for model: LocalModel) {
        guard model.providerType == .whisperKit,
              let variant = model.whisperKitVariant else {
            return
        }

        WhisperKitTranscriptionProvider.shared.setVariant(variant, modelName: model.modelName)
    }

    private func deleteWhisperKitModelFiles(_ model: LocalModel) {
        guard let variant = model.whisperKitVariant else {
            print("❌ Impossible de supprimer: variant WhisperKit manquant")
            return
        }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let folderName = model.modelName ?? "openai_whisper-\(variant)"
        guard let modelPath = documentsDir?
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true) else {
            print("❌ Chemin des modèles WhisperKit introuvable")
            return
        }

        if FileManager.default.fileExists(atPath: modelPath.path) {
            do {
                try FileManager.default.removeItem(at: modelPath)
                print("✅ Fichiers WhisperKit supprimés: \(modelPath.lastPathComponent)")
            } catch {
                print("❌ Erreur lors de la suppression des fichiers WhisperKit: \(error.localizedDescription)")
            }
        } else {
            print("ℹ️ Aucun fichier trouvé au chemin: \(modelPath.path)")
        }
    }

    private func deleteCoreMLModelFiles() {
        guard let modelsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true) else {
            print("❌ Répertoire FluidAudio introuvable")
            return
        }

        do {
            let items = try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            let parakeetModels = items.filter { $0.lastPathComponent.localizedCaseInsensitiveContains("parakeet") }

            if parakeetModels.isEmpty {
                print("ℹ️ Aucun modèle Parakeet trouvé dans \(modelsDirectory.path)")
            }

            for item in parakeetModels {
                try FileManager.default.removeItem(at: item)
                print("✅ Modèle CoreML supprimé: \(item.lastPathComponent)")
            }
        } catch {
            print("❌ Erreur lors de la lecture ou suppression des modèles CoreML: \(error.localizedDescription)")
        }
    }
}
