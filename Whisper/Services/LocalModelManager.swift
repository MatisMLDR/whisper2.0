import Foundation
import Combine
import CoreML

/// Gestionnaire des modèles locaux de transcription.
/// Gère le téléchargement, le stockage et l'état des modèles IA locaux.
@MainActor
final class LocalModelManager: NSObject, ObservableObject {
    static let shared = LocalModelManager()

    // MARK: - Published Properties

    /// Liste des modèles disponibles
    @Published var models: [LocalModel] = [
        LocalModel(
            id: "parakeet-tdt-0.6b-v3",
            name: "Parakeet TDT 0.6B v3",
            description: "Modèle NVIDIA multilingue ultra-rapide. Supporte le français, anglais, etc. Nécessite 7 fichiers CoreML.",
            downloadURL: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!,
            fileSize: "~620 MB"
        )
    ]

    /// Progression de téléchargement pour chaque modèle (ID: 0.0 à 1.0)
    @Published var downloadProgress: [String: Double] = [:]

    /// État de téléchargement pour chaque modèle
    @Published var isDownloading: [String: Bool] = [:]

    /// Message d'erreur si téléchargement échoue
    @Published var errorMessage: String?

    /// Erreur détaillée pour chaque modèle
    @Published var downloadError: [String: String] = [:]

    // URLs de téléchargement HuggingFace pour les fichiers CoreML
    // Format: https://huggingface.co/{org}/{repo}/resolve/main/{filename}
    // NOTE: .mlmodelc files are directories containing multiple files

    // Les 6 bundles de modèle Parakeet
    private let parakeetBundles = [
        "ParakeetDecoder.mlmodelc",
        "Preprocessor.mlmodelc",
        "JointDecisionv2.mlmodelc",
        "MelEncoder.mlmodelc",
        "RNNTJoint.mlmodelc",
        "ParakeetEncoder_15s.mlmodelc"
    ]

    // Fichiers internes de chaque bundle .mlmodelc
    private let mlmodelcInternalFiles = [
        "coremldata.bin",
        "model.mil",
        "analytics/coremldata.bin",
        "weights/weight.bin"
    ]

    // Liste plate de tous les fichiers à télécharger
    private var parakeetFiles: [String] {
        parakeetBundles.flatMap { bundle in
            mlmodelcInternalFiles.map { file in "\(bundle)/\(file)" }
        }
    }

    // Nombre de fichiers téléchargés pour le modèle Parakeet
    @Published var parakeetFilesDownloaded: Int = 0

    /// Nombre de fichiers terminés pour le téléchargement en cours
    private var completedFiles: Int = 0

    // Thread-safe storage for download tasks (accessed from background threads)
    private nonisolated let downloadTasksLock = NSLock()
    private nonisolated var _downloadTasks: [URLSessionDownloadTask: (modelId: String, fileName: String)] = [:]

    private var downloadTasks: [URLSessionDownloadTask: (modelId: String, fileName: String)] {
        get {
            downloadTasksLock.lock()
            defer { downloadTasksLock.unlock() }
            return _downloadTasks
        }
        set {
            downloadTasksLock.lock()
            defer { downloadTasksLock.unlock() }
            _downloadTasks = newValue
        }
    }

    private nonisolated func getDownloadTaskInfo(_ task: URLSessionDownloadTask) -> (modelId: String, fileName: String)? {
        downloadTasksLock.lock()
        defer { downloadTasksLock.unlock() }
        return _downloadTasks[task]
    }

    private nonisolated func removeDownloadTask(_ task: URLSessionDownloadTask) {
        downloadTasksLock.lock()
        defer { downloadTasksLock.unlock() }
        _downloadTasks.removeValue(forKey: task)
    }

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
        createModelsDirectory()
        refreshModelStates()
    }

    // MARK: - Directory Management

    private func createModelsDirectory() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Whisper", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)

        guard let modelsDir = appSupport else { return }

        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
    }

    private nonisolated func getParakeetModelDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Whisper", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
    }

    private func refreshModelStates() {
        // Compter les bundles Parakeet complets (tous les fichiers internes présents)
        guard let modelDir = getParakeetModelDirectory() else { return }

        var completeBundles = 0
        for bundle in parakeetBundles {
            let bundleComplete = mlmodelcInternalFiles.allSatisfy { internalFile in
                let fullPath = modelDir.appendingPathComponent(bundle).appendingPathComponent(internalFile)
                return FileManager.default.fileExists(atPath: fullPath.path)
            }
            if bundleComplete {
                completeBundles += 1
            }
        }
        parakeetFilesDownloaded = completeBundles
        // Note: pas besoin de objectWillChange.send() car parakeetFilesDownloaded est @Published
    }

    // MARK: - Public Methods

    func downloadModel(_ model: LocalModel) {
        guard !isDownloading[model.id, default: false] else { return }
        guard model.id == "parakeet-tdt-0.6b-v3" else { return }

        errorMessage = nil
        downloadError[model.id] = nil

        let allFiles = parakeetFiles
        let totalFiles = allFiles.count

        // Lancer le téléchargement de tous les fichiers
        for filePath in allFiles {
            let fileURL = URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/main/\(filePath)")!

            let task = urlSession.downloadTask(with: fileURL)
            downloadTasks[task] = (model.id, filePath)
        }

        isDownloading[model.id] = true
        downloadProgress[model.id] = 0.0
        completedFiles = 0

        for task in downloadTasks.keys {
            task.resume()
        }
    }

    func cancelDownload(_ model: LocalModel) {
        let tasks = downloadTasks.filter { $0.value.modelId == model.id }
        for (task, _) in tasks {
            task.cancel()
            downloadTasks.removeValue(forKey: task)
        }
        isDownloading[model.id] = false
        downloadProgress[model.id] = nil
    }

    func deleteModel(_ model: LocalModel) {
        guard let modelDir = getParakeetModelDirectory() else { return }

        try? FileManager.default.removeItem(at: modelDir)
        parakeetFilesDownloaded = 0
        refreshModelStates()
    }

    func getReadyModel() -> LocalModel? {
        if parakeetFilesDownloaded == parakeetBundles.count {
            return models.first { $0.id == "parakeet-tdt-0.6b-v3" }
        }
        return nil
    }

    /// Retourne les chemins vers les bundles du modèle Parakeet
    func getParakeetModelPaths() -> [String: URL]? {
        guard parakeetFilesDownloaded == parakeetBundles.count,
              let modelDir = getParakeetModelDirectory() else {
            return nil
        }

        var paths: [String: URL] = [:]
        for bundleName in parakeetBundles {
            let nameWithoutExt = bundleName.replacingOccurrences(of: ".mlmodelc", with: "")
            paths[nameWithoutExt] = modelDir.appendingPathComponent(bundleName)
        }
        return paths
    }
}

// MARK: - URLSessionDownloadDelegate

extension LocalModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (modelId, filePath) = getDownloadTaskInfo(downloadTask) else { return }

        let modelDir = getParakeetModelDirectory()

        guard let destinationDir = modelDir else {
            Task { @MainActor in
                Self.shared.isDownloading[modelId] = false
                Self.shared.errorMessage = "Impossible d'accéder au dossier Models"
            }
            removeDownloadTask(downloadTask)
            return
        }

        let destinationURL = destinationDir.appendingPathComponent(filePath)

        do {
            // Vérifier la taille du fichier (minimum 100 bytes pour les petits fichiers de métadonnées)
            let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
            let fileSize = (attrs[.size] as? UInt64) ?? 0
            guard fileSize > 100 else {
                throw NSError(domain: "Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fichier téléchargé invalide (\(fileSize) bytes)"])
            }

            // Créer les sous-répertoires si nécessaire
            let parentDir = destinationURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Déplacer le fichier
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)

            // Mettre à jour le compteur sur le MainActor
            Task { @MainActor in
                Self.shared.completedFiles += 1
                Self.shared.refreshModelStates()

                // Vérifier si tous les fichiers sont téléchargés
                if Self.shared.parakeetFilesDownloaded == Self.shared.parakeetBundles.count {
                    Self.shared.isDownloading[modelId] = false
                    Self.shared.downloadProgress[modelId] = 1.0
                    Self.shared.completedFiles = 0
                }
            }

        } catch {
            print("Erreur lors du téléchargement de \(filePath): \(error)")
            Task { @MainActor in
                Self.shared.downloadError[modelId] = "Erreur téléchargement \(filePath): \(error.localizedDescription)"
            }
        }

        removeDownloadTask(downloadTask)
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (modelId, _) = getDownloadTaskInfo(downloadTask),
              totalBytesExpectedToWrite > 0 else { return }

        // Progression du fichier actuel (0.0 à 1.0)
        let currentFileProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        Task { @MainActor in
            // Progression globale = (fichiers terminés + progression fichier actuel) / total fichiers
            let totalFiles = Self.shared.parakeetBundles.count * Self.shared.mlmodelcInternalFiles.count
            let overallProgress = (Double(Self.shared.completedFiles) + currentFileProgress) / Double(totalFiles)
            Self.shared.downloadProgress[modelId] = min(overallProgress, 1.0)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (modelId, fileName) = getDownloadTaskInfo(task as! URLSessionDownloadTask) else { return }

        if let error = error {
            let nsError = error as NSError

            // Ignorer les erreurs d'annulation
            guard nsError.code != NSURLErrorCancelled else {
                removeDownloadTask(task as! URLSessionDownloadTask)
                return
            }

            Task { @MainActor in
                Self.shared.isDownloading[modelId] = false
                Self.shared.downloadError[modelId] = "Erreur téléchargement \(fileName): \(error.localizedDescription)"
                Self.shared.errorMessage = "Échec du téléchargement. Vérifiez votre connexion Internet."
            }
        }

        removeDownloadTask(task as! URLSessionDownloadTask)
    }
}
