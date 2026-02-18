import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var apiKeyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var showSuccessHint: Bool = false
    @State private var showErrorHint: Bool = false

    @StateObject private var microphoneService = MicrophoneService.shared

    private let accentColor = Color(nsColor: .controlAccentColor)

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    transcriptionModeSection

                    microphoneSection

                    if appState.transcriptionMode == .api {
                        apiConfigurationSection
                    }

                    if appState.transcriptionMode == .local {
                        localModelsSection
                    }

                    usageSection
                    aboutSection
                }
                .padding(24)
            }

            footerSection
        }
        .frame(width: 500, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Computed Properties

    private func isSelected(_ model: LocalModel) -> Bool {
        appState.localModelProvider.selectedModel?.id == model.id
    }

    // MARK: - Sections

    private var transcriptionModeSection: some View {
        SettingsSection(title: "MODE DE TRANSCRIPTION", icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $appState.transcriptionMode) {
                    ForEach(TranscriptionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    Image(systemName: appState.transcriptionMode == .api ? "cloud" : "cpu")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(appState.transcriptionMode == .api
                        ? "Transcription via l'API OpenAI (plus précise, nécessite Internet)"
                        : "Transcription locale (privée, fonctionne hors ligne)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var microphoneSection: some View {
        SettingsSection(title: "MICROPHONE", icon: "mic.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if microphoneService.availableDevices.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.slash")
                            .foregroundColor(.orange)
                        Text("Aucun microphone détecté")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Picker(selection: $microphoneService.selectedDevice, label: EmptyView()) {
                        ForEach(microphoneService.availableDevices) { device in
                            HStack {
                                Image(systemName: device.iconName)
                                Text(device.displayName)
                            }
                            .tag(device as MicrophoneDevice?)
                        }
                    }
                    .pickerStyle(.menu)

                    if !microphoneService.isSelectedDeviceAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Microphone déconnecté")
                                .foregroundColor(.orange)
                        }
                    }
                }

                Button(action: { microphoneService.refreshDevices() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Actualiser")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(accentColor)
            }
        }
    }

    private var apiConfigurationSection: some View {
        SettingsSection(title: "CONFIGURATION API", icon: "key.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SecureField("sk-...", text: $apiKeyInput)
                        .textFieldStyle(RefinedTextFieldStyle())
                        .frame(maxWidth: .infinity)

                    Button(action: validateKey) {
                        HStack(spacing: 6) {
                            if isValidating {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.6)
                            } else {
                                Text("Valider")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .frame(width: 70, height: 24)
                    }
                    .buttonStyle(RefinedButtonStyle(isPrimary: true))
                    .disabled(apiKeyInput.isEmpty || isValidating)
                }

                HStack(spacing: 12) {
                    statusIndicator

                    Spacer()

                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                        HStack(spacing: 4) {
                            Text("Obtenir une clé")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(accentColor.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
        }
    }

    private var localModelsSection: some View {
        SettingsSection(title: "MODÈLES LOCAUX", icon: "cpu.fill") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(appState.localModelProvider.availableModels) { model in
                    ModelRowView(
                        model: model,
                        isSelected: isSelected(model),
                        isDownloading: appState.localModelProvider.isDownloading[model.id] ?? false,
                        downloadProgress: appState.localModelProvider.downloadProgress[model.id] ?? 0,
                        errorMessage: appState.localModelProvider.downloadErrors[model.id]
                    ) {
                        // onSelect
                        appState.localModelProvider.selectModel(model)
                    } onDownload: {
                        // onDownload
                        appState.localModelProvider.downloadModel(model)
                    } onCancel: {
                        // onCancel
                        appState.localModelProvider.cancelDownload(model)
                    } onDelete: {
                        // onDelete
                        appState.localModelProvider.deleteModel(model)
                    } onRetry: {
                        // onRetry
                        appState.localModelProvider.retryDownload(model)
                    }

                    if model.id != appState.localModelProvider.availableModels.last?.id {
                        Divider()
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var usageSection: some View {
        SettingsSection(title: "UTILISATION", icon: "command") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ShortcutKeyView(label: "Fn", subLabel: "Maintenir")

                    Text("Maintenez la touche Fn enfoncée pour parler. Relâchez pour transcrire et coller le texte.")
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundColor(.secondary)
                }

                Divider().opacity(0.5)

                HStack(spacing: 12) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 14))
                        .foregroundColor(accentColor)
                        .frame(width: 24)

                    Text("Le texte transcrit sera inséré automatiquement à l'emplacement actuel de votre curseur.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "À PROPOS", icon: "info.circle") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Whisper for macOS")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Version 1.0.0")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("gpt-4o-mini-transcribe")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [accentColor, accentColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                        .shadow(color: accentColor.opacity(0.3), radius: 8, x: 0, y: 4)

                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Whisper")
                        .font(.system(size: 16, weight: .bold))
                        .kerning(-0.2)
                    Text("Préférences Système")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider().opacity(0.5)
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.hasAPIKey ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
                .shadow(color: (appState.hasAPIKey ? Color.green : Color.orange).opacity(0.4), radius: 3)

            Text(appState.hasAPIKey ? "Clé API valide" : "Clé non configurée")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if appState.hasAPIKey {
                Button(action: { appState.clearAPIKey() }) {
                    Text("Réinitialiser")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack {
                Text(appState.transcriptionMode == .api
                    ? "Whisper utilise l'API OpenAI pour une précision optimale."
                    : "L'IA locale garantit la confidentialité de vos données.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))

                Spacer()

                Button("Quitter") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(RefinedButtonStyle(isPrimary: false))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }

    // MARK: - Logic

    private func validateKey() {
        guard !apiKeyInput.isEmpty else { return }

        isValidating = true
        showErrorHint = false

        Task {
            let success = await appState.updateAPIKey(apiKeyInput)
            await MainActor.run {
                isValidating = false
                if success {
                    apiKeyInput = ""
                    showSuccessHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showSuccessHint = false }
                } else {
                    showErrorHint = true
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .kerning(0.5)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

struct ShortcutKeyView: View {
    let label: String
    let subLabel: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 1, opacity: 0.1), Color(white: 1, opacity: 0.05)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    .frame(width: 36, height: 36)

                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }

            Text(subLabel)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))
                .textCase(.uppercase)
        }
    }
}

// MARK: - Styles

struct RefinedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .font(.system(size: 12, design: .monospaced))
    }
}

struct RefinedButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isPrimary {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isPrimary ? Color.white.opacity(0.1) : Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .foregroundColor(isPrimary ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { inside in
                isHovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
