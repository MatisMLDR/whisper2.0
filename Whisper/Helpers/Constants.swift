import Foundation

enum Constants {
    static let keychainService = "com.hyrak.whisper"
    static let keychainAPIKeyAccount = "openai-api-key"
    static let openAITranscriptionURL = "https://api.openai.com/v1/audio/transcriptions"
    static let openAIModel = "gpt-4o-mini-transcribe"
    static let doubleTapInterval: TimeInterval = 0.3 // 300ms pour double-tap
}
