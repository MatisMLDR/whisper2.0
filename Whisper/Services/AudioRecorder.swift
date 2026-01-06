import AVFoundation
import Foundation

final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var hasPermission = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

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
                DispatchQueue.main.async {
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
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Enregistrement terminé avec erreur")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Erreur d'encodage: \(error.localizedDescription)")
        }
    }
}
