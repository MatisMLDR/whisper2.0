import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                // Also setting the titlebar transparent to let the material shine through
                window.titlebarAppearsTransparent = true
                
                // Make the window behave like a classic window (not always on screen/top)
                // and appear in Mission Control (Space manager)
                window.level = .normal
                window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
                
                // Masquer le bouton de zoom/plein écran
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
