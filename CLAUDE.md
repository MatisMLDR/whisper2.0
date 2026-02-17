# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Whisper is a macOS menu bar app that transcribes voice input to text using OpenAI's Whisper API. The user holds the **Fn** key to record, speaks, releases Fn, and the transcribed text is automatically pasted at the cursor location.

**Core workflow:** Fn press → record → Fn release → transcribe → inject text

## Build and Run

```bash
# Open in Xcode
open Whisper.xcodeproj

# Then build and run with Cmd+R in Xcode
```

No package manager, build scripts, or test suite currently exist.

## Architecture

### Entry Point

- **WhisperApp.swift** - Main app with `@main` attribute, defines the `MenuBarExtra` and `Settings` scenes

### State Management

- **AppState.swift** - Central `@MainActor` `ObservableObject` that:
  - Orchestrates the entire record→transcribe→inject workflow
  - Manages recording/transcription states with `@Published` properties
  - Holds singleton service instances
  - Handles Fn key monitoring lifecycle

### Service Layer (Singletons)

All services are singleton instances accessed via `.shared`:

| Service | Purpose |
|---------|---------|
| **AudioRecorder** | AVAudioRecorder-based M4A recording (16kHz, mono) |
| **AudioConverter** | Converts M4A to WAV PCM for CoreML models |
| **TranscriptionService** | OpenAI Whisper API integration |
| **LocalModelManager** | Downloads/manages local AI models from Hugging Face |
| **LocalModelProvider** | Orchestrates local model inference |
| **KeyboardService** | Fn key press/release monitoring via Carbon/HIToolbox |
| **TextInjector** | AppleScript-based text injection, captures active app |
| **SoundService** | Audio feedback for recording states |
| **HistoryService** | 24-hour local transcription history |
| **KeychainHelper** | Secure API key storage in macOS Keychain |

### Transcription Modes

The app supports two transcription modes (selected in Settings):

| Mode | Provider | Description |
|------|----------|-------------|
| **Cloud** | `OpenAITranscriptionProvider` | OpenAI API, requires API key |
| **Local** | `ParakeetTranscriptionProvider` | On-device CoreML, privacy-first |

**Provider Protocol:** All providers implement `TranscriptionProvider` protocol with a single `transcribe(audioURL:)` method.

### Directory Structure

```
Whisper/
├── Models/           # Data models (TranscriptionMode, LocalModel)
├── Protocols/        # Abstraction protocols (TranscriptionProvider)
├── Providers/        # Transcription implementations (OpenAI, Parakeet, WhisperKit)
├── Services/         # Core services (AudioRecorder, LocalModelManager, etc.)
├── Views/            # SwiftUI views
└── Helpers/          # Utilities (Constants, KeychainHelper)
```

### Views

- **MenuBarView** - Menu bar popup interface
- **SettingsView** - API key configuration
- **HistoryView** - 24-hour transcription history

## Key Patterns

- **SwiftUI** with `@StateObject` / `@EnvironmentObject` for view state
- **MainActor** for all UI-related state management
- **Async/await** for API calls
- **Singleton pattern** for services (accessed via `.shared`)
- **Callbacks** for keyboard events (`onFnPressed`, `onFnReleased`)
- **French language** - UI, comments, and error messages are in French

## Important Constraints

- **App Sandbox is disabled** - Required for Accessibility (text injection)
- **LSUIElement = true** - Menu bar only, no dock icon
- **Minimum macOS 14.0** (Sonoma)

## Permissions Required

1. **Microphone** - Voice recording
2. **Accessibility** - Text injection via AppleScript

Check with `TextInjector.hasAccessibilityPermission()` and request with `TextInjector.requestAccessibilityPermission()`

## API Configuration

- Uses OpenAI's "gpt-4o-mini-transcribe" model
- Optimized for French with technical vocabulary prompts
- API key validation via `TranscriptionService.validateAPIKey()`
- Cost: ~$0.006/minute

## Local Models

- **Parakeet TDT 0.6B v3** - NVIDIA multilingual model via CoreML
- Downloaded from Hugging Face (~620 MB, 6 CoreML files)
- Stored in `~/Library/Application Support/Whisper/Models/parakeet-tdt-0.6b-v3/`
- Requires WAV PCM format (AudioConverter handles M4A→WAV)
- **Note:** Parakeet transcription is currently a work-in-progress (RNN-T pipeline not fully implemented)

## Audio Format

- **M4A** at 16kHz, mono (optimal for Whisper API)
- Temporary files cleaned up after transcription

## Git Guidelines

- Do NOT add "Co-authored by..." lines in commit messages
- Commits in English
