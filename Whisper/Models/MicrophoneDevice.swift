import Foundation

struct MicrophoneDevice: Identifiable, Hashable, Codable {
    let id: String              // AVCaptureDevice.uniqueID
    let name: String            // localizedName
    let manufacturer: String
    let isBuiltIn: Bool
    let audioDeviceID: UInt32   // CoreAudio device ID

    var displayName: String {
        isBuiltIn ? "\(name) (Interne)" : "\(name) (Externe)"
    }

    var iconName: String {
        if isBuiltIn { return "mic.fill" }
        if name.lowercased().contains("airpod") { return "headphones" }
        return "mic.badge.plus"
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MicrophoneDevice, rhs: MicrophoneDevice) -> Bool {
        lhs.id == rhs.id
    }
}
