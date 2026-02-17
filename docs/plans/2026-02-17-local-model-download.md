# Local Model Download Feature - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix and perfect the local model download system so users can reliably download, select, and use local AI models for transcription.

**Architecture:** The app uses a multi-layer architecture: `LocalModel` data structs define available models, `LocalModelManager` handles CoreML file downloads with progress tracking, `LocalModelProvider` coordinates between providers, and `SettingsView` displays the UI. The key issues are: (1) broken `isReady` detection for CoreML models, (2) unreliable progress tracking, (3) UI not reflecting real state.

**Tech Stack:** SwiftUI, URLSession with download delegate, FileManager, Combine, HuggingFace model hosting

---

## Issues Identified

1. **`isReady` check broken for CoreML** - Checks for single `{id}.mlmodelc` file but Parakeet needs 6 separate files
2. **File count mismatch** - LocalModelManager has 6 files but description says "7 fichiers"
3. **Timer memory leak** - Timer in `downloadCoreMLModel` never invalidated
4. **Progress calculation convoluted** - May show incorrect percentages
5. **Selection button unclear** - Doesn't indicate if model must be downloaded first
6. **Download state not properly synced** - Between LocalModelManager and LocalModelProvider

---

## Task 1: Fix CoreML Model `isReady` Detection

**Files:**
- Modify: `Whisper/Models/LocalModel.swift:31-43`

**Step 1: Update `isReady` computed property for CoreML models**

Replace the broken `isReady` check with one that verifies all Parakeet files exist:

```swift
var isReady: Bool {
    switch providerType {
    case .whisperKit:
        // Pour WhisperKit, vérifier si le modèle est dans le cache
        return isWhisperKitModelDownloaded()
    case .coreML:
        // Pour CoreML, vérifier si tous les fichiers du modèle existent
        return areAllCoreMLFilesDownloaded()
    case .generic:
        return false
    }
}

/// Vérifie si tous les fichiers CoreML du modèle sont téléchargés
private func areAllCoreMLFilesDownloaded() -> Bool {
    guard providerType == .coreML else { return false }

    let requiredFiles: [String]
    switch id {
    case "parakeet-tdt-0.6b-v3":
        requiredFiles = Self.parakeetRequiredFiles
    default:
        return false
    }

    guard let modelDir = getCoreMLModelDirectory() else { return false }

    return requiredFiles.allSatisfy { fileName in
        FileManager.default.fileExists(atPath: modelDir.appendingPathComponent(fileName).path)
    }
}

/// Répertoire où sont stockés les modèles CoreML
private func getCoreMLModelDirectory() -> URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Whisper", isDirectory: true)
        .appendingPathComponent("Models", isDirectory: true)
        .appendingPathComponent(id, isDirectory: true)
}

/// Fichiers requis pour le modèle Parakeet
static let parakeetRequiredFiles = [
    "ParakeetDecoder.mlmodelc",
    "Preprocessor.mlmodelc",
    "JointDecisionv2.mlmodelc",
    "MelEncoder.mlmodelc",
    "RNNTJoint.mlmodelc",
    "ParakeetEncoder_15s.mlmodelc"
]
```

**Step 2: Verify fix by checking file exists**

Run: Build app in Xcode with `Cmd+R`
Expected: App compiles without errors

**Step 3: Commit**

```bash
git add Whisper/Models/LocalModel.swift
git commit -m "fix: correct isReady detection for CoreML models"
```

---

## Task 2: Fix LocalModelManager Download Logic

**Files:**
- Modify: `Whisper/Services/LocalModelManager.swift`

**Step 1: Add proper state tracking properties**

Add after line 44:

```swift
/// Nombre total de fichiers à télécharger
private let totalParakeetFiles = parakeetFiles.count

/// Nombre de fichiers terminés pour le téléchargement en cours
private var completedFiles: Int = 0
```

**Step 2: Fix download progress calculation in `urlSession(_:didWriteData:)`**

Replace lines 208-219 with:

```swift
func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard let (modelId, _) = downloadTasks[downloadTask],
          totalBytesExpectedToWrite > 0 else { return }

    // Progression du fichier actuel (0.0 à 1.0)
    let currentFileProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

    // Progression globale = (fichiers terminés + progression fichier actuel) / total fichiers
    let overallProgress = (Double(completedFiles) + currentFileProgress) / Double(totalParakeetFiles)

    Task { @MainActor in
        downloadProgress[modelId] = min(overallProgress, 1.0)
    }
}
```

**Step 3: Fix completion tracking in `urlSession(_:didFinishDownloadingTo:)`**

After line 191 (`refreshModelStates()`), add:

```swift
completedFiles = parakeetFilesDownloaded
```

And update the completion check (lines 194-199):

```swift
// Vérifier si tous les fichiers sont téléchargés
if parakeetFilesDownloaded == totalParakeetFiles {
    Task { @MainActor in
        isDownloading[modelId] = false
        downloadProgress[modelId] = 1.0
        completedFiles = 0
    }
}
```

**Step 4: Reset state when starting new download**

In `downloadModel(_:)`, after line 111 add:

```swift
completedFiles = 0
```

**Step 5: Build and verify**

Run: Build app in Xcode with `Cmd+R`
Expected: App compiles without errors

**Step 6: Commit**

```bash
git add Whisper/Services/LocalModelManager.swift
git commit -m "fix: improve download progress tracking accuracy"
```

---

## Task 3: Fix LocalModelProvider Timer Leak

**Files:**
- Modify: `Whisper/Services/LocalModelProvider.swift:188-213`

**Step 1: Store timer reference properly**

Add property after line 34:

```swift
private var progressTimer: Timer?
```

**Step 2: Replace `downloadCoreMLModel` method**

Replace lines 188-213 with:

```swift
private func downloadCoreMLModel(_ model: LocalModel) {
    LocalModelManager.shared.downloadModel(model)

    // Invalider l'ancien timer s'il existe
    progressTimer?.invalidate()
    progressTimer = nil

    // Observer la progression depuis LocalModelManager
    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
        guard let self = self else {
            timer.invalidate()
            return
        }

        // Récupérer la progression depuis LocalModelManager
        if let progress = LocalModelManager.shared.downloadProgress[model.id] {
            Task { @MainActor in
                self.downloadProgress[model.id] = progress

                if progress >= 1.0 {
                    self.isDownloading[model.id] = false
                    timer.invalidate()
                    self.progressTimer = nil
                    // Rafraîchir la sélection
                    self.restoreSelectedModel()
                }
            }
        }

        // Vérifier si le téléchargement a été annulé
        if !LocalModelManager.shared.isDownloading[model.id, default: false] {
            Task { @MainActor in
                self.isDownloading[model.id] = false
                timer.invalidate()
                self.progressTimer = nil
            }
        }
    }

    // S'assurer que le timer tourne sur le run loop principal
    if let timer = progressTimer {
        RunLoop.main.add(timer, forMode: .common)
    }
}
```

**Step 3: Add cleanup in `cancelDownload`**

In `cancelDownload(_:)`, after line 106 add:

```swift
progressTimer?.invalidate()
progressTimer = nil
```

**Step 4: Build and verify**

Run: Build app in Xcode with `Cmd+R`
Expected: App compiles without errors

**Step 5: Commit**

```bash
git add Whisper/Services/LocalModelProvider.swift
git commit -m "fix: prevent timer memory leak in download progress tracking"
```

---

## Task 4: Fix Description Text (6 files, not 7)

**Files:**
- Modify: `Whisper/Models/LocalModel.swift:183`

**Step 1: Update Parakeet description**

Change line 183 from:
```swift
description: "Modèle NVIDIA multilingue ultra-rapide. Nécessite 7 fichiers CoreML.",
```
to:
```swift
description: "Modèle NVIDIA multilingue ultra-rapide. 6 fichiers CoreML (~620 MB).",
```

**Step 2: Commit**

```bash
git add Whisper/Models/LocalModel.swift
git commit -m "fix: correct Parakeet file count in description"
```

---

## Task 5: Improve SettingsView UI for Model Selection

**Files:**
- Modify: `Whisper/Views/SettingsView.swift`

**Step 1: Improve selection button to show download requirement**

Replace the selection button in `modelRow(_:)` (lines 140-163) with:

```swift
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
```

**Step 2: Build and verify**

Run: Build app in Xcode with `Cmd+R`
Expected: App compiles without errors

**Step 3: Commit**

```bash
git add Whisper/Views/SettingsView.swift
git commit -m "feat: improve model selection button with download status indication"
```

---

## Task 6: Add Download Error Handling and User Feedback

**Files:**
- Modify: `Whisper/Services/LocalModelManager.swift`
- Modify: `Whisper/Views/SettingsView.swift`

**Step 1: Add error state to LocalModelManager**

Add after line 31:

```swift
/// Erreur détaillée pour chaque modèle
@Published var downloadError: [String: String] = [:]
```

**Step 2: Update error handling in `urlSession(_:task:didCompleteWithError:)`**

Replace lines 222-236 with:

```swift
func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let (modelId, fileName) = downloadTasks[task as! URLSessionDownloadTask] else { return }

    if let error = error {
        let nsError = error as NSError

        // Ignorer les erreurs d'annulation
        guard nsError.code != NSURLErrorCancelled else {
            downloadTasks.removeValue(forKey: task as! URLSessionDownloadTask)
            return
        }

        Task { @MainActor in
            isDownloading[modelId] = false
            downloadError[modelId] = "Erreur téléchargement \(fileName): \(error.localizedDescription)"
            errorMessage = "Échec du téléchargement. Vérifiez votre connexion Internet."
        }
    }

    downloadTasks.removeValue(forKey: task as! URLSessionDownloadTask)
}
```

**Step 3: Add error display in SettingsView**

In `modelActions(_:)`, add error display after the download progress section (after line 235):

```swift
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
    .frame(width: 100)
}
```

**Step 4: Clear error when starting new download**

In `LocalModelManager.downloadModel(_:)`, after line 97 add:

```swift
downloadError[model.id] = nil
```

**Step 5: Build and verify**

Run: Build app in Xcode with `Cmd+R`
Expected: App compiles without errors

**Step 6: Commit**

```bash
git add Whisper/Services/LocalModelManager.swift Whisper/Views/SettingsView.swift
git commit -m "feat: add download error handling with retry option"
```

---

## Task 7: Add Proper Progress Bar Animation

**Files:**
- Modify: `Whisper/Views/SettingsView.swift:227-235`

**Step 1: Enhance progress bar display**

Replace the progress section in `modelActions(_:)` with:

```swift
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
}
```

**Step 2: Build and verify**

Run: Build app in Xcode with `Cmd+R`
Expected: App compiles without errors

**Step 3: Commit**

```bash
git add Whisper/Views/SettingsView.swift
git commit -m "feat: add animated progress bar with cancel button"
```

---

## Task 8: Verify HuggingFace Download URLs

**Files:**
- Modify: `Whisper/Services/LocalModelManager.swift:34-41`

**Step 1: Confirm URLs are correct**

The current URLs use this format:
```
https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/main/{fileName}
```

This is the correct HuggingFace direct download URL format. No changes needed.

**Step 2: Add URL validation comment**

Add comment before line 34:

```swift
// URLs de téléchargement HuggingFace pour les fichiers CoreML
// Format: https://huggingface.co/{org}/{repo}/resolve/main/{filename}
```

**Step 3: Commit**

```bash
git add Whisper/Services/LocalModelManager.swift
git commit -m "docs: add HuggingFace URL format comment"
```

---

## Task 9: Final Integration Test

**Files:**
- None (testing only)

**Step 1: Build and run the app**

Run: Build in Xcode with `Cmd+R`

**Step 2: Test the complete flow**

1. Open Settings
2. Switch to "Local" mode
3. Verify models appear with correct "Téléchargé" status
4. Click "Télécharger" on Parakeet model
5. Verify progress bar appears and updates
6. Wait for download to complete
7. Verify "Téléchargé" badge appears
8. Click selection button
9. Verify model becomes selected
10. Delete model and verify it disappears

**Step 3: Create summary commit**

```bash
git add -A
git status
git commit -m "feat: complete local model download system overhaul"
```

---

## Summary

| Task | Description | Files Modified |
|------|-------------|----------------|
| 1 | Fix `isReady` detection | LocalModel.swift |
| 2 | Fix download progress | LocalModelManager.swift |
| 3 | Fix timer leak | LocalModelProvider.swift |
| 4 | Fix description text | LocalModel.swift |
| 5 | Improve selection UI | SettingsView.swift |
| 6 | Add error handling | LocalModelManager.swift, SettingsView.swift |
| 7 | Add progress animation | SettingsView.swift |
| 8 | Verify URLs | LocalModelManager.swift |
| 9 | Integration test | None |
