import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var hasPermission = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private let microphoneService = MicrophoneService.shared

    override init() {
        super.init()
        checkPermission()
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.hasPermission = granted
                }
            }
        case .denied, .restricted:
            hasPermission = false
        @unknown default:
            hasPermission = false
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
