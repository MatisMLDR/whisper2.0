import Foundation

/// Protocole d'abstraction pour tous les modèles audio locaux.
/// Permet d'ajouter facilement de nouveaux types de modèles (WhisperKit, CoreML, etc.)
protocol LocalAudioModel: Identifiable, Codable, Hashable {
    /// Identifiant unique du modèle
    var id: String { get }

    /// Nom affiché dans l'interface
    var name: String { get }

    /// Description du modèle (langues supportées, performances, etc.)
    var description: String { get }

    /// Langue principale ou "Multilingue"
    var language: String { get }

    /// Taille du fichier pour affichage (ex: "~74 MB", "~1.5 GB")
    var fileSize: String { get }

    /// Type de provider utilisé pour ce modèle
    var providerType: ProviderType { get }

    /// URL d'information/téléchargement (optionnel)
    var infoURL: URL? { get }

    /// Indique si le modèle est prêt à être utilisé
    var isReady: Bool { get }
}

extension LocalAudioModel {
    var infoURL: URL? { nil }
    var isReady: Bool { true }
}

/// Types de providers disponibles pour les modèles locaux
enum ProviderType: String, Codable {
    /// WhisperKit - Framework Swift avec téléchargement automatique
    case whisperKit = "whisperKit"

    /// CoreML - Fichiers .mlmodelc directs (pour Parakeet, etc.)
    case coreML = "coreML"

    /// Type générique pour futurs providers
    case generic = "generic"

    /// Display name pour l'UI
    var displayName: String {
        switch self {
        case .whisperKit:
            return "WhisperKit"
        case .coreML:
            return "CoreML"
        case .generic:
            return "Générique"
        }
    }
}
