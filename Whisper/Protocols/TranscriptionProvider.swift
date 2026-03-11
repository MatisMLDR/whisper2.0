import Foundation

/// Protocole d'abstraction pour les services de transcription.
/// Permet de basculer facilement entre différents providers (API OpenAI, modèles locaux, etc.)
protocol TranscriptionProvider {
    /// Transcrit un fichier audio en texte
    /// - Parameter audioURL: URL du fichier audio à transcrire
    /// - Parameter language: Langue cible optionnelle (code ISO, ex: "fr", "en")
    /// - Returns: Le texte transcrit
    /// - Throws: Une erreur si la transcription échoue
    func transcribe(audioURL: URL, language: String?) async throws -> String
}
