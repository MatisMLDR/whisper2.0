import Foundation

enum RecordingMode: String, CaseIterable, Identifiable {
    case pushToTalk
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pushToTalk: return "Maintenir pour parler"
        case .toggle: return "Cliquer pour basculer"
        }
    }
}
