import AppKit
import SwiftUI

enum AppWindowID: String {
    case settings
    case history
}

func activateAndOpenWindow(_ id: AppWindowID, with openWindow: OpenWindowAction) {
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: id.rawValue)
}

@main
struct WhisperApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)
        .commands {
            WhisperCommands()
        }

        Window("Réglages", id: AppWindowID.settings.rawValue) {
            SettingsView()
                .environmentObject(appState)
                // Appliquer un fond transparent au niveau de la fenêtre macOS
                .background(WindowAccessor())
        }
        .defaultSize(width: 750, height: 450)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

        Window("Historique", id: AppWindowID.history.rawValue) {
            HistoryView()
                .environmentObject(appState)
                .background(WindowAccessor())
        }
        .defaultSize(width: 560, height: 540)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        if appState.isTranscribing {
            Image(systemName: appState.menuBarIconName)
                .symbolEffect(.pulse)
        } else if appState.isRecording {
            Image(systemName: appState.menuBarIconName)
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(.red)
        } else if appState.blockingIssue != nil {
            Image(systemName: appState.menuBarIconName)
                .foregroundStyle(.orange)
        } else {
            Image(systemName: appState.menuBarIconName)
        }
    }
}

private struct WhisperCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Réglages…") {
                activateAndOpenWindow(.settings, with: openWindow)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
