import SwiftUI

struct DraftsView: View {
    @State private var sessions: [RecordingSession] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView("还没有草稿", systemImage: "tray", description: Text("录制完成后会出现在这里"))
                } else {
                    List {
                        ForEach(sessions) { s in
                            DraftRow(session: s)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("草稿箱")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        sessions = RecordingStore.shared.loadAllSessions()
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets {
            try? RecordingStore.shared.delete(session: sessions[i])
        }
        sessions.remove(atOffsets: offsets)
    }
}

private struct DraftRow: View {
    let session: RecordingSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.subheadline)
                Text("\(session.quality.displayName) · \(formatDuration(session.durationSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if session.landscapeURL != nil {
                    Label("横", systemImage: "rectangle.fill")
                        .font(.caption2)
                }
                if session.portraitURL != nil {
                    Label("竖", systemImage: "rectangle.portrait.fill")
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ t: Double) -> String {
        let total = Int(t)
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
