import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    enum PermissionStatus: Equatable {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    @Published private(set) var isRecording = false
    @Published private(set) var hasPermission = false
    @Published private(set) var permissionStatus: PermissionStatus = .notDetermined

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private let microphoneService = MicrophoneService.shared

    override init() {
        super.init()
        refreshPermissionStatus(requestIfNeeded: true)
    }

    func refreshPermissionStatus(requestIfNeeded: Bool = false) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
            permissionStatus = .authorized
        case .notDetermined:
            permissionStatus = .notDetermined
            hasPermission = false
            guard requestIfNeeded else { return }

            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.hasPermission = granted
                    self?.permissionStatus = granted ? .authorized : .denied
                }
            }
        case .denied, .restricted:
            hasPermission = false
            permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio) == .restricted ? .restricted : .denied
        @unknown default:
            hasPermission = false
            permissionStatus = .denied
        }
    }

    private func getRecordingURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("whisper_recording_\(UUID().uuidString).m4a")
    }

    func startRecording() throws {
        guard hasPermission else {
            throw RecordingError.noPermission
        }

        // Préparer le microphone sélectionné (change le défaut système)
        microphoneService.prepareForRecording()

        let url = getRecordingURL()
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000, // 16kHz recommandé pour Whisper
            AVNumberOfChannelsKey: 1, // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()
        isRecording = true
    }

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        isRecording = false

        // Restaurer le périphérique par défaut original
        microphoneService.restoreAfterRecording()

        return recordingURL
    }

    func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }

    enum RecordingError: LocalizedError {
        case noPermission
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .noPermission:
                return "Accès au microphone refusé"
            case .recordingFailed:
                return "Échec de l'enregistrement"
            }
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Enregistrement terminé avec erreur")
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Erreur d'encodage: \(error.localizedDescription)")
        }
    }
}
