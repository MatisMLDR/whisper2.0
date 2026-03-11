import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayWindow {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    func show(appState: AppState) {
        if panel != nil {
            panel?.orderFront(nil)
            return
        }

        let overlayView = RecordingOverlayView()
            .environmentObject(appState)

        let hostingView = NSHostingView(rootView: AnyView(overlayView))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView = hostingView

        // Calculer la taille intrinsèque
        let fittingSize = hostingView.fittingSize
        let panelWidth = max(fittingSize.width, 480)
        let panelHeight = max(fittingSize.height, 120)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        panel.contentView = hostingView

        // Positionner en bas au centre de l'écran principal
        positionPanel(panel, width: panelWidth, height: panelHeight)

        self.panel = panel

        // Afficher avec fade in
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.hostingView = nil
        })
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private func positionPanel(_ panel: NSPanel, width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        // 60pt au-dessus du bas de la zone visible (au-dessus du Dock)
        let y = screenFrame.origin.y + 60

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
