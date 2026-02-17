import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var apiKeyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var showSuccessHint: Bool = false
    @State private var showErrorHint: Bool = false

    private let accentColor = Color(nsColor: .controlAccentColor)

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    transcriptionModeSection

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
                // Liste des modèles disponibles
                ForEach(appState.localModelProvider.availableModels) { model in
                    modelRow(model)

                    if model.id != appState.localModelProvider.availableModels.last?.id {
                        Divider()
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func modelRow(_ model: LocalModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Bouton de sélection
            Button(action: {
                guard model.isReady else { return }
                appState.localModelProvider.selectedModel = model
            }) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected(model) ? accentColor.opacity(0.2) : Color.clear)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected(model) ? accentColor : Color.primary.opacity(0.1), lineWidth: isSelected(model) ? 2 : 1)

                    if isSelected(model) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Sélectionné")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    } else if !model.isReady {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12))
                            Text("Télécharger")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "circle")
                                .font(.system(size: 12))
                            Text("Sélectionner")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .frame(height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!model.isReady)
            .opacity(model.isReady ? 1.0 : 0.6)

            // Info du modèle
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 13, weight: isSelected(model) ? .semibold : .regular))
                        .foregroundColor(isSelected(model) ? accentColor : .primary)

                    // Badge du provider
                    Text(model.providerType.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(model.providerType == .whisperKit ? Color.blue.opacity(0.2) : Color.purple.opacity(0.2))
                        .foregroundColor(model.providerType == .whisperKit ? .blue : .purple)
                        .cornerRadius(4)

                    // Badge "Téléchargé" si le modèle est prêt
                    if model.isReady {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 7))
                            Text("Téléchargé")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                    }
                }

                Text(model.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Text(model.language)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(model.fileSize)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Actions (télécharger/supprimer)
            modelActions(model)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func modelActions(_ model: LocalModel) -> some View {
        if appState.localModelProvider.isDownloading[model.id] == true {
            VStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 100, height: 8)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(accentColor)
                        .frame(width: 100 * (appState.localModelProvider.downloadProgress[model.id] ?? 0), height: 8)
                        .animation(.linear(duration: 0.1), value: appState.localModelProvider.downloadProgress[model.id])
                }

                HStack(spacing: 4) {
                    Text("\(Int((appState.localModelProvider.downloadProgress[model.id] ?? 0) * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    Button(action: {
                        appState.localModelProvider.cancelDownload(model)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if model.isReady {
            // Modèle téléchargé - bouton vert + bouton supprimer
            HStack(spacing: 6) {
                // Badge "Téléchargé" vert
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Téléchargé")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .cornerRadius(6)

                // Bouton supprimer
                Button(action: {
                    appState.localModelProvider.deleteModel(model)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        } else {
            // Bouton télécharger + erreur éventuelle
            VStack(alignment: .leading, spacing: 4) {
                Button(action: {
                    appState.localModelProvider.downloadModel(model)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 12))
                        Text("Télécharger")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(RefinedButtonStyle(isPrimary: true))

                // Afficher l'erreur si présente
                if let error = appState.localModelProvider.errorMessage ??
                               LocalModelManager.shared.downloadError[model.id] {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Button("Réessayer") {
                            LocalModelManager.shared.downloadError[model.id] = nil
                            appState.localModelProvider.downloadModel(model)
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundColor(accentColor)
                    }
                    .frame(width: 120)
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
