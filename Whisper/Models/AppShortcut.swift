import AppKit

struct AppShortcut: Codable, Equatable {
    var keyCode: UInt16?
    var modifiers: UInt
    var character: String?

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    init(keyCode: UInt16? = nil, modifiers: NSEvent.ModifierFlags = [], character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
        self.character = character
    }

    /// Représentation textuelle du raccourci (ex: "⌘ T", "Fn", "Espace")
    var displayString: String {
        var parts: [String] = []

        let flags = modifierFlags
        let isModifierKey = keyCode != nil && [54, 55, 56, 60, 59, 62, 58, 61, 63].contains(keyCode!)
        
        if flags.contains(.control) && (!isModifierKey || !(keyCode == 59 || keyCode == 62)) { parts.append("⌃") }
        if flags.contains(.option) && (!isModifierKey || !(keyCode == 58 || keyCode == 61)) { parts.append("⌥") }
        if flags.contains(.shift) && (!isModifierKey || !(keyCode == 56 || keyCode == 60)) { parts.append("⇧") }
        if flags.contains(.command) && (!isModifierKey || !(keyCode == 54 || keyCode == 55)) { parts.append("⌘") }

        if let keyCode = keyCode {
            if let special = specialKeyString(for: keyCode) {
                parts.append(special)
            } else if let char = character, !char.isEmpty {
                // Ignore empty characters for layout specific keys sometimes
                parts.append(char.uppercased())
            } else {
                parts.append("Touche (\(keyCode))")
            }
        } else if parts.isEmpty, flags.contains(.function) {
            parts.append("Fn")
        } else if parts.isEmpty {
            parts.append("Aucune")
        }

        return parts.joined(separator: " + ")
    }

    private func specialKeyString(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "Entrée"
        case 48: return "Tab"
        case 49: return "Espace"
        case 51: return "Effacer"
        case 53: return "Échap"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 54: return "Cmd Droit"
        case 55: return "Cmd Gauche"
        case 56: return "Shift Gauche"
        case 60: return "Shift Droit"
        case 59: return "Ctrl Gauche"
        case 62: return "Ctrl Droit"
        case 58: return "Option Gauche"
        case 61: return "Option Droit"
        case 63: return "Fn"
        default: return nil
        }
    }

    static let defaultShortcut = AppShortcut(keyCode: nil, modifiers: .function)
}
