import Foundation

/// Mode de transcription choisi par l'utilisateur
enum TranscriptionMode: String, CaseIterable {
    /// Transcription via l'API OpenAI (Cloud)
    case api = "Cloud (OpenAI)"

    /// Transcription locale avec un modèle IA (Privée)
    case local = "Local (IA Privée)"
}
