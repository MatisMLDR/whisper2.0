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

    // Fichiers individuels du modèle Parakeet
    private let parakeetFiles = [
        "ParakeetDecoder.mlmodelc",
        "Preprocessor.mlmodelc",
        "JointDecisionv2.mlmodelc",
        "MelEncoder.mlmodelc",
        "RNNTJoint.mlmodelc",
        "ParakeetEncoder_15s.mlmodelc"
    ]

    // Nombre de fichiers téléchargés pour le modèle Parakeet
    @Published var parakeetFilesDownloaded: Int = 0

    /// Nombre de fichiers terminés pour le téléchargement en cours
    private var completedFiles: Int = 0

    private var downloadTasks: [URLSessionDownloadTask: (modelId: String, fileName: String)] = [:]
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

    private func getParakeetModelDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Whisper", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
    }

    private func refreshModelStates() {
        // Compter les fichiers Parakeet téléchargés
        if let modelDir = getParakeetModelDirectory() {
            let downloadedCount = parakeetFiles.filter { fileName in
                FileManager.default.fileExists(atPath: modelDir.appendingPathComponent(fileName).path)
            }.count
            parakeetFilesDownloaded = downloadedCount
        }
        objectWillChange.send()
    }

    // MARK: - Public Methods

    func downloadModel(_ model: LocalModel) {
        guard !isDownloading[model.id, default: false] else { return }
        guard model.id == "parakeet-tdt-0.6b-v3" else { return }

        errorMessage = nil

        // Lancer le téléchargement de tous les fichiers
        for fileName in parakeetFiles {
            let fileURL = URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/main/\(fileName)")!

            var request = URLRequest(url: fileURL)
            request.httpMethod = "HEAD"

            // Vérifier si le fichier existe déjà
            let task = urlSession.downloadTask(with: fileURL)
            downloadTasks[task] = (model.id, fileName)
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
        if parakeetFilesDownloaded == parakeetFiles.count {
            return models.first { $0.id == "parakeet-tdt-0.6b-v3" }
        }
        return nil
    }

    /// Retourne les chemins vers les fichiers du modèle Parakeet
    func getParakeetModelPaths() -> [String: URL]? {
        guard parakeetFilesDownloaded == parakeetFiles.count,
              let modelDir = getParakeetModelDirectory() else {
            return nil
        }

        var paths: [String: URL] = [:]
        for fileName in parakeetFiles {
            let nameWithoutExt = fileName.replacingOccurrences(of: ".mlmodelc", with: "")
            paths[nameWithoutExt] = modelDir.appendingPathComponent(fileName)
        }
        return paths
    }
}

// MARK: - URLSessionDownloadDelegate

extension LocalModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (modelId, fileName) = downloadTasks[downloadTask] else { return }

        guard let modelDir = getParakeetModelDirectory() else {
            Task { @MainActor in
                isDownloading[modelId] = false
                errorMessage = "Impossible d'accéder au dossier Models"
            }
            downloadTasks.removeValue(forKey: downloadTask)
            return
        }

        let destinationURL = modelDir.appendingPathComponent(fileName)

        do {
            // Vérifier la taille du fichier
            let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
            guard let fileSize = attrs[.size] as? UInt64, fileSize > 1_000_000 else {
                throw NSError(domain: "Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fichier téléchargé invalide"])
            }

            // Déplacer le fichier
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)

            // Mettre à jour le compteur
            refreshModelStates()
            completedFiles = parakeetFilesDownloaded

            // Vérifier si tous les fichiers sont téléchargés
            if parakeetFilesDownloaded == parakeetFiles.count {
                Task { @MainActor in
                    isDownloading[modelId] = false
                    downloadProgress[modelId] = 1.0
                    completedFiles = 0
                }
            }

        } catch {
            print("Erreur lors du téléchargement de \(fileName): \(error)")
        }

        downloadTasks.removeValue(forKey: downloadTask)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (modelId, _) = downloadTasks[downloadTask],
              totalBytesExpectedToWrite > 0 else { return }

        // Progression du fichier actuel (0.0 à 1.0)
        let currentFileProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        // Progression globale = (fichiers terminés + progression fichier actuel) / total fichiers
        let overallProgress = (Double(completedFiles) + currentFileProgress) / Double(parakeetFiles.count)

        Task { @MainActor in
            downloadProgress[modelId] = min(overallProgress, 1.0)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else {
                // Trouver le modelId
                if let (modelId, _) = downloadTasks[task as! URLSessionDownloadTask] {
                    Task { @MainActor in
                        isDownloading[modelId] = false
                        errorMessage = "Erreur de téléchargement: \(error.localizedDescription)"
                    }
                }
                return
            }
        }
    }
}
