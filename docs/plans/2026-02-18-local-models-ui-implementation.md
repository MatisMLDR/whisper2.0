# Interface de gestion des modèles locaux - Plan d'implémentation

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactoriser l'interface de gestion des modèles locaux avec radio button à gauche, actions à droite, et suppression du code mort.

**Architecture:** Nouveau composant `ModelRowView` encapsule la logique d'affichage d'une ligne. `LocalModelProvider` devient la source unique de vérité. `LocalModelManager` est supprimé.

**Tech Stack:** SwiftUI, Combine, @MainActor, @Published

---

## Task 1: Créer le composant ModelRowView

**Files:**
- Create: `Whisper/Views/ModelRowView.swift`

**Step 1: Créer le fichier ModelRowView.swift avec la structure de base**

```swift
import SwiftUI

struct ModelRowView: View {
    // MARK: - Properties
    let model: LocalModel
    let isSelected: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let errorMessage: String?

    // MARK: - Actions
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void

    // MARK: - Computed
    private var isDownloaded: Bool {
        model.isReady
    }

    private var accentColor: Color {
        Color(nsColor: .controlAccentColor)
    }

    // MARK: - Body
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Radio button à gauche
            radioButton

            // Infos du modèle au centre
            modelInfo

            Spacer()

            // Actions à droite
            actionButtons
        }
        .padding(.vertical, 8)
    }

    // MARK: - Subviews
    private var radioButton: some View {
        Button(action: {
            guard isDownloaded else { return }
            onSelect()
        }) {
            ZStack {
                Circle()
                    .stroke(isDownloaded ? (isSelected ? accentColor : Color.primary.opacity(0.3)) : Color.primary.opacity(0.15), lineWidth: 2)
                    .frame(width: 20, height: 20)

                if isSelected && isDownloaded {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 12, height: 12)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isDownloaded)
        .opacity(isDownloaded ? 1.0 : 0.4)
        .help(isDownloaded ? "Sélectionner ce modèle" : "Téléchargez d'abord ce modèle")
    }

    private var modelInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(model.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? accentColor : .primary)

                // Badge provider
                Text(model.providerType.displayName.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(model.providerType == .whisperKit ? Color.blue.opacity(0.2) : Color.purple.opacity(0.2))
                    .foregroundColor(model.providerType == .whisperKit ? .blue : .purple)
                    .cornerRadius(4)

                // Badge langue
                Text(model.language.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .foregroundColor(.secondary)
                    .cornerRadius(4)
            }

            Text(model.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text(model.fileSize)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isDownloading {
            // État: téléchargement en cours
            downloadProgressView
        } else if let error = errorMessage {
            // État: erreur
            errorView(message: error)
        } else if isDownloaded {
            // État: téléchargé
            downloadedView
        } else {
            // État: non téléchargé
            downloadButton
        }
    }

    private var downloadProgressView: some View {
        VStack(spacing: 6) {
            // Barre de progression indéterminée (animée)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 100, height: 8)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 100 * max(0.05, downloadProgress), height: 8)
                    .animation(.linear(duration: 0.1), value: downloadProgress)
            }

            HStack(spacing: 6) {
                Text("Téléchargement...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("Échec")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
            }

            Button(action: onRetry) {
                Text("Réessayer")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(accentColor)
        }
        .frame(width: 80)
    }

    private var downloadedView: some View {
        HStack(spacing: 8) {
            // Icône de validation
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                Text("Prêt")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.green)

            // Bouton supprimer discret
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Supprimer ce modèle")
        }
    }

    private var downloadButton: some View {
        Button(action: onDownload) {
            HStack(spacing: 4) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 11))
                Text("Télécharger")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .buttonStyle(RefinedButtonStyle(isPrimary: true))
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        ModelRowView(
            model: LocalModel.allModels()[0],
            isSelected: false,
            isDownloading: false,
            downloadProgress: 0,
            errorMessage: nil,
            onSelect: {},
            onDownload: {},
            onCancel: {},
            onDelete: {},
            onRetry: {}
        )

        ModelRowView(
            model: LocalModel.allModels()[0],
            isSelected: true,
            isDownloading: false,
            downloadProgress: 0,
            errorMessage: nil,
            onSelect: {},
            onDownload: {},
            onCancel: {},
            onDelete: {},
            onRetry: {}
        )

        ModelRowView(
            model: LocalModel.allModels()[0],
            isSelected: false,
            isDownloading: true,
            downloadProgress: 0.5,
            errorMessage: nil,
            onSelect: {},
            onDownload: {},
            onCancel: {},
            onDelete: {},
            onRetry: {}
        )
    }
    .padding()
    .frame(width: 450)
}
```

**Step 2: Ajouter le fichier au projet Xcode**

Ouvrir `Whisper.xcodeproj`, ajouter `Whisper/Views/ModelRowView.swift` au target Whisper.

**Step 3: Compiler pour vérifier**

Build dans Xcode (Cmd+B). Devrait compiler sans erreur.

**Step 4: Commit**

```bash
git add Whisper/Views/ModelRowView.swift
git commit -m "feat: add ModelRowView component for local models UI"
```

---

## Task 2: Nettoyer LocalModelProvider

**Files:**
- Modify: `Whisper/Services/LocalModelProvider.swift`

**Step 1: Ajouter une propriété pour les erreurs par modèle**

Ajouter après la ligne 25 :

```swift
    /// Erreur détaillée pour chaque modèle
    @Published var downloadErrors: [String: String] = [:]
```

**Step 2: Modifier downloadCoreMLModel pour gérer les erreurs**

Remplacer la méthode `downloadCoreMLModel` (lignes 187-219) par :

```swift
    private func downloadCoreMLModel(_ model: LocalModel) {
        Task { @MainActor in
            downloadErrors[model.id] = nil

            // Utiliser FluidAudio SDK pour télécharger
            do {
                // Progression indéterminée - on simule une progression basique
                for progress in stride(from: 0.1, through: 0.9, by: 0.1) {
                    guard !Task.isCancelled else {
                        isDownloading[model.id] = false
                        downloadProgress[model.id] = nil
                        return
                    }
                    downloadProgress[model.id] = progress
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }

                // Pré-charger le modèle Parakeet via FluidAudio
                await ParakeetTranscriptionProvider.shared.prewarm()

                // Vérifier si le modèle est bien téléchargé
                if model.isReady {
                    downloadProgress[model.id] = 1.0
                    isDownloading[model.id] = false

                    // Rafraîchir la sélection
                    restoreSelectedModel()
                    saveSelectedModelId()
                } else {
                    throw NSError(domain: "LocalModelProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Le téléchargement a échoué"])
                }
            } catch {
                downloadErrors[model.id] = error.localizedDescription
                isDownloading[model.id] = false
                downloadProgress[model.id] = nil
            }
        }
    }
```

**Step 3: Ajouter une méthode selectModel explicite**

Ajouter après la ligne 76 :

```swift
    /// Sélectionne un modèle s'il est téléchargé
    func selectModel(_ model: LocalModel) {
        guard model.isReady else { return }
        selectedModel = model
        saveSelectedModelId()
    }
```

**Step 4: Ajouter une méthode retry**

Ajouter après cancelDownload :

```swift
    /// Réessaie le téléchargement après un échec
    func retryDownload(_ model: LocalModel) {
        downloadErrors[model.id] = nil
        downloadModel(model)
    }
```

**Step 5: Compiler pour vérifier**

Build dans Xcode (Cmd+B).

**Step 6: Commit**

```bash
git add Whisper/Services/LocalModelProvider.swift
git commit -m "feat: add per-model error tracking and selectModel method"
```

---

## Task 3: Supprimer LocalModelManager

**Files:**
- Delete: `Whisper/Services/LocalModelManager.swift`
- Modify: `Whisper/AppState.swift`
- Modify: `Whisper.xcodeproj/project.pbxproj`

**Step 1: Supprimer la référence dans AppState.swift**

Dans `Whisper/AppState.swift`, supprimer la ligne 16 :

```swift
    @Published var localModelManager = LocalModelManager.shared
```

Et supprimer le commentaire au-dessus (lignes 14-15).

**Step 2: Supprimer le fichier LocalModelManager.swift**

```bash
rm Whisper/Services/LocalModelManager.swift
```

**Step 3: Retirer le fichier du projet Xcode**

Ouvrir `Whisper.xcodeproj`, sélectionner `LocalModelManager.swift` dans le navigateur, appuyer sur Suppr, choisir "Remove Reference".

**Step 4: Compiler pour vérifier**

Build dans Xcode (Cmd+B). Devrait compiler sans erreur.

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove unused LocalModelManager, use LocalModelProvider only"
```

---

## Task 4: Refactoriser SettingsView pour utiliser ModelRowView

**Files:**
- Modify: `Whisper/Views/SettingsView.swift`

**Step 1: Simplifier localModelsSection**

Remplacer `localModelsSection` (lignes 169-183) par :

```swift
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
```

**Step 2: Supprimer les méthodes modelRow et modelActions**

Supprimer `modelRow` (lignes 185-294) et `modelActions` (lignes 296-393).

**Step 3: Compiler pour vérifier**

Build dans Xcode (Cmd+B).

**Step 4: Commit**

```bash
git add Whisper/Views/SettingsView.swift
git commit -m "refactor: use ModelRowView in SettingsView, simplify local models section"
```

---

## Task 5: Tester l'interface complète

**Step 1: Lancer l'app**

Build & Run dans Xcode (Cmd+R).

**Step 2: Vérifier visuellement**

1. Ouvrir Settings → Mode "Local"
2. Vérifier que chaque ligne affiche :
   - Radio button à gauche (cercle vide si non téléchargé, rempli si sélectionné)
   - Infos du modèle au centre
   - Actions à droite (Télécharger / Progression / Prêt)
3. Cliquer sur "Télécharger" - vérifier que la progression s'affiche
4. Une fois téléchargé, vérifier que le radio button devient actif
5. Cliquer sur le radio button pour sélectionner le modèle
6. Vérifier que la suppression fonctionne

**Step 3: Tester les erreurs**

Simuler une erreur réseau (débrancher internet pendant téléchargement) et vérifier que l'état d'erreur s'affiche avec le bouton "Réessayer".

**Step 4: Commit final**

```bash
git add -A
git commit -m "test: verify local models UI works correctly"
```

---

## Fichiers modifiés - Résumé

| Fichier | Action |
|---------|--------|
| `Whisper/Views/ModelRowView.swift` | Créer |
| `Whisper/Services/LocalModelProvider.swift` | Modifier |
| `Whisper/Services/LocalModelManager.swift` | Supprimer |
| `Whisper/AppState.swift` | Modifier |
| `Whisper/Views/SettingsView.swift` | Modifier |
