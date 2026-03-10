import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuContainer {
            VStack(spacing: 0) {
                if let statusMessage {
                    MenuRowLabel(
                        title: statusMessage,
                        symbol: appState.statusIconName,
                        tint: statusTint,
                        multiline: true
                    )

                    menuDivider
                }

                menuActionButton(
                    title: "Historique…",
                    symbol: "clock.arrow.circlepath"
                ) {
                    activateAndOpenWindow(.history, with: openWindow)
                }

                menuActionButton(
                    title: "Réglages…",
                    symbol: "gearshape",
                    shortcut: "⌘,"
                ) {
                    activateAndOpenWindow(.settings, with: openWindow)
                }

                menuDivider

                microphoneMenuRow
                profileMenuRow

                menuDivider

                versionRow

                menuActionButton(
                    title: "Quitter Whisper",
                    symbol: "power",
                    shortcut: "⌘Q"
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(6)
        .frame(width: 312)
        .onAppear {
            appState.refreshMicrophones()
        }
    }

    private var microphoneMenuRow: some View {
        Menu {
            Button {
                appState.selectMicrophone(nil)
            } label: {
                menuChoiceItem(
                    title: "Micro par défaut du système",
                    symbol: "slider.horizontal.3",
                    isSelected: appState.microphoneService.selectedDevice == nil
                )
            }

            if !appState.availableMicrophones.isEmpty {
                Divider()
            }

            ForEach(appState.availableMicrophones) { device in
                Button {
                    appState.selectMicrophone(device)
                } label: {
                    menuChoiceItem(
                        title: device.displayName,
                        symbol: device.iconName,
                        isSelected: appState.microphoneService.selectedDevice?.id == device.id
                    )
                }
            }
        } label: {
            MenuRowLabel(
                title: microphoneMenuValue,
                symbol: currentMicrophoneIconName,
                hasSubmenu: true
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileMenuRow: some View {
        Menu {
            ForEach(appState.profiles) { profile in
                Button {
                    appState.setActiveProfile(id: profile.id)
                } label: {
                    menuChoiceItem(
                        title: profile.name,
                        symbol: profile.transcriptionMode.iconName,
                        isSelected: appState.activeProfileId == profile.id
                    )
                }
            }
        } label: {
            MenuRowLabel(
                title: appState.activeProfileName,
                symbol: appState.transcriptionMode.iconName,
                hasSubmenu: true
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var versionRow: some View {
        MenuRowLabel(
            title: appVersionString,
            symbol: nil,
            tint: .secondary,
            titleColor: .secondary
        )
    }

    private var menuDivider: some View {
        Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }

    private var statusMessage: String? {
        if appState.isTranscribing {
            return "Transcription en cours"
        }

        if appState.isRecording {
            return "Enregistrement en cours"
        }

        if let currentModeConfigurationIssue = appState.currentModeConfigurationIssue {
            return currentModeConfigurationIssue
        }

        return appState.blockingIssue
    }

    private var appVersionString: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Version \(shortVersion)"
    }

    private var statusTint: Color {
        if appState.isTranscribing {
            return .blue
        }

        if appState.isRecording {
            return .red
        }

        if appState.currentModeConfigurationIssue != nil {
            return .secondary
        }

        if appState.blockingIssue != nil {
            return .orange
        }

        return .secondary
    }

    private var currentMicrophoneIconName: String {
        if let selectedDevice = appState.microphoneService.selectedDevice,
           appState.microphoneService.isSelectedDeviceAvailable {
            return selectedDevice.iconName
        }

        if !appState.microphoneService.isSelectedDeviceAvailable {
            return "mic.slash"
        }

        return "slider.horizontal.3"
    }

    private var microphoneMenuValue: String {
        if appState.availableMicrophones.isEmpty {
            return "Aucun"
        }

        if !appState.microphoneService.isSelectedDeviceAvailable {
            return "Indisponible"
        }

        if appState.microphoneService.selectedDevice == nil {
            return "Système"
        }

        return appState.selectedMicrophoneSummary
    }

    private func menuActionButton(
        title: String,
        symbol: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MenuRowLabel(
                title: title,
                symbol: symbol,
                trailingText: shortcut
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menuChoiceItem(title: String, symbol: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

private struct MenuContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private struct MenuRowLabel: View {
    let title: String
    let symbol: String?
    var tint: Color = .primary
    var titleColor: Color = .primary
    var trailingText: String? = nil
    var hasSubmenu: Bool = false
    var multiline: Bool = false

    var body: some View {
        HStack(alignment: multiline ? .top : .center, spacing: 10) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tint)
                } else {
                    Color.clear
                }
            }
            .frame(width: 18)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(titleColor)
                .lineLimit(multiline ? 3 : 1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
