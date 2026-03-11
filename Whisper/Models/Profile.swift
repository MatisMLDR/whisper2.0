import Foundation

struct Profile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var transcriptionMode: TranscriptionMode
    var selectedLocalModelId: String?
    var language: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        transcriptionMode: TranscriptionMode,
        selectedLocalModelId: String? = nil,
        language: String? = "fr",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.transcriptionMode = transcriptionMode
        self.selectedLocalModelId = selectedLocalModelId
        self.language = language
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func touch() {
        updatedAt = Date()
    }
}

extension Profile {
    static func defaultProfiles(preferredLocalModelId: String?) -> [Profile] {
        [
            Profile(
                name: "Local",
                transcriptionMode: .local,
                selectedLocalModelId: preferredLocalModelId
            ),
            Profile(
                name: "Clé API",
                transcriptionMode: .api
            )
        ]
    }
}
