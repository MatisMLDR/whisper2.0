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
    /// Appelé quand la touche Échap est pressée (annuler enregistrement)
    var onEscapePressed: (() -> Void)?

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
            // Détecter la touche Échap (keyCode 53)
            if event.type == .keyDown && event.keyCode == 53 {
                DispatchQueue.main.async { [weak self] in
                    self?.onEscapePressed?()
                }
                return
            }
            pressedKeyCodes.insert(event.keyCode)
        } else if event.type == .keyUp {
            pressedKeyCodes.remove(event.keyCode)
        } else if event.type == .flagsChanged {
            pressedModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            
            // Pour différencier les touches modifier gauche et droite, on vérifie leur état via les flags de bas niveau
            let isPressed: Bool
            let flags = event.modifierFlags.rawValue
            switch event.keyCode {
            case 54: isPressed = (flags & 0x00000010) != 0 // Right Command
            case 55: isPressed = (flags & 0x00000008) != 0 // Left Command
            case 56: isPressed = (flags & 0x00000002) != 0 // Left Shift
            case 60: isPressed = (flags & 0x00000004) != 0 // Right Shift
            case 58: isPressed = (flags & 0x00000020) != 0 // Left Option
            case 61: isPressed = (flags & 0x00000040) != 0 // Right Option
            case 59: isPressed = (flags & 0x00000001) != 0 // Left Control
            case 62: isPressed = (flags & 0x00002000) != 0 // Right Control
            case 63: isPressed = event.modifierFlags.contains(.function) // Fn
            default: isPressed = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(event.keyCode))
            }
            
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
