import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard
            profilesSection
            microphoneSection

            if let blockingIssue = appState.blockingIssue,
               !appState.isRecording,
               !appState.isTranscribing {
                WhisperInlineNotice(
                    title: "Action requise",
                    message: blockingIssue,
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }

            if appState.hasHistoryEntries {
                recentHistorySection
            }

            actionSection
        }
        .padding(16)
        .frame(width: 336)
        .onAppear {
            appState.refreshMicrophones()
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: appState.statusIconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusTint)
                .frame(width: 36, height: 36)
                .background(statusTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Whisper")
                    .font(.headline)

                Text(appState.activeProfileName)
                    .font(.subheadline.weight(.semibold))

                Text(appState.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            profilesHeader
            profilesList

            if let currentModeConfigurationIssue = appState.currentModeConfigurationIssue {
                Text(currentModeConfigurationIssue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Historique récent")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Voir tout") {
                    activateAndOpenWindow(.history, with: openWindow)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(appState.recentHistoryEntries) { entry in
                    Button {
                        appState.copyToPasteboard(entry.text)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                Text(relativeDate(entry.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Microphone")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    appState.refreshMicrophones()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Actualiser la liste")
            }

            Menu {
                Button {
                    appState.selectMicrophone(nil)
                } label: {
                    microphoneMenuItem(
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
                        microphoneMenuItem(
                            title: device.displayName,
                            symbol: device.iconName,
                            isSelected: appState.microphoneService.selectedDevice?.id == device.id
                        )
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: currentMicrophoneIconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.selectedMicrophoneSummary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Choisir le micro utilisé")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)

            if !appState.microphoneService.isSelectedDeviceAvailable {
                Text("Le dernier micro choisi n’est plus disponible. Le système utilisera le micro par défaut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if appState.availableMicrophones.isEmpty {
                Text("Aucun microphone détecté pour le moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionSection: some View {
        VStack(spacing: 8) {
            Button {
                activateAndOpenWindow(.settings, with: openWindow)
            } label: {
                Label("Réglages", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(",", modifiers: .command)

            Button {
                activateAndOpenWindow(.history, with: openWindow)
            } label: {
                Label("Historique", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quitter", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: .command)
        }
        .controlSize(.large)
    }

    private var profilesHeader: some View {
        HStack {
            Text("Profils")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Gérer") {
                activateAndOpenWindow(.settings, with: openWindow)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var profilesList: some View {
        VStack(spacing: 8) {
            ForEach(appState.profiles) { profile in
                profileButton(profile)
            }
        }
    }

    private func profileButton(_ profile: Profile) -> some View {
        let isActive = appState.activeProfileId == profile.id

        return Button {
            appState.setActiveProfile(id: profile.id)
        } label: {
            ProfileMenuRow(
                title: profile.name,
                subtitle: appState.profileSummary(for: profile),
                isActive: isActive,
                backgroundColor: rowBackground(isActive: isActive)
            )
        }
        .buttonStyle(.plain)
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

        return .green
    }

    private func rowBackground(isActive: Bool) -> Color {
        isActive ? Color.accentColor.opacity(0.08) : Color(nsColor: .windowBackgroundColor)
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

    private func microphoneMenuItem(title: String, symbol: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 16)

            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct WhisperInlineNotice: View {
    let title: String
    let message: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ProfileMenuRow: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    let backgroundColor: Color

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
        }
        .padding(10)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
