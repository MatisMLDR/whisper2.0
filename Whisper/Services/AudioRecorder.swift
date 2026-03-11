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

    /// Niveau audio normalisé (0…1) mis à jour ~30 fps
    @Published private(set) var audioLevel: Float = 0

    /// Historique des niveaux audio pour la waveform (buffer circulaire, ~40 valeurs)
    @Published private(set) var audioLevelHistory: [Float] = Array(repeating: 0, count: 40)

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private let microphoneService = MicrophoneService.shared
    private var meteringTimer: Timer?
    private static let historySize = 40

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
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.delegate = self
        audioRecorder?.record()
        isRecording = true

        startMeteringTimer()
    }

    func stopRecording() -> URL? {
        stopMeteringTimer()

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

    // MARK: - Metering

    private func startMeteringTimer() {
        audioLevel = 0
        audioLevelHistory = Array(repeating: 0, count: Self.historySize)

        meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetering()
            }
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        audioLevel = 0
        audioLevelHistory = Array(repeating: 0, count: Self.historySize)
    }

    private func updateMetering() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()
        let dB = recorder.averagePower(forChannel: 0) // -160…0 dB

        // Normaliser dB en 0…1 (on considère -50 dB comme le silence)
        let minDB: Float = -50.0
        let normalized = max(0, min(1, (dB - minDB) / (-minDB)))

        audioLevel = normalized

        // Ajouter dans l'historique (buffer circulaire)
        audioLevelHistory.append(normalized)
        if audioLevelHistory.count > Self.historySize {
            audioLevelHistory.removeFirst()
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
