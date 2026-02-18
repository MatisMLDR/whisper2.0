# Design: Système de Profils

**Date:** 2026-02-18
**Status:** Approved

## Objectif

Permettre aux utilisateurs de créer plusieurs profils de transcription, chacun avec sa propre configuration IA (mode, modèle, prompt, langue). La sélection du profil se fait via un sous-menu dans la barre de menus.

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────┐
│                    Menu Bar Icon                        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────┐
│ Statut enregistrement   │
├─────────────────────────┤
│ ▸ Profils               │──→ ┌─────────────────┐
├─────────────────────────┤    │ ✓ Boulot        │
│ 📜 Historique           │    │   Perso         │
│ ⚙️ Paramètres           │    │   Rapide        │
├─────────────────────────┤    └─────────────────┘
│ Quitter                 │
└─────────────────────────┘
```

## Contenu d'un Profil

| Champ | Type | Description |
|-------|------|-------------|
| `id` | UUID | Identifiant unique |
| `name` | String | Nom affiché dans le menu |
| `transcriptionMode` | TranscriptionMode | Cloud ou Local |
| `selectedModelId` | String? | ID du modèle local (nil si Cloud) |
| `customPrompt` | String | Prompt système pour l'IA |
| `language` | String | Code ISO ("fr", "en", "es"...) |
| `createdAt` | Date | Date de création |
| `updatedAt` | Date | Dernière modification |

## Architecture

### Nouveaux fichiers

```
Whisper/
├── Models/
│   └── Profile.swift              # NOUVEAU
├── Services/
│   └── ProfileService.swift       # NOUVEAU
└── Views/
    ├── ProfileRowView.swift       # NOUVEAU
    └── ProfileEditorView.swift    # NOUVEAU
```

### Modifications

| Fichier | Changement |
|---------|------------|
| `AppState.swift` | Supprimer `transcriptionMode`, utiliser `ProfileService` |
| `MenuBarView.swift` | Ajouter sous-menu "Profils" |
| `SettingsView.swift` | Ajouter section "Profils" + binder au profil actif |
| `WhisperApp.swift` | Correction focus fenêtre Settings |

## Modèle de données

### Profile.swift

```swift
struct Profile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var transcriptionMode: TranscriptionMode
    var selectedModelId: String?
    var customPrompt: String
    var language: String
    let createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        transcriptionMode: TranscriptionMode,
        selectedModelId: String? = nil,
        customPrompt: String = "",
        language: String = "fr"
    ) {
        self.id = UUID()
        self.name = name
        self.transcriptionMode = transcriptionMode
        self.selectedModelId = selectedModelId
        self.customPrompt = customPrompt
        self.language = language
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
```

## Service

### ProfileService.swift

```swift
@MainActor
final class ProfileService: ObservableObject {
    static let shared = ProfileService()

    @Published var profiles: [Profile] = []
    @Published var activeProfileId: UUID?

    // MARK: - Computed

    var activeProfile: Profile? {
        guard let id = activeProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    // MARK: - CRUD

    func createProfile(name: String, mode: TranscriptionMode, ...) -> Profile
    func updateProfile(_ profile: Profile)
    func deleteProfile(_ profile: Profile)
    func setActiveProfile(_ profile: Profile)

    // MARK: - Persistance

    private let fileURL: URL  // ~/Application Support/Whisper/profiles.json
    private func save()       // Encode JSON et écrit sur disque
    private func load()       // Lit JSON et décode
    private func createDefaultProfile() -> Profile
}
```

**Règles métier:**

1. Au premier lancement (`load()` échoue), créer un profil "Défaut" avec:
   - Mode: Cloud
   - Prompt: Le prompt français technique actuel
   - Langue: "fr"

2. Impossible de supprimer le dernier profil
3. Impossible de supprimer le profil actif (changer d'abord)

**Persistance:**

- Profils: `~/Library/Application Support/Whisper/profiles.json`
- ID actif: `UserDefaults.standard` avec clé `"activeProfileId"`

## Modifications AppState

```swift
@MainActor
final class AppState: ObservableObject {
    // SUPPRIMÉ: @Published var transcriptionMode: TranscriptionMode

    let profileService = ProfileService.shared

    // Computed - redirige vers le profil actif
    var transcriptionMode: TranscriptionMode {
        profileService.activeProfile?.transcriptionMode ?? .api
    }

    var currentProvider: TranscriptionProvider {
        guard let profile = profileService.activeProfile else {
            return OpenAITranscriptionProvider.shared
        }

        switch profile.transcriptionMode {
        case .api:
            return OpenAITranscriptionProvider.shared
        case .local:
            if let modelId = profile.selectedModelId {
                localModelProvider.selectModel(withId: modelId)
            }
            return localModelProvider.currentProvider ?? WhisperKitTranscriptionProvider.shared
        }
    }

    init() {
        // Forward les changements de ProfileService
        profileService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        // ... reste de l'init
    }
}
```

## UI - MenuBarView

Ajouter un `Menu` dans le menu existant:

```swift
Menu {
    ForEach(profileService.profiles) { profile in
        Button {
            profileService.setActiveProfile(profile)
        } label: {
            HStack {
                Text(profile.name)
                if profileService.activeProfileId == profile.id {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }
} label: {
    HStack {
        Image(systemName: "person.crop.circle")
        Text("Profils")
    }
}
```

## UI - SettingsView

### Structure révisée

```
┌─────────────────────────────────────────────────────┐
│ PROFILS                                             │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Profil actif: [Boulot        ▾]                 │ │
│ ├─────────────────────────────────────────────────┤ │
│ │ Boulot                              [✏️] [🗑️]  │ │
│ │ Cloud • Français                               │ │
│ ├─────────────────────────────────────────────────┤ │
│ │ Perso                               [✏️] [🗑️]  │ │
│ │ Local (WhisperKit base) • Anglais              │ │
│ ├─────────────────────────────────────────────────┤ │
│ │ + Nouveau profil                               │ │
│ └─────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────┤
│ CONFIGURATION DU PROFIL ACTIF                       │
│ (sections existantes bindées au profil)             │
│ - Mode de transcription                             │
│ - Microphone                                        │
│ - API Key / Modèles locaux                          │
│ - Langue                                            │
│ - Prompt personnalisé                               │
├─────────────────────────────────────────────────────┤
│ UTILISATION                                         │
│ À PROPOS                                            │
└─────────────────────────────────────────────────────┘
```

### ProfileRowView

Composant compact affichant un profil dans la liste:

```swift
struct ProfileRowView: View {
    let profile: Profile
    let isActive: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(profile.name)
                    .fontWeight(.medium)
                Text("\(profile.transcriptionMode.rawValue) • \(languageName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.plain)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .disabled(canDelete == false)
        }
    }
}
```

### ProfileEditorView

Sheet pour créer/modifier un profil:

```swift
struct ProfileEditorView: View {
    @Binding var profile: Profile?  // nil = création
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var mode: TranscriptionMode
    @State private var selectedModelId: String?
    @State private var language: String
    @State private var customPrompt: String

    var body: some View {
        Form {
            Section("Informations") {
                TextField("Nom du profil", text: $name)
                Picker("Langue", selection: $language) {
                    Text("Français").tag("fr")
                    Text("Anglais").tag("en")
                    Text("Espagnol").tag("es")
                    // ...
                }
            }

            Section("Mode de transcription") {
                Picker("Mode", selection: $mode) {
                    Text("Cloud (OpenAI)").tag(TranscriptionMode.api)
                    Text("Local (IA Privée)").tag(TranscriptionMode.local)
                }
                .pickerStyle(.segmented)

                if mode == .local {
                    // Sélecteur de modèle local
                    ModelPicker(selection: $selectedModelId)
                }
            }

            Section("Prompt système") {
                TextEditor(text: $customPrompt)
                    .frame(minHeight: 100)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }
            }
        }
    }
}
```

## Correction Focus Settings

Solution simple dans SettingsView:

```swift
.onAppear {
    NSApp.activate(ignoringOtherApps: true)
}
```

Si insuffisant, approche plus robuste dans WhisperApp:

```swift
Settings {
    SettingsView()
        .environmentObject(appState)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
}
```

## Flux de données

```
┌─────────────────┐
│ ProfileService  │◄──────────────────────────────────┐
│ (Singleton)     │                                   │
├─────────────────┤                                   │
│ profiles: [...] │    objectWillChange              │
│ activeProfileId │──────────────────────────────┐    │
└─────────────────┘                              │    │
                                                 │    │
┌─────────────────┐                              ▼    │
│   AppState      │◄─────────────────────────────────┘
│ (Observable)    │    (forward change events)
├─────────────────┤
│ profileService  │
│ currentProvider │──► Utilise activeProfile
└─────────────────┘
        │
        │ @EnvironmentObject
        ▼
┌─────────────────┐     ┌─────────────────┐
│  MenuBarView    │     │  SettingsView   │
├─────────────────┤     ├─────────────────┤
│ Lit profiles    │     │ Édite profiles  │
│ Sélectionne     │     │ via ProfileService
└─────────────────┘     └─────────────────┘
```

## Migration

Pas de migration nécessaire - les utilisateurs existants auront un profil "Défaut" créé automatiquement au premier lancement avec la nouvelle version.

## Questions ouvertes / Futures

- [ ] Import/Export de profils
- [ ] Icône/couleur par profil
- [ ] Raccourci clavier par profil
