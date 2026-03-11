import SwiftUI

struct RecordingOverlayView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.isTranscribing {
                transcribingContent
            } else {
                recordingContent
            }

            Divider()
                .opacity(0.3)

            bottomBar
        }
        .frame(width: 480)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
    }

    // MARK: - Recording State

    private var recordingContent: some View {
        VStack(spacing: 0) {
            waveformView
                .frame(height: 64)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
    }

    private var waveformView: some View {
        GeometryReader { geometry in
            let levels = appState.audioRecorder.audioLevelHistory
            let barCount = levels.count
            let spacing: CGFloat = 3
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = max(2, (geometry.size.width - totalSpacing) / CGFloat(barCount))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let level = CGFloat(levels[index])
                    // Hauteur minimale de 3pt pour les barres silencieuses
                    let barHeight = max(3, level * geometry.size.height * 0.9)

                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(barGradient(for: level))
                        .frame(width: barWidth, height: barHeight)
                        .animation(.easeOut(duration: 0.08), value: levels[index])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barGradient(for level: CGFloat) -> some ShapeStyle {
        if level > 0.6 {
            return Color.white
        } else if level > 0.2 {
            return Color.white.opacity(0.7)
        } else {
            return Color.white.opacity(0.35)
        }
    }

    // MARK: - Transcribing State

    private var transcribingContent: some View {
        VStack(spacing: 8) {
            shimmerWaveform
                .frame(height: 64)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
    }

    private var shimmerWaveform: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                let barCount = 40
                let spacing: CGFloat = 3
                let totalSpacing = spacing * CGFloat(barCount - 1)
                let barWidth = max(2, (geometry.size.width - totalSpacing) / CGFloat(barCount))

                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let phase = sin(time * 3.0 + Double(index) * 0.3) * 0.5 + 0.5
                        let height = max(3, CGFloat(phase) * geometry.size.height * 0.4)

                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(Color.white.opacity(0.2 + phase * 0.2))
                            .frame(width: barWidth, height: height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Profil actif (bas gauche)
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(appState.isTranscribing ? .blue : .red)

                Text(appState.activeProfileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer()

            if appState.isTranscribing {
                // État transcription
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)

                    Text("Transcription…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                // Contrôles enregistrement (bas droite)
                HStack(spacing: 12) {
                    // Stop
                    HStack(spacing: 5) {
                        Text("Stop")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        KeyCapView(label: shortcutKeyLabel)
                    }

                    // Cancel
                    HStack(spacing: 5) {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        KeyCapView(label: "esc")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var shortcutKeyLabel: String {
        appState.recordingShortcut.displayString
    }
}

// MARK: - Key Cap View

private struct KeyCapView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}
