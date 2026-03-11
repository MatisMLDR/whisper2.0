import AppKit
import Foundation

final class KeyboardService: ObservableObject {
    @Published private(set) var isMonitoring = false
    
    var shortcut: AppShortcut = .defaultShortcut

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isShortcutPressed = false

    private var pressedKeyCodes: Set<UInt16> = []
    private var pressedModifiers: NSEvent.ModifierFlags = []

    /// Appelé quand le raccourci configuré est pressé (début enregistrement)
    var onModifierPressed: (() -> Void)?
    /// Appelé quand le raccourci configuré est relâché (fin enregistrement)
    var onModifierReleased: (() -> Void)?

    func startMonitoring() {
        guard !isMonitoring else { return }

        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
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
        pressedKeyCodes.removeAll()
        pressedModifiers = []
        isShortcutPressed = false
    }

    private func handleEvent(_ event: NSEvent) {
        if event.type == .keyDown || event.type == .systemDefined {
            pressedKeyCodes.insert(event.keyCode)
        } else if event.type == .keyUp {
            pressedKeyCodes.remove(event.keyCode)
        } else if event.type == .flagsChanged {
            pressedModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            
            // Pour différencier les touches modifier gauche et droite, on vérifie leur état physique
            let isPressed = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(event.keyCode))
            if isPressed {
                pressedKeyCodes.insert(event.keyCode)
            } else {
                pressedKeyCodes.remove(event.keyCode)
            }
        }

        checkShortcutState()
    }

    private func checkShortcutState() {
        let isMatch: Bool

        if let keyCode = shortcut.keyCode {
            // Uniquement vrai si la touche voulue est pressée ET les bons modifiers sont appliqués
            isMatch = pressedKeyCodes.contains(keyCode) && pressedModifiers == shortcut.modifierFlags
        } else {
            // S'il n'y a pas de touche spéciale requise (uniquement des modifiers, ex: Fn)
            isMatch = pressedModifiers == shortcut.modifierFlags && pressedModifiers.rawValue != 0
        }

        if isMatch && !isShortcutPressed {
            isShortcutPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.onModifierPressed?()
            }
        } else if !isMatch && isShortcutPressed {
            isShortcutPressed = false
            DispatchQueue.main.async { [weak self] in
                self?.onModifierReleased?()
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
