import AppKit
import Foundation

final class KeyboardService: ObservableObject {
    @Published private(set) var isMonitoring = false
    
    // The configured modifier flag to monitor (e.g. .function, .command, etc.)
    var modifierFlag: NSEvent.ModifierFlags = .function

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isModifierPressed = false

    /// Appelé quand la touche configurée est pressée (début enregistrement)
    var onModifierPressed: (() -> Void)?
    /// Appelé quand la touche configurée est relâchée (fin enregistrement)
    var onModifierReleased: (() -> Void)?

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Monitor global (quand l'app n'est pas au premier plan)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Monitor local (quand l'app est au premier plan)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        isMonitoring = true
    }

    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isMonitoring = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let modifierKeyPressed = event.modifierFlags.contains(modifierFlag)

        // La touche vient d'être pressée
        if modifierKeyPressed && !isModifierPressed {
            isModifierPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.onModifierPressed?()
            }
        }
        // La touche vient d'être relâchée
        else if !modifierKeyPressed && isModifierPressed {
            isModifierPressed = false
            DispatchQueue.main.async { [weak self] in
                self?.onModifierReleased?()
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
