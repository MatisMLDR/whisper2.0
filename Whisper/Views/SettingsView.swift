import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var selection: SettingsPane? = .profiles
    @State private var apiKeyInput = ""
    @State private var isValidating = false
    @State private var apiFeedback: APIValidationFeedback = .idle

    private var currentPane: SettingsPane {
        selection ?? .profiles
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.iconName)
                    .tag(Optional(pane))
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        paneContent
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 920, minHeight: 620)
        .onAppear {
            appState.refreshUIState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshUIState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(currentPane.title)
                .font(.title2.weight(.semibold))

            Text(currentPane.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let blockingIssue = appState.blockingIssue,
               !appState.isRecording,
               !appState.isTranscribing {
                SettingsNotice(
                    title: "À finaliser",
                    message: blockingIssue,
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch currentPane {
        case .profiles:
            profilesPane
        case .general:
            generalPane
        case .transcription:
            transcriptionPane
        case .models:
            modelsPane
        case .permissions:
            permissionsPane
        }
    }

    private var profilesPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "Profils", systemImage: "person.crop.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appState.profiles) { profile in
                        ProfileRow(
                            title: profile.name,
                            subtitle: appState.profileSummary(for: profile),
                            isActive: appState.activeProfileId == profile.id
                        ) {
                            appState.setActiveProfile(id: profile.id)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Nouveau profil") {
                            appState.createProfile()
                        }
                        .buttonStyle(.borderedProminent)

                        if appState.profileService.canDeleteProfiles,
                           let activeProfileId = appState.activeProfileId {
                            Button("Supprimer le profil actif", role: .destructive) {
                                appState.deleteProfile(id: activeProfileId)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if let activeProfile = appState.activeProfile {
                SettingsCard(title: "Profil actif", systemImage: activeProfile.transcriptionMode.iconName) {
                    LabeledContent("Nom") {
                        TextField("Nom du profil", text: activeProfileNameBinding(activeProfile.id))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }
                    .font(.subheadline)

                    LabeledContent("IA") {
                        Picker(
                            "IA",
                            selection: activeProfileModeBinding(activeProfile.id)
                        ) {
                            Text("Local").tag(TranscriptionMode.local)
                            Text("Clé API").tag(TranscriptionMode.api)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    .font(.subheadline)

                    if activeProfile.transcriptionMode == .local {
                        LabeledContent("Modèle local") {
                            Picker(
                                "Modèle local",
                                selection: activeProfileModelBinding(activeProfile.id)
                            ) {
                                Text("Choisir").tag(Optional<String>.none)
                                ForEach(appState.localModelProvider.availableModels) { model in
                                    Text(localModelPickerLabel(model)).tag(Optional(model.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 260)
                        }
                        .font(.subheadline)

                        if let currentModeConfigurationIssue = appState.currentModeConfigurationIssue {
                            SettingsNotice(
                                title: "Profil local incomplet",
                                message: currentModeConfigurationIssue,
                                symbol: "externaldrive.badge.exclamationmark",
                                tint: .orange
                            )
                        }
                    } else {
                        SettingsNotice(
                            title: appState.hasAPIKey ? "Clé API prête" : "Clé API requise",
                            message: appState.hasAPIKey
                                ? "Tous les profils en mode Clé API utiliseront la clé OpenAI enregistrée sur ce Mac."
                                : "Aucune clé API n’est configurée pour les profils Cloud.",
                            symbol: appState.hasAPIKey ? "checkmark.circle.fill" : "key.fill",
                            tint: appState.hasAPIKey ? .green : .orange
                        )

                        if !appState.hasAPIKey {
                            Button("Configurer la clé API") {
                                selection = .transcription
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "État", systemImage: "checkmark.circle") {
                SettingsFactRow(label: "Whisper", value: appState.statusTitle)
                SettingsFactRow(label: "Profil actif", value: appState.activeProfileName)
                SettingsFactRow(label: "IA active", value: appState.providerSummary)
                SettingsFactRow(label: "Microphone", value: appState.selectedMicrophoneSummary)
                SettingsFactRow(
                    label: "Historique",
                    value: appState.hasHistoryEntries ? "\(appState.historyService.entries.count) éléments sur 24 h" : "Aucune transcription"
                )
            }

            SettingsCard(title: "Utilisation", systemImage: "command") {
                HStack(alignment: .top, spacing: 14) {
                    ShortcutKeyView(label: "Fn", subLabel: "Maintenir")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Maintiens Fn pour dicter. Le profil actif détermine l’IA utilisée au moment où tu relâches la touche.")
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Choisis rapidement un autre profil depuis l’icône de barre de menus, puis dicte sans rouvrir les réglages.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                }
            }

            SettingsCard(title: "Profil actif", systemImage: "person.crop.circle.badge.checkmark") {
                SettingsFactRow(label: "Nom", value: appState.activeProfileName)
                SettingsFactRow(label: "Mode", value: appState.transcriptionMode.title)
                SettingsFactRow(label: "Résumé", value: appState.activeModeSummary)
            }
        }
    }

    private var transcriptionPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "Clé API OpenAI", systemImage: "key") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tous les profils en mode Clé API utiliseront cette clé.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        SecureField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            validateKey()
                        } label: {
                            if isValidating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Valider")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                    }

                    SettingsFactRow(label: "État", value: appState.hasAPIKey ? "Clé configurée" : "Aucune clé API")

                    if case .success(let message) = apiFeedback {
                        SettingsNotice(title: "Clé enregistrée", message: message, symbol: "checkmark.circle.fill", tint: .green)
                    }

                    if case .failure(let message) = apiFeedback {
                        SettingsNotice(title: "Validation impossible", message: message, symbol: "xmark.circle.fill", tint: .red)
                    }

                    HStack(spacing: 12) {
                        Link("Gérer mes clés OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)

                        if appState.hasAPIKey {
                            Button("Réinitialiser") {
                                appState.clearAPIKey()
                                apiFeedback = .idle
                            }
                        }
                    }
                }
            }
        }
    }

    private var modelsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsNotice(
                title: "Bibliothèque locale",
                message: "Les profils en mode Local pointeront vers les modèles gérés ici. Sélectionner un modèle l’assigne au profil actif.",
                symbol: "info.circle.fill",
                tint: .blue
            )

            SettingsCard(title: "Modèles locaux", systemImage: "shippingbox") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appState.localModelProvider.availableModels) { model in
                        ModelRowView(
                            model: model,
                            isSelected: appState.activeProfile?.selectedLocalModelId == model.id,
                            isDownloading: appState.localModelProvider.isDownloading[model.id] ?? false,
                            downloadProgress: appState.localModelProvider.downloadProgress[model.id] ?? 0,
                            errorMessage: appState.localModelProvider.downloadErrors[model.id]
                        ) {
                            guard let activeProfileId = appState.activeProfileId else { return }
                            appState.updateProfileMode(.local, for: activeProfileId)
                            appState.updateProfileLocalModel(model.id, for: activeProfileId)
                        } onDownload: {
                            appState.localModelProvider.downloadModel(model)
                        } onCancel: {
                            appState.localModelProvider.cancelDownload(model)
                        } onDelete: {
                            appState.localModelProvider.deleteModel(model)
                        } onRetry: {
                            appState.localModelProvider.retryDownload(model)
                        }
                    }
                }
            }
        }
    }

    private var permissionsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "Microphone", systemImage: "mic") {
                PermissionRow(
                    title: "Accès au micro",
                    message: microphonePermissionMessage,
                    isGranted: appState.audioRecorder.permissionStatus == .authorized,
                    primaryActionTitle: microphonePrimaryActionTitle,
                    primaryAction: handleMicrophonePrimaryAction,
                    secondaryActionTitle: microphoneSecondaryActionTitle,
                    secondaryAction: microphoneSecondaryAction
                )
            }

            SettingsCard(title: "Accessibilité", systemImage: "keyboard") {
                PermissionRow(
                    title: "Collage automatique",
                    message: accessibilityPermissionMessage,
                    isGranted: appState.hasAccessibilityPermission,
                    primaryActionTitle: appState.hasAccessibilityPermission ? "Actualiser" : "Autoriser l’accessibilité",
                    primaryAction: {
                        if appState.hasAccessibilityPermission {
                            appState.refreshUIState()
                        } else {
                            appState.requestAccessibilityPermission()
                        }
                    },
                    secondaryActionTitle: appState.hasAccessibilityPermission ? nil : "Ouvrir Réglages Système",
                    secondaryAction: appState.hasAccessibilityPermission ? nil : { appState.openAccessibilityPrivacySettings() }
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Whisper \(appVersion)")
                .foregroundStyle(.secondary)

            Spacer()

            Text(Constants.openAIModel)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var microphonePermissionMessage: String {
        switch appState.audioRecorder.permissionStatus {
        case .authorized:
            return "Accès autorisé. Whisper peut enregistrer dès que tu maintiens Fn."
        case .notDetermined:
            return "Le microphone n’a pas encore été autorisé sur ce Mac."
        case .denied:
            return "L’accès au microphone a été refusé. Ouvre les Réglages Système pour l’autoriser."
        case .restricted:
            return "L’accès au microphone est restreint sur ce Mac."
        }
    }

    private var microphonePrimaryActionTitle: String {
        switch appState.audioRecorder.permissionStatus {
        case .authorized:
            return "Actualiser"
        case .notDetermined:
            return "Autoriser le micro"
        case .denied, .restricted:
            return "Ouvrir Réglages Système"
        }
    }

    private var microphoneSecondaryActionTitle: String? {
        switch appState.audioRecorder.permissionStatus {
        case .authorized, .notDetermined:
            return nil
        case .denied, .restricted:
            return "Réessayer"
        }
    }

    private var microphoneSecondaryAction: (() -> Void)? {
        switch appState.audioRecorder.permissionStatus {
        case .authorized, .notDetermined:
            return nil
        case .denied, .restricted:
            return { appState.refreshUIState() }
        }
    }

    private var accessibilityPermissionMessage: String {
        if appState.hasAccessibilityPermission {
            return "Accès autorisé. Whisper peut remettre le texte à l’endroit où tu écris."
        }

        return "L’accessibilité est requise pour coller automatiquement la transcription dans l’app active."
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func activeProfileNameBinding(_ profileID: UUID) -> Binding<String> {
        Binding(
            get: {
                appState.profileService.profile(with: profileID)?.name ?? ""
            },
            set: { newValue in
                appState.updateProfileName(newValue, for: profileID)
            }
        )
    }

    private func activeProfileModeBinding(_ profileID: UUID) -> Binding<TranscriptionMode> {
        Binding(
            get: {
                appState.profileService.profile(with: profileID)?.transcriptionMode ?? .local
            },
            set: { newValue in
                appState.updateProfileMode(newValue, for: profileID)
            }
        )
    }

    private func activeProfileModelBinding(_ profileID: UUID) -> Binding<String?> {
        Binding(
            get: {
                appState.profileService.profile(with: profileID)?.selectedLocalModelId
            },
            set: { newValue in
                appState.updateProfileLocalModel(newValue, for: profileID)
            }
        )
    }

    private func localModelPickerLabel(_ model: LocalModel) -> String {
        model.isReady ? model.name : "\(model.name) · à télécharger"
    }

    private func handleMicrophonePrimaryAction() {
        if appState.audioRecorder.permissionStatus == .authorized {
            appState.refreshUIState()
        } else {
            appState.requestMicrophonePermission()
        }
    }

    private func validateKey() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        isValidating = true
        apiFeedback = .idle

        Task {
            let success = await appState.updateAPIKey(trimmedKey)
            await MainActor.run {
                isValidating = false
                if success {
                    apiKeyInput = ""
                    apiFeedback = .success("La clé API est valide et a été enregistrée.")
                } else {
                    apiFeedback = .failure("La clé API n’a pas pu être validée.")
                }
            }
        }
    }
}

private enum SettingsPane: CaseIterable, Hashable, Identifiable {
    case profiles
    case general
    case transcription
    case models
    case permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .profiles:
            return "Profils"
        case .general:
            return "Général"
        case .transcription:
            return "Clé API"
        case .models:
            return "Modèles locaux"
        case .permissions:
            return "Permissions"
        }
    }

    var subtitle: String {
        switch self {
        case .profiles:
            return "Crée, renomme et choisis les profils qui pilotent l’IA utilisée."
        case .general:
            return "Vue d’ensemble, profil actif et usage quotidien."
        case .transcription:
            return "Configuration globale de la clé API utilisée par les profils Cloud."
        case .models:
            return "Téléchargement et gestion des modèles utilisés par les profils locaux."
        case .permissions:
            return "Statut des autorisations requises pour le micro et le collage."
        }
    }

    var iconName: String {
        switch self {
        case .profiles:
            return "person.2"
        case .general:
            return "slider.horizontal.3"
        case .transcription:
            return "key"
        case .models:
            return "cpu"
        case .permissions:
            return "lock.shield"
        }
    }
}

private enum APIValidationFeedback {
    case idle
    case success(String)
    case failure(String)
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

private struct SettingsFactRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct SettingsNotice: View {
    let title: String
    let message: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PermissionRow: View {
    let title: String
    let message: String
    let isGranted: Bool
    let primaryActionTitle: String
    let primaryAction: () -> Void
    let secondaryActionTitle: String?
    let secondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Label(isGranted ? "Autorisé" : "Requis", systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isGranted ? .green : .orange)
            }

            HStack(spacing: 10) {
                if isGranted {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(.bordered)
                } else {
                    Button(primaryActionTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                }

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct ProfileRow: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isActive {
                                Text("Actif")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                        }
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutKeyView: View {
    let label: String
    let subLabel: String

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(width: 44, height: 40)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(subLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
