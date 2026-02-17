import AVFoundation

/// Convertisseur de fichiers audio pour la transcription locale.
/// Convertit les fichiers M4A (AAC) en WAV PCM requis par CoreML.
final class AudioConverter {

    /// Convertit un fichier M4A en WAV PCM 16kHz mono 16-bit
    /// - Parameter m4aURL: URL du fichier M4A source
    /// - Returns: URL du fichier WAV converti
    /// - Throws: AudioConverterError si la conversion échoue
    static func convertToWAV(m4aURL: URL) async throws -> URL {
        // Créer l'URL de sortie
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("whisper_wav_\(UUID().uuidString).wav")

        // Charger l'asset audio
        let asset = AVAsset(url: m4aURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioConverterError.exportSessionCreationFailed
        }

        // Configurer la sortie WAV
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .wav

        // Configurer les paramètres audio pour WAV PCM 16kHz mono 16-bit
        exportSession.audioTimePitchAlgorithm = .timeDomain
        exportSession.audioMix = AVMutableAudioMix()

        // Attendre la fin de l'export
        await exportSession.export()

        // Vérifier le résultat
        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed:
            throw AudioConverterError.conversionFailed(exportSession.error?.localizedDescription ?? "Erreur inconnue")
        case .cancelled:
            throw AudioConverterError.cancelled
        default:
            throw AudioConverterError.unknownStatus
        }
    }

    /// Nettoie un fichier WAV temporaire
    /// - Parameter url: URL du fichier à supprimer
    static func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Errors

    enum AudioConverterError: LocalizedError {
        case exportSessionCreationFailed
        case conversionFailed(String)
        case cancelled
        case unknownStatus

        var errorDescription: String? {
            switch self {
            case .exportSessionCreationFailed:
                return "Impossible de créer la session d'export"
            case .conversionFailed(let message):
                return "Échec de la conversion: \(message)"
            case .cancelled:
                return "Conversion annulée"
            case .unknownStatus:
                return "Statut de conversion inconnu"
            }
        }
    }
}
