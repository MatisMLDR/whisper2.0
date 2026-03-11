import SwiftUI
import AppKit

struct ShortcutRecordingView: View {
    @Binding var shortcut: AppShortcut
    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var maxModifiers: NSEvent.ModifierFlags = []
    @State private var maxModifierKeyCode: UInt16? = nil

    var body: some View {
        Button(action: {
            startRecording()
        }) {
            HStack {
                Text(isRecording ? "Appuyez sur une touche..." : shortcut.displayString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isRecording ? .blue : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.blue : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { _, newValue in
            if !newValue {
                stopRecording()
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        
        maxModifiers = []
        maxModifierKeyCode = nil
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            
            if event.type == .keyDown {
                // If Escape is pressed alone, we cancel the recording without modifying the existing shortcut
                if event.keyCode == 53 && modifiers.isEmpty { // 53 = Echap
                    self.isRecording = false
                    return nil
                }
                
                let character = event.charactersIgnoringModifiers
                self.shortcut = AppShortcut(keyCode: event.keyCode, modifiers: modifiers, character: character)
                self.isRecording = false
                return nil
            } else if event.type == .flagsChanged {
                if modifiers.rawValue > maxModifiers.rawValue {
                    maxModifiers = modifiers
                    maxModifierKeyCode = event.keyCode
                }
                
                // If modifiers are being released and we saw some
                if modifiers.rawValue == 0 && maxModifiers.rawValue != 0 {
                    self.shortcut = AppShortcut(keyCode: maxModifierKeyCode, modifiers: maxModifiers, character: nil)
                    self.isRecording = false
                    return nil
                }
                
                return nil // Consume event to avoid system ding
            }
            return event
        }
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
