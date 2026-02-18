# Profile System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a profile system allowing users to create, manage, and switch between multiple transcription configurations.

**Architecture:** Profile model + ProfileService singleton handle persistence and state. AppState consumes active profile to determine transcription provider. MenuBarView adds profile submenu, SettingsView adds profile management section.

**Tech Stack:** SwiftUI, Combine, FileManager (JSON persistence), UserDefaults

---

## Task 1: Create Profile Model

**Files:**
- Create: `Whisper/Models/Profile.swift`

**Step 1: Create the Profile.swift file**

```swift
//
//  Profile.swift
//  Whisper
//
//  Created on 2026-02-18.
//

import Foundation

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
        transcriptionMode: TranscriptionMode = .api,
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

    mutating func touch() {
        updatedAt = Date()
    }

    /// Default prompt optimized for French technical dictation
    static var defaultPrompt: String {
        """
        Tu es un assistant de transcription vocale expert en français.
        Transcris l'audio en texte clair et bien formaté.
        Conserve la ponctuation naturelle et la structure des phrases.
        Utilise un vocabulaire technique précis quand approprié.
        Ne rajoute aucun commentaire, juste la transcription.
        """
    }

    /// Create the default profile for first launch
    static func createDefault() -> Profile {
        Profile(
            name: "Défaut",
            transcriptionMode: .api,
            customPrompt: defaultPrompt,
            language: "fr"
        )
    }
}
```

**Step 2: Add file to Xcode project**

- Open `Whisper.xcodeproj`
- Right-click on `Whisper/Models` folder → Add Files to "Whisper"
- Select `Profile.swift`
- Ensure target membership: Whisper

**Step 3: Build to verify**

Run: `Cmd+B` in Xcode
Expected: Build succeeds, no errors

**Step 4: Commit**

```bash
git add Whisper/Models/Profile.swift
git commit -m "feat: add Profile model with default configuration"
```

---

## Task 2: Create ProfileService

**Files:**
- Create: `Whisper/Services/ProfileService.swift`

**Step 1: Create the ProfileService.swift file**

```swift
//
//  ProfileService.swift
//  Whisper
//
//  Created on 2026-02-18.
//

import Foundation
import Combine

@MainActor
final class ProfileService: ObservableObject {
    static let shared = ProfileService()

    // MARK: - Published State

    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfileId: UUID?

    // MARK: - Computed Properties

    var activeProfile: Profile? {
        guard let id = activeProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    var canDeleteActiveProfile: Bool {
        profiles.count > 1
    }

    // MARK: - Persistence

    private let fileManager = FileManager.default
    private var profilesFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let whisperDir = appSupport.appendingPathComponent("Whisper", isDirectory: true)
        return whisperDir.appendingPathComponent("profiles.json")
    }

    private let activeProfileKey = "activeProfileId"

    // MARK: - Initialization

    private init() {
        load()
    }

    // MARK: - CRUD Operations

    func createProfile(
        name: String,
        transcriptionMode: TranscriptionMode = .api,
        selectedModelId: String? = nil,
        customPrompt: String = "",
        language: String = "fr"
    ) -> Profile {
        var profile = Profile(
            name: name,
            transcriptionMode: transcriptionMode,
            selectedModelId: selectedModelId,
            customPrompt: customPrompt.isEmpty ? Profile.defaultPrompt : customPrompt,
            language: language
        )
        profiles.append(profile)
        save()
        return profile
    }

    func updateProfile(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.touch()
        profiles[index] = updated
        save()
    }

    func deleteProfile(_ profile: Profile) {
        // Cannot delete if it's the last profile
        guard profiles.count > 1 else { return }

        // Cannot delete active profile
        guard activeProfileId != profile.id else { return }

        profiles.removeAll { $0.id == profile.id }
        save()
    }

    func setActiveProfile(_ profile: Profile) {
        activeProfileId = profile.id
        UserDefaults.standard.set(profile.id.uuidString, forKey: activeProfileKey)
    }

    func setActiveProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileKey)
    }

    // MARK: - Persistence

    private func save() {
        do {
            // Ensure directory exists
            let directory = profilesFileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesFileURL)
        } catch {
            print("❌ Error saving profiles: \(error)")
        }
    }

    private func load() {
        do {
            // Check if file exists
            guard fileManager.fileExists(atPath: profilesFileURL.path) else {
                // First launch - create default profile
                initializeDefaultProfile()
                return
            }

            let data = try Data(contentsOf: profilesFileURL)
            profiles = try JSONDecoder().decode([Profile].self, from: data)

            // Restore active profile ID
            if let savedIdString = UserDefaults.standard.string(forKey: activeProfileKey),
               let savedId = UUID(uuidString: savedIdString),
               profiles.contains(where: { $0.id == savedId }) {
                activeProfileId = savedId
            } else {
                // Fallback to first profile
                activeProfileId = profiles.first?.id
            }
        } catch {
            print("❌ Error loading profiles: \(error)")
            initializeDefaultProfile()
        }
    }

    private func initializeDefaultProfile() {
        let defaultProfile = Profile.createDefault()
        profiles = [defaultProfile]
        activeProfileId = defaultProfile.id
        save()
        UserDefaults.standard.set(defaultProfile.id.uuidString, forKey: activeProfileKey)
    }
}
```

**Step 2: Add file to Xcode project**

- Right-click on `Whisper/Services` folder → Add Files to "Whisper"
- Select `ProfileService.swift`
- Ensure target membership: Whisper

**Step 3: Build to verify**

Run: `Cmd+B` in Xcode
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Whisper/Services/ProfileService.swift
git commit -m "feat: add ProfileService for profile CRUD and persistence"
```

---

## Task 3: Update AppState to use ProfileService

**Files:**
- Modify: `Whisper/AppState.swift`

**Step 1: Read current AppState.swift**

Read the file to understand the current structure before modifying.

**Step 2: Modify AppState to integrate ProfileService**

Replace the existing `AppState.swift` with:

```swift
//
//  AppState.swift
//  Whisper
//
//  Orchestrates the record → transcribe → inject workflow.
//  Uses ProfileService for transcription configuration.
//

import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - Services

    let profileService = ProfileService.shared
    var localModelProvider = LocalModelProvider.shared
    let audioRecorder = AudioRecorder()
    let keyboardService = KeyboardService()
    let textInjector = TextInjector.shared
    let soundService = SoundService.shared

    // MARK: - State

    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastError: String?
    @Published var hasAPIKey: Bool

    // MARK: - Computed from Active Profile

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
            // Sync selected model from profile to LocalModelProvider
            if let modelId = profile.selectedModelId {
                localModelProvider.selectModel(withId: modelId)
            }
            return localModelProvider.currentProvider ?? WhisperKitTranscriptionProvider.shared
        }
    }

    // MARK: - Initialization

    init() {
        // Check for API key
        hasAPIKey = KeychainHelper.shared.hasAPIKey()

        // Forward LocalModelProvider changes to trigger UI updates
        localModelProvider.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward ProfileService changes to trigger UI updates
        profileService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Setup keyboard callbacks
        setupKeyboardCallbacks()
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Keyboard Handling

    private func setupKeyboardCallbacks() {
        keyboardService.onFnPressed = { [weak self] in
            self?.startRecording()
        }

        keyboardService.onFnReleased = { [weak self] in
            self?.stopRecordingAndTranscribe()
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording, !isTranscribing else { return }

        // Check permissions
        guard TextInjector.hasAccessibilityPermission() else {
            lastError = "Permission d'accessibilité requise"
            return
        }

        do {
            try audioRecorder.startRecording()
            isRecording = true
            lastError = nil
            soundService.playStartSound()
        } catch {
            lastError = "Erreur d'enregistrement: \(error.localizedDescription)"
        }
    }

    func stopRecordingAndTranscribe() {
        guard isRecording else { return }

        audioRecorder.stopRecording()
        isRecording = false
        soundService.playStopSound()

        Task {
            await transcribeAndInject()
        }
    }

    // MARK: - Transcription

    private func transcribeAndInject() async {
        isTranscribing = true

        do {
            guard let audioURL = audioRecorder.recordingURL else {
                throw NSError(domain: "Whisper", code: -1)
            }

            let text = try await currentProvider.transcribe(audioURL: audioURL)

            // Inject text
            try textInjector.injectText(text)

            // Save to history
            HistoryService.shared.addEntry(
                text: text,
                mode: transcriptionMode,
                modelId: profileService.activeProfile?.selectedModelId
            )

            // Cleanup temp audio file
            try? FileManager.default.removeItem(at: audioURL)

        } catch {
            lastError = "Erreur de transcription: \(error.localizedDescription)"
        }

        isTranscribing = false
    }

    // MARK: - API Key Management

    func updateAPIKey(_ key: String) {
        KeychainHelper.shared.save(apiKey: key)
        hasAPIKey = true
    }

    func clearAPIKey() {
        KeychainHelper.shared.delete()
        hasAPIKey = false
    }
}
```

**Step 3: Build to verify**

Run: `Cmd+B` in Xcode
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Whisper/AppState.swift
git commit -m "refactor: AppState now uses ProfileService for transcription config"
```

---

## Task 4: Create ProfileRowView component

**Files:**
- Create: `Whisper/Views/ProfileRowView.swift`

**Step 1: Create ProfileRowView.swift**

```swift
//
//  ProfileRowView.swift
//  Whisper
//
//  Created on 2026-02-18.
//

import SwiftUI

struct ProfileRowView: View {
    let profile: Profile
    let isActive: Bool
    let canDelete: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var languageName: String {
        Locale.current.localizedString(forLanguageCode: profile.language) ?? profile.language.uppercased()
    }

    private var modeDescription: String {
        switch profile.transcriptionMode {
        case .api:
            return "Cloud"
        case .local:
            if let modelId = profile.selectedModelId {
                return "Local (\(modelId))"
            }
            return "Local"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Active indicator
            Circle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)

            // Profile info
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .fontWeight(.medium)
                Text("\(modeDescription) • \(languageName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Modifier")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(canDelete ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
            .help(canDelete ? "Supprimer" : "Impossible de supprimer")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack {
        ProfileRowView(
            profile: Profile(name: "Boulot", transcriptionMode: .api, language: "fr"),
            isActive: true,
            canDelete: true,
            onEdit: {},
            onDelete: {}
        )
        ProfileRowView(
            profile: Profile(name: "Perso", transcriptionMode: .local, selectedModelId: "whisperkit-base", language: "en"),
            isActive: false,
            canDelete: true,
            onEdit: {},
            onDelete: {}
        )
    }
    .padding()
}
```

**Step 2: Add to Xcode project**

- Right-click on `Whisper/Views` folder → Add Files to "Whisper"
- Select `ProfileRowView.swift`

**Step 3: Build to verify**

Run: `Cmd+B` in Xcode
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Whisper/Views/ProfileRowView.swift
git commit -m "feat: add ProfileRowView component for profile list"
```

---

## Task 5: Create ProfileEditorView sheet

**Files:**
- Create: `Whisper/Views/ProfileEditorView.swift`

**Step 1: Create ProfileEditorView.swift**

```swift
//
//  ProfileEditorView.swift
//  Whisper
//
//  Created on 2026-02-18.
//

import SwiftUI

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profileService = ProfileService.shared

    // Existing profile to edit (nil for creation)
    let editingProfile: Profile?

    // Form state
    @State private var name: String
    @State private var transcriptionMode: TranscriptionMode
    @State private var selectedModelId: String?
    @State private var language: String
    @State private var customPrompt: String

    // Available languages
    private let languages = [
        ("fr", "Français"),
        ("en", "Anglais"),
        ("es", "Espagnol"),
        ("de", "Allemand"),
        ("it", "Italien"),
        ("pt", "Portugais")
    ]

    // Local models for picker
    @State private var availableModels: [LocalModel] = []

    var isCreating: Bool {
        editingProfile == nil
    }

    init(profile: Profile?) {
        self.editingProfile = profile
        _name = State(initialValue: profile?.name ?? "")
        _transcriptionMode = State(initialValue: profile?.transcriptionMode ?? .api)
        _selectedModelId = State(initialValue: profile?.selectedModelId)
        _language = State(initialValue: profile?.language ?? "fr")
        _customPrompt = State(initialValue: profile?.customPrompt ?? Profile.defaultPrompt)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Name section
                Section("Informations") {
                    TextField("Nom du profil", text: $name)
                        .textContentType(.name)

                    Picker("Langue", selection: $language) {
                        ForEach(languages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                }

                // Mode section
                Section("Mode de transcription") {
                    Picker("", selection: $transcriptionMode) {
                        Text("Cloud (OpenAI)").tag(TranscriptionMode.api)
                        Text("Local (IA Privée)").tag(TranscriptionMode.local)
                    }
                    .pickerStyle(.segmented)

                    if transcriptionMode == .local {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Modèle")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if availableModels.isEmpty {
                                Text("Aucun modèle téléchargé")
                                    .foregroundStyle(.secondary)
                                    .italic()
                            } else {
                                ForEach(availableModels) { model in
                                    HStack {
                                        RadioButton(isSelected: selectedModelId == model.id) {
                                            selectedModelId = model.id
                                        }
                                        VStack(alignment: .leading) {
                                            Text(model.name)
                                            Text(model.providerType.rawValue)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if model.isReady {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedModelId = model.id
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Prompt section
                Section {
                    TextEditor(text: $customPrompt)
                        .frame(minHeight: 120)
                        .font(.body)
                } header: {
                    Text("Prompt système")
                } footer: {
                    Text("Instructions envoyées à l'IA pour guider la transcription.")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isCreating ? "Nouveau profil" : "Modifier le profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Créer" : "Enregistrer") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                loadAvailableModels()
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    private func loadAvailableModels() {
        availableModels = LocalModel.allModels().filter { $0.isReady }

        // If editing and selected model isn't ready, still show it
        if let currentId = selectedModelId,
           !availableModels.contains(where: { $0.id == currentId }) {
            if let model = LocalModel.allModels().first(where: { $0.id == currentId }) {
                availableModels.append(model)
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        if var existing = editingProfile {
            existing.name = trimmedName
            existing.transcriptionMode = transcriptionMode
            existing.selectedModelId = transcriptionMode == .local ? selectedModelId : nil
            existing.language = language
            existing.customPrompt = customPrompt
            profileService.updateProfile(existing)
        } else {
            let _ = profileService.createProfile(
                name: trimmedName,
                transcriptionMode: transcriptionMode,
                selectedModelId: transcriptionMode == .local ? selectedModelId : nil,
                customPrompt: customPrompt,
                language: language
            )
        }

        dismiss()
    }
}

// Simple radio button component
struct RadioButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
            .foregroundStyle(isSelected ? .accentColor : .secondary)
            .onTapGesture(perform: action)
    }
}

#Preview("Creation") {
    ProfileEditorView(profile: nil)
}

#Preview("Editing") {
    ProfileEditorView(profile: Profile(name: "Boulot", customPrompt: "Custom prompt", language: "en"))
}
```

**Step 2: Add to Xcode project**

- Right-click on `Whisper/Views` folder → Add Files to "Whisper"
- Select `ProfileEditorView.swift`

**Step 3: Build to verify**

Run: `Cmd+B` in Xcode
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Whisper/Views/ProfileEditorView.swift
git commit -m "feat: add ProfileEditorView for creating/editing profiles"
```

---

## Task 6: Update MenuBarView with profile submenu

**Files:**
- Modify: `Whisper/Views/MenuBarView.swift`

**Step 1: Read current MenuBarView.swift**

Read the file to understand the current structure.

**Step 2: Add profile submenu**

Add a `Menu` for profiles between the status section and the existing menu items. Key changes:

1. Add `@ObservedObject var profileService = ProfileService.shared`
2. Add profile selection `Menu` after the status divider
3. Profile submenu shows all profiles with checkmark for active one

Look for the divider after status and add:

```swift
// Profile selection submenu
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

Divider()
```

**Step 3: Build and test**

Run: `Cmd+R` in Xcode
Expected: Menu bar shows "Profils" submenu with default profile

**Step 4: Commit**

```bash
git add Whisper/Views/MenuBarView.swift
git commit -m "feat: add profile selection submenu to MenuBarView"
```

---

## Task 7: Update SettingsView with profile management

**Files:**
- Modify: `Whisper/Views/SettingsView.swift`

**Step 1: Read current SettingsView.swift**

Read the file to understand the current structure.

**Step 2: Add profile management section**

Key changes to SettingsView:

1. Add `@ObservedObject var profileService = ProfileService.shared`
2. Add `@State private var showingProfileEditor: Profile?`
3. Add `@State private var showingNewProfileSheet = false`
4. Add new "Profils" section at the top of the Form
5. Bind existing controls to active profile properties
6. Show ProfileEditorView as sheet

The profile section should include:
- Active profile picker
- List of profiles with ProfileRowView
- "New Profile" button
- Sheet for ProfileEditorView

**Step 3: Modify existing sections to use active profile**

Change bindings from `appState.transcriptionMode` to use the active profile through ProfileService.

The mode picker becomes:
```swift
Picker("Mode", selection: Binding(
    get: { profileService.activeProfile?.transcriptionMode ?? .api },
    set: { newValue in
        if var profile = profileService.activeProfile {
            profile.transcriptionMode = newValue
            profileService.updateProfile(profile)
        }
    }
)) { ... }
```

**Step 4: Build and test**

Run: `Cmd+R` in Xcode
Expected: Settings shows profile section, can create/edit profiles

**Step 5: Commit**

```bash
git add Whisper/Views/SettingsView.swift
git commit -m "feat: add profile management section to SettingsView"
```

---

## Task 8: Fix Settings window focus

**Files:**
- Modify: `Whisper/SettingsView.swift` or `Whisper/WhisperApp.swift`

**Step 1: Add onAppear to SettingsView**

In SettingsView, add:

```swift
.onAppear {
    // Ensure window comes to front
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

**Step 2: Build and test**

Run: `Cmd+R` in Xcode
Test: Open Settings, click another window, then click menu bar → Settings
Expected: Settings window comes to front and takes focus

**Step 3: Commit**

```bash
git add Whisper/Views/SettingsView.swift
git commit -m "fix: ensure Settings window comes to front on open"
```

---

## Task 9: Update HistoryService to use profile info

**Files:**
- Modify: `Whisper/Services/HistoryService.swift`
- Modify: `Whisper/Models/HistoryEntry.swift` (if needed)

**Step 1: Check current HistoryEntry model**

Read `HistoryService.swift` and `HistoryEntry` if it exists.

**Step 2: Add profile reference to history entries**

If HistoryEntry exists, add:
```swift
var profileName: String?
```

Update `addEntry` to accept profile name.

**Step 3: Update AppState to pass profile name**

In `transcribeAndInject()`:
```swift
HistoryService.shared.addEntry(
    text: text,
    mode: transcriptionMode,
    modelId: profileService.activeProfile?.selectedModelId,
    profileName: profileService.activeProfile?.name
)
```

**Step 4: Commit**

```bash
git add Whisper/Services/HistoryService.swift Whisper/Models/HistoryEntry.swift
git commit -m "feat: track profile name in transcription history"
```

---

## Task 10: Final testing and polish

**Step 1: Full manual test**

Test all scenarios:
1. Fresh install → Default profile created
2. Create new profile → Appears in menu
3. Switch profiles → Transcription uses correct config
4. Edit profile → Changes persist
5. Delete profile (non-active) → Removed
6. Cannot delete active profile → Button disabled
7. Cannot delete last profile → Button disabled
8. Settings window focus → Comes to front
9. App restart → Active profile restored

**Step 2: Fix any issues found**

Address any bugs or UI issues discovered during testing.

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete profile system implementation"
```

---

## Summary

| Task | Description | New Files | Modified Files |
|------|-------------|-----------|----------------|
| 1 | Profile model | `Models/Profile.swift` | - |
| 2 | ProfileService | `Services/ProfileService.swift` | - |
| 3 | AppState refactor | - | `AppState.swift` |
| 4 | ProfileRowView | `Views/ProfileRowView.swift` | - |
| 5 | ProfileEditorView | `Views/ProfileEditorView.swift` | - |
| 6 | MenuBar profiles | - | `MenuBarView.swift` |
| 7 | Settings profiles | - | `SettingsView.swift` |
| 8 | Settings focus | - | `SettingsView.swift` |
| 9 | History update | - | `HistoryService.swift` |
| 10 | Final testing | - | Various |

**Total: 4 new files, ~6 modified files**
