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
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
