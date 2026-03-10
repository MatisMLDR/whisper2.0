import Foundation

/// Mode de transcription choisi par l'utilisateur
enum TranscriptionMode: String, CaseIterable {
    /// Transcription via l'API OpenAI (Cloud)
    case api = "Cloud (OpenAI)"

    /// Transcription locale avec un modèle IA (Privée)
    case local = "Local (IA Privée)"

    var title: String {
        switch self {
        case .api:
            return "Cloud"
        case .local:
            return "Local"
        }
    }

    var subtitle: String {
        switch self {
        case .api:
            return "OpenAI, précision maximale, connexion Internet requise."
        case .local:
            return "Traitement sur l'appareil, plus privé, fonctionne hors ligne."
        }
    }

    var iconName: String {
        switch self {
        case .api:
            return "cloud"
        case .local:
            return "cpu"
        }
    }
}
