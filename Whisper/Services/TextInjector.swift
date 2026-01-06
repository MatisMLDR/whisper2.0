import AppKit
import Carbon.HIToolbox

final class TextInjector {
    static let shared = TextInjector()
    private init() {}

    /// L'app qui avait le focus quand l'enregistrement a commencé
    private var targetApp: NSRunningApplication?

    /// Capture l'app frontale actuelle (à appeler au début de l'enregistrement)
    func captureTargetApp() {
        targetApp = NSWorkspace.shared.frontmostApplication
    }

    /// Injecte le texte à la position actuelle du curseur via CGEvent
    func inject(text: String) {
        // Sauvegarder le contenu actuel du presse-papiers
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Mettre le texte transcrit dans le presse-papiers
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // S'assurer que l'app cible a le focus
        if let app = targetApp {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        // Délai pour s'assurer que l'app est vraiment active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.pasteViaCGEvent()

            // Restaurer le presse-papiers après un délai
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
                self.targetApp = nil
            }
        }
    }

    private func pasteViaCGEvent() {
        // CGEvent ne fonctionne pas bien sur macOS récent, utiliser AppleScript
        pasteViaAppleScript()
    }

    private func pasteViaAppleScript() {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }

        if error != nil {
            // Fallback: via le menu Edit > Paste de l'app frontale
            pasteViaMenuClick()
        }
    }

    private func pasteViaMenuClick() {
        guard let appName = targetApp?.localizedName else { return }

        let script = """
        tell application "\(appName)"
            activate
        end tell
        delay 0.1
        tell application "System Events"
            tell process "\(appName)"
                click menu item "Paste" of menu "Edit" of menu bar 1
            end tell
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Vérifie si l'app a les permissions d'accessibilité
    static func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Demande les permissions d'accessibilité
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
