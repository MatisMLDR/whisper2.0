# Design: Interface de gestion des modèles locaux

**Date:** 2026-02-18
**Status:** Approuvé

## Contexte

L'interface actuelle de gestion des modèles locaux présente plusieurs problèmes :
- La sélection du modèle n'est pas visible
- Le bouton de téléchargement ne fonctionne pas correctement
- La barre de progression ne s'affiche pas correctement
- Double système de téléchargement (FluidAudio SDK vs LocalModelManager)
- Double badge "Téléchargé" affiché

## Objectifs

- Interface claire et professionnelle
- Sélection toujours visible via radio button
- Progression de téléchargement visible
- États visuels distincts pour chaque situation

## Design

### Structure d'une ligne

```
┌────────────────────────────────────────────────────────────────────┐
│ ○  Parakeet TDT 0.6B v3        FR   NVIDIA     [Télécharger]     │
│    Modèle multilingue optimisé                                     │
│    620 MB                                                          │
└────────────────────────────────────────────────────────────────────┘
```

**De gauche à droite :**
1. **Radio button** - Sélection du modèle
2. **Infos modèle** - Nom, description, taille
3. **Badges** - Langue, Provider
4. **Zone d'action** - Télécharger / Progression / Validé + Supprimer

### États d'un modèle

| État | Radio | Action droite |
|------|-------|---------------|
| Non téléchargé | ○ grisé, inactif | Bouton "Télécharger" bleu |
| Téléchargement | ○ grisé, inactif | Barre animée + "Annuler" |
| Erreur | ○ grisé, inactif | ⚠ Message + "Réessayer" |
| Téléchargé, non sélectionné | ○ actif, cliquable | ✓ vert + 🗑 discret |
| Téléchargé, sélectionné | ● actif, rempli | ✓ vert + 🗑 discret |

### Règle de sélection

Un modèle ne peut être sélectionné **que s'il est téléchargé** (`isReady = true`).

### Gestion de la progression

FluidAudio SDK ne expose pas de progression réelle. Solution : barre de progression indéterminée (animée) pendant le téléchargement.

```
[░░░░░░░░░░░░░░░░░░░░]  (barre animée)
     Téléchargement...
```

## Architecture

### Simplification

- **Supprimer** `LocalModelManager.swift` (code mort, doublon avec SDK)
- **Refactoriser** `LocalModelProvider.swift` pour être la source unique de vérité

### Nouveau LocalModelProvider

```swift
@Published var selectedModelId: String?
@Published var downloadingModelIds: Set<String> = []
@Published var downloadedModelIds: Set<String> = []
@Published var errorMessages: [String: String] = []
```

**Méthodes :**
- `selectModel(_ id: String)` - Sélectionne si téléchargé
- `downloadModel(_ id: String)` - Lance téléchargement via SDK
- `cancelDownload(_ id: String)` - Annule
- `deleteModel(_ id: String)` - Supprime et désélectionne si besoin
- `refreshDownloadedModels()` - Vérifie quels modèles sont prêts

### Nouveau composant UI

Créer `ModelRowView.swift` :

```swift
struct ModelRowView: View {
    let model: LocalModel
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let errorMessage: String?

    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void
}
```

## Fichiers à modifier

| Fichier | Action |
|---------|--------|
| `LocalModelProvider.swift` | Refactoriser, supprimer références à LocalModelManager |
| `LocalModelManager.swift` | **Supprimer** |
| `ModelRowView.swift` | **Créer** |
| `SettingsView.swift` | Simplifier, utiliser ModelRowView |

## Gestion des erreurs

- Message d'erreur discret à côté du bouton
- Bouton "Réessayer" disponible
- Pas d'alerte modale intrusive

## Liste des modèles

Statique (codée en dur) avec le modèle Parakeet TDT 0.6B v3 actuel.

## SDK de téléchargement

Utiliser **FluidAudio SDK** pour le téléchargement (pas de téléchargement direct HuggingFace).
