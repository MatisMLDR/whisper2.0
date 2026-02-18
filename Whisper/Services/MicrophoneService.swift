import AVFoundation
import Combine
import CoreAudio
import Foundation

@MainActor
final class MicrophoneService: ObservableObject {
    static let shared = MicrophoneService()

    // MARK: - Published Properties

    @Published private(set) var availableDevices: [MicrophoneDevice] = []
    @Published var selectedDevice: MicrophoneDevice? {
        didSet {
            saveSelectedDevice()
            updateSelectedDeviceAvailability()
        }
    }
    @Published private(set) var isSelectedDeviceAvailable: Bool = true

    // MARK: - Private Properties

    private var originalDefaultInputDeviceID: AudioDeviceID?
    private let userDefaultsKey = "selectedMicrophoneID"

    // MARK: - Initialization

    private init() {
        refreshDevices()
        loadSelectedDevice()
        observeDeviceChanges()
    }

    // MARK: - Public Methods

    /// Rafraîchit la liste des microphones disponibles
    func refreshDevices() {
        var devices: [MicrophoneDevice] = []

        // Utiliser AVCaptureDevice pour énumérer les périphériques audio
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        for captureDevice in discoverySession.devices {
            if let audioDeviceID = getAudioDeviceID(for: captureDevice.uniqueID) {
                let device = MicrophoneDevice(
                    id: captureDevice.uniqueID,
                    name: captureDevice.localizedName,
                    manufacturer: captureDevice.manufacturer ?? "Inconnu",
                    isBuiltIn: captureDevice.modelID.contains("BuiltIn"),
                    audioDeviceID: audioDeviceID
                )
                devices.append(device)
            }
        }

        // Trier: micros internes d'abord, puis par nom
        devices.sort { device1, device2 in
            if device1.isBuiltIn != device2.isBuiltIn {
                return device1.isBuiltIn
            }
            return device1.name < device2.name
        }

        availableDevices = devices
        updateSelectedDeviceAvailability()

        // Si aucun périphérique sélectionné, prendre le premier disponible
        if selectedDevice == nil, let firstDevice = devices.first {
            selectedDevice = firstDevice
        }
    }

    /// Prépare l'enregistrement en changeant temporairement le périphérique par défaut
    /// - Returns: true si la préparation a réussi
    @discardableResult
    func prepareForRecording() -> Bool {
        // Sauvegarder le périphérique par défaut actuel
        originalDefaultInputDeviceID = getCurrentDefaultInputDeviceID()

        // Si un périphérique spécifique est sélectionné et disponible
        guard let device = selectedDevice,
              isSelectedDeviceAvailable else {
            return true // Utiliser le défaut système
        }

        // Trouver le périphérique dans la liste actuelle (peut avoir changé)
        if let currentDevice = availableDevices.first(where: { $0.id == device.id }) {
            let success = setDefaultInputDevice(currentDevice.audioDeviceID)
            if !success {
                print("MicrophoneService: Impossible de définir le périphérique par défaut")
            }
            return success
        }

        return true
    }

    /// Restaure le périphérique par défaut original après l'enregistrement
    func restoreAfterRecording() {
        guard let originalID = originalDefaultInputDeviceID else { return }

        let success = setDefaultInputDevice(originalID)
        if !success {
            print("MicrophoneService: Impossible de restaurer le périphérique par défaut")
        }

        originalDefaultInputDeviceID = nil
    }

    // MARK: - Private Methods

    private func loadSelectedDevice() {
        guard let savedID = UserDefaults.standard.string(forKey: userDefaultsKey) else {
            return
        }

        // Chercher le périphérique sauvegardé dans la liste actuelle
        if let device = availableDevices.first(where: { $0.id == savedID }) {
            selectedDevice = device
        } else {
            // Le périphérique n'est plus disponible, mais on garde la référence
            // pour pouvoir le rétablir s'il reconnecte
            isSelectedDeviceAvailable = false
        }
    }

    private func saveSelectedDevice() {
        if let device = selectedDevice {
            UserDefaults.standard.set(device.id, forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }

    private func updateSelectedDeviceAvailability() {
        guard let device = selectedDevice else {
            isSelectedDeviceAvailable = true
            return
        }

        isSelectedDeviceAvailable = availableDevices.contains { $0.id == device.id }
    }

    private func observeDeviceChanges() {
        // Observer les changements de périphériques audio
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceChange),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceChange),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
    }

    @objc private func handleDeviceChange() {
        Task { @MainActor in
            refreshDevices()
        }
    }

    // MARK: - CoreAudio Helpers

    /// Récupère l'AudioDeviceID à partir de l'uniqueID AVCaptureDevice
    private func getAudioDeviceID(for uniqueID: String) -> UInt32? {
        // Obtenir le nombre de périphériques
        var propertySize: UInt32 = 0
        var status: OSStatus

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )

        guard status == noErr else { return nil }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        guard status == noErr else { return nil }

        // Chercher le périphérique avec l'UID correspondant
        for deviceID in deviceIDs {
            if let deviceUID = getDeviceUID(deviceID),
               deviceUID == uniqueID {
                return deviceID
            }
        }

        return nil
    }

    /// Récupère l'UID d'un périphérique CoreAudio
    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var propertySize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &uid
        )

        guard status == noErr, let uid = uid else { return nil }

        return uid as String
    }

    /// Récupère l'ID du périphérique d'entrée par défaut actuel
    private func getCurrentDefaultInputDeviceID() -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        return status == noErr ? deviceID : 0
    }

    /// Définit le périphérique d'entrée par défaut
    private func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceID = deviceID
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            propertySize,
            &mutableDeviceID
        )

        return status == noErr
    }
}
