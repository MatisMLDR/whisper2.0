import SwiftUI

struct ModelRowView: View {
    let model: LocalModel
    let isSelected: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let errorMessage: String?

    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void

    private var isDownloaded: Bool {
        model.isReady
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            selectButton

            VStack(alignment: .leading, spacing: 8) {
                header
                Text(model.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    ModelBadge(text: model.providerType.displayName, tint: model.providerType == .whisperKit ? .blue : .secondary)
                    ModelBadge(text: model.language, tint: .secondary)
                    Text(model.fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            actionArea
        }
        .padding(14)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var selectButton: some View {
        Button {
            guard isDownloaded else { return }
            onSelect()
        } label: {
            Image(systemName: selectionSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selectionColor)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!isDownloaded)
        .help(isDownloaded ? "Utiliser ce modèle" : "Télécharge d’abord ce modèle")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(model.name)
                .font(.headline)

            if isSelected {
                ModelBadge(text: "Actif", tint: .accentColor)
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if isDownloading {
            VStack(alignment: .trailing, spacing: 8) {
                ProgressView(value: max(0.08, downloadProgress))
                    .frame(width: 120)

                Button("Annuler", action: onCancel)
                    .buttonStyle(.borderless)
            }
        } else if let errorMessage {
            VStack(alignment: .trailing, spacing: 8) {
                Label("Échec", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)

                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 150, alignment: .trailing)

                Button("Réessayer", action: onRetry)
                    .buttonStyle(.bordered)
            }
        } else if isDownloaded {
            VStack(alignment: .trailing, spacing: 8) {
                Label("Prêt", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)

                Button(role: .destructive, action: onDelete) {
                    Label("Supprimer", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button("Télécharger", action: onDownload)
                .buttonStyle(.borderedProminent)
        }
    }

    private var selectionSymbol: String {
        if !isDownloaded {
            return "circle.dashed"
        }

        return isSelected ? "largecircle.fill.circle" : "circle"
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor)
    }

    private var selectionColor: Color {
        if !isDownloaded {
            return .secondary.opacity(0.45)
        }

        return isSelected ? .accentColor : .secondary
    }
}

private struct ModelBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

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
    }
    .padding()
    .frame(width: 520)
}
