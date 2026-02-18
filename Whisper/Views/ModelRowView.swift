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
            print("🔘 [ModelRowView] Radio button cliqué pour: \(model.id)")
            print("🔘 [ModelRowView] isDownloaded: \(isDownloaded)")
            guard isDownloaded else {
                print("❌ [ModelRowView] Non téléchargé, action ignorée")
                return
            }
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
