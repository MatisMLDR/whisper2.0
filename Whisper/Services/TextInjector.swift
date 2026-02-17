import AppKit
import Carbon.HIToolbox

final class TextInjector {
    static let shared = TextInjector()
    private init() {}

    /// Injecte le texte à la position actuelle du curseur
    func inject(text: String) {
        guard !text.isEmpty else { return }

        // 1. Vérifier les permissions d'accessibilité
        guard Self.hasAccessibilityPermission() else {
            print("❌ TextInjector: Permission d'accessibilité manquante")
            Self.requestAccessibilityPermission()
            return
        }

        // 2. Capturer l'application frontale ACTUELLE (pas celle au début de l'enregistrement)
        guard let targetApp = NSWorkspace.shared.frontmostApplication else {
            print("❌ TextInjector: Aucune application frontale détectée")
            return
        }

        print("✅ TextInjector: App cible = \(targetApp.localizedName ?? "Unknown")")

        // 3. Sauvegarder le contenu actuel du presse-papiers
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // 4. Mettre le texte transcrit dans le presse-papiers
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 5. Activer l'app cible
        targetApp.activate(options: [.activateIgnoringOtherApps])

        // 6. Attendre que l'app soit vraiment active (augmenté à 0.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Vérifier que l'app est toujours frontale
            guard let currentApp = NSWorkspace.shared.frontmostApplication,
                  currentApp.bundleIdentifier == targetApp.bundleIdentifier else {
                print("⚠️ TextInjector: L'app cible n'est plus active")
                // Restaurer le presse-papiers quand même
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
                return
            }

            // 7. Coller le texte
            self?.pasteText()

            // 8. Restaurer le presse-papiers après un délai
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
                print("✅ TextInjector: Presse-papiers restauré")
            }
        }
    }

    private func pasteText() {
        // Méthode 1: AppleScript avec Cmd+V
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)

        if let result = appleScript?.executeAndReturnError(&error),
           error == nil {
            print("✅ TextInjector: Collé via AppleScript")
            return
        }

        if let error = error {
            print("⚠️ TextInjector: AppleScript échoué - \(error)")
        }

        // Méthode 2: Fallback par menu click
        pasteViaMenuClick()
    }

    private func pasteViaMenuClick() {
        guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName else {
            print("❌ TextInjector: Impossible de faire fallback - pas d'app nom")
            return
        }

        let script = """
        tell application "\(appName)"
            activate
        end tell
        delay 0.3
        tell application "System Events"
            tell process "\(appName)"
                click menu item "Paste" of menu "Edit" of menu bar 1
            end tell
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if error == nil {
                print("✅ TextInjector: Collé via menu click")
            } else {
                print("❌ TextInjector: Fallback échoué - \(error ?? [:])")
            }
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
