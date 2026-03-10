import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard
            modeSection

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
        .frame(width: 320)
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

                Text(appState.statusTitle)
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

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mode")
                .font(.subheadline.weight(.semibold))

            Picker("Mode", selection: Binding(
                get: { appState.transcriptionMode },
                set: { appState.setTranscriptionMode($0) }
            )) {
                Text("Local").tag(TranscriptionMode.local)
                Text("Clé API").tag(TranscriptionMode.api)
            }
            .pickerStyle(.segmented)

            Text(modeSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let modeActionTitle {
                Button(modeActionTitle) {
                    activateAndOpenWindow(.settings, with: openWindow)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
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
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

    private var modeSummaryText: String {
        if let currentModeConfigurationIssue = appState.currentModeConfigurationIssue {
            return currentModeConfigurationIssue
        }

        return appState.providerSummary
    }

    private var modeActionTitle: String? {
        switch appState.transcriptionMode {
        case .api:
            return appState.hasAPIKey ? nil : "Configurer une clé API"
        case .local:
            return (appState.localModelProvider.selectedModel?.isReady ?? false) ? nil : "Choisir un modèle local"
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

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
