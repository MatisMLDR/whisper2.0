import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.historyService.entries.isEmpty {
                ContentUnavailableView(
                    "Aucune transcription",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("L’historique conserve les 24 dernières heures pour retrouver rapidement une dictée récente.")
                )
            } else {
                List {
                    ForEach(appState.historyService.entries) { entry in
                        HistoryEntryRow(
                            entry: entry,
                            onCopy: { appState.copyToPasteboard(entry.text) },
                            onDelete: { appState.historyService.delete(entry) }
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Historique")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !appState.historyService.entries.isEmpty {
                    Button("Tout effacer") {
                        appState.historyService.clearAll()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 540)
    }
}

private struct HistoryEntryRow: View {
    let entry: TranscriptionEntry
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copier")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Supprimer")
            }

            Text(entry.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button("Copier", action: onCopy)
            Button("Supprimer", role: .destructive, action: onDelete)
        }
    }

    private var timeLabel: String {
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.locale = Locale(identifier: "fr_FR")
        relativeFormatter.unitsStyle = .short
        return relativeFormatter.localizedString(for: entry.date, relativeTo: Date())
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppState())
}
