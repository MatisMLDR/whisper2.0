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
        HStack(spacing: 0) {
            sidebar
            
            Divider()
                .ignoresSafeArea()
            
            mainContent
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear {
            appState.refreshUIState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshUIState()
        }
    }

    // MARK: - Layout Components

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 38)
            
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(SettingsPane.allCases) { pane in
                        SidebarItem(pane: pane, isSelected: selection == pane) {
                            selection = pane
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            Button(action: {}) {
                HStack {
                    Text("Whisper")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text(appVersion)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .frame(width: 240)
        .background(Color.black.opacity(0.15)) 
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    // Toggle sidebar if needed, but not standard for this design
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    Text(appState.selectedMicrophoneSummary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "headphones")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentPane.title)
                                .font(.system(size: 20, weight: .bold))
                            
                            Text(currentPane.subtitle)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        if currentPane == .profiles {
                            Button {
                                appState.createProfile()
                            } label: {
                                Text("Créer un mode")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

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

                    paneContent
                    
                    Spacer().frame(height: 40)
                }
                .padding(32)
                .frame(maxWidth: 800, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Panes

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

    @ViewBuilder
    private var profilesPane: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard {
                ForEach(Array(appState.profiles.enumerated()), id: \.element.id) { index, profile in
                    ProfileRow(
                        title: profile.name,
                        icon: profile.transcriptionMode.iconName,
                        isActive: appState.activeProfileId == profile.id,
                        modeType: profile.transcriptionMode
                    ) {
                        appState.setActiveProfile(id: profile.id)
                    }
                    
                    if index < appState.profiles.count - 1 {
                        SettingsDivider()
                    }
                }
            }

            if let activeProfile = appState.activeProfile {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profil actif")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)

                    SettingsCard {
                        SettingsEntryRow(label: "Nom") {
                            TextField("", text: activeProfileNameBinding(activeProfile.id))
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 14))
                                .frame(width: 200)
                        }

                        SettingsDivider()

                        SettingsEntryRow(label: "IA") {
                            Picker("", selection: activeProfileModeBinding(activeProfile.id)) {
                                Text("Local").tag(TranscriptionMode.local)
                                Text("Clé API").tag(TranscriptionMode.api)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                        }

                        if activeProfile.transcriptionMode == .local {
                            SettingsDivider()
                            SettingsEntryRow(label: "Modèle local") {
                                Picker("", selection: activeProfileModelBinding(activeProfile.id)) {
                                    Text("Choisir").tag(Optional<String>.none)
                                    ForEach(appState.localModelProvider.availableModels) { model in
                                        Text(localModelPickerLabel(model)).tag(Optional(model.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                        }
                    }

                    if activeProfile.transcriptionMode == .local, let currentModeConfigurationIssue = appState.currentModeConfigurationIssue {
                        SettingsNotice(
                            title: "Profil local incomplet",
                            message: currentModeConfigurationIssue,
                            symbol: "externaldrive.badge.exclamationmark",
                            tint: .orange
                        )
                    } else if activeProfile.transcriptionMode == .api {
                        SettingsNotice(
                            title: appState.hasAPIKey ? "Clé API prête" : "Clé API requise",
                            message: appState.hasAPIKey
                                ? "Tous les profils en mode Clé API utiliseront la clé OpenAI enregistrée sur ce Mac."
                                : "Aucune clé API n’est configurée pour les profils Cloud.",
                            symbol: appState.hasAPIKey ? "checkmark.circle.fill" : "key.fill",
                            tint: appState.hasAPIKey ? .green : .orange
                        )

                        if !appState.hasAPIKey {
                            Button {
                                selection = .transcription
                            } label: {
                                Text("Configurer la clé API")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if appState.profileService.canDeleteProfiles {
                        HStack {
                            Spacer()
                            Button {
                                appState.deleteProfile(id: activeProfile.id)
                            } label: {
                                Text("Supprimer ce profil")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var generalPane: some View {
        VStack(spacing: 24) {
            SettingsCard {
                SettingsFactRow(label: "État", value: appState.statusTitle)
                SettingsDivider()
                SettingsFactRow(label: "Profil actif", value: appState.activeProfileName)
                SettingsDivider()
                SettingsFactRow(label: "IA active", value: appState.providerSummary)
                SettingsDivider()
                SettingsFactRow(label: "Microphone", value: appState.selectedMicrophoneSummary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Utilisation")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                SettingsCard {
                    HStack(alignment: .top, spacing: 16) {
                        ShortcutKeyView(label: "Fn", subLabel: "Maintenir")

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maintiens Fn pour dicter. Le profil actif détermine l’IA utilisée au moment où tu relâches la touche.")
                                .font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Choisis rapidement un autre profil depuis l’icône de barre de menus, puis dicte sans rouvrir les réglages.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptionPane: some View {
        VStack(spacing: 24) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tous les profils en mode Clé API utiliseront cette clé.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        SecureField("sk-...", text: $apiKeyInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))

                        Button {
                            validateKey()
                        } label: {
                            Group {
                                if isValidating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Valider")
                                }
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 32)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                        .opacity((apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating) ? 0.5 : 1)
                    }

                    SettingsFactRow(label: "État", value: appState.hasAPIKey ? "Clé configurée" : "Aucune clé API", padding: 0)
                }
            }

            if case .success(let message) = apiFeedback {
                SettingsNotice(title: "Clé enregistrée", message: message, symbol: "checkmark.circle.fill", tint: .green)
            }

            if case .failure(let message) = apiFeedback {
                SettingsNotice(title: "Validation impossible", message: message, symbol: "xmark.circle.fill", tint: .red)
            }

            HStack(spacing: 16) {
                Link("Gérer mes clés OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.system(size: 13))
                    .foregroundStyle(.blue)

                if appState.hasAPIKey {
                    Button {
                        appState.clearAPIKey()
                        apiFeedback = .idle
                    } label: {
                        Text("Réinitialiser")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var modelsPane: some View {
        VStack(spacing: 24) {
            SettingsNotice(
                title: "Bibliothèque locale",
                message: "Les profils en mode Local pointeront vers les modèles gérés ici. Sélectionner un modèle l’assigne au profil actif.",
                symbol: "info.circle.fill",
                tint: .blue
            )

            SettingsCard {
                ForEach(Array(appState.localModelProvider.availableModels.enumerated()), id: \.element.id) { index, model in
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

                    if index < appState.localModelProvider.availableModels.count - 1 {
                        SettingsDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var permissionsPane: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Microphone")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                SettingsCard {
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
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Accessibilité")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                SettingsCard {
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
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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

    private func activeProfileNameBinding(_ profileID: UUID) -> Binding<String> {
        Binding(
            get: { appState.profileService.profile(with: profileID)?.name ?? "" },
            set: { appState.updateProfileName($0, for: profileID) }
        )
    }

    private func activeProfileModeBinding(_ profileID: UUID) -> Binding<TranscriptionMode> {
        Binding(
            get: { appState.profileService.profile(with: profileID)?.transcriptionMode ?? .local },
            set: { appState.updateProfileMode($0, for: profileID) }
        )
    }

    private func activeProfileModelBinding(_ profileID: UUID) -> Binding<String?> {
        Binding(
            get: { appState.profileService.profile(with: profileID)?.selectedLocalModelId },
            set: { appState.updateProfileLocalModel($0, for: profileID) }
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

// MARK: - Enums

private enum SettingsPane: CaseIterable, Hashable, Identifiable {
    case general
    case profiles
    case transcription
    case models
    case permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "Home"
        case .profiles: return "Modes"
        case .transcription: return "Configuration"
        case .models: return "Models library"
        case .permissions: return "Permissions"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Vue d’ensemble, profil actif et usage quotidien."
        case .profiles: return "Create modes designed for your tasks, whether you're writing a message, speaking another language, or running a meeting..."
        case .transcription: return "Configuration globale de la clé API utilisée par les profils Cloud."
        case .models: return "Téléchargement et gestion des modèles utilisés par les profils locaux."
        case .permissions: return "Statut des autorisations requises pour le micro et le collage."
        }
    }

    var iconName: String {
        switch self {
        case .general: return "house.fill"
        case .profiles: return "sparkles"
        case .transcription: return "gearshape.fill"
        case .models: return "books.vertical.fill"
        case .permissions: return "lock.shield.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: return .orange
        case .profiles: return .blue
        case .transcription: return Color.gray.opacity(0.8)
        case .models: return Color.gray.opacity(0.8)
        case .permissions: return Color.gray.opacity(0.8)
        }
    }
}

private enum APIValidationFeedback {
    case idle
    case success(String)
    case failure(String)
}

// MARK: - View Components

private struct SidebarItem: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(pane.iconColor)
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: pane.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text(pane.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.8))
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : (isHovered ? Color.white.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.1))
            .padding(.vertical, 12)
    }
}

private struct SettingsFactRow: View {
    let label: String
    let value: String
    var padding: CGFloat = 0

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, padding)
    }
}

private struct SettingsEntryRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            content
        }
    }
}

private struct SettingsNotice: View {
    let title: String
    let message: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(isGranted ? .green : .orange)
                        .font(.system(size: 13))
                }
                
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 12) {
                    Button {
                        primaryAction()
                    } label: {
                        Text(primaryActionTitle)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    if let secondaryActionTitle, let secondaryAction {
                        Button {
                            secondaryAction()
                        } label: {
                            Text(secondaryActionTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
    }
}

private struct ProfileRow: View {
    let title: String
    let icon: String
    let isActive: Bool
    let modeType: TranscriptionMode
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    if isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                    
                    Spacer()

                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(modeType == .local ? Color.green.opacity(0.15) : Color.white.opacity(0.1))
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        
                        Image(systemName: modeType == .local ? "cpu" : "cloud.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(modeType == .local ? .green : .gray)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.08) : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.02)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
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
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            Text(subLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
