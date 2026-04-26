import SwiftUI
import UIKit

struct DraftsView: View {
    @State private var sessions: [RecordingSession] = []
    @State private var totalUsed: Int64 = 0
    @State private var deviceFree: Int64 = 0
    @State private var pendingDelete: RecordingSession?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView("还没有草稿",
                                           systemImage: "tray",
                                           description: Text("录制完成后会出现在这里"))
                } else {
                    list
                }
            }
            .navigationTitle("草稿箱")
            .navigationDestination(for: RecordingSession.self) { session in
                DraftDetailView(session: session) { id in
                    sessions.removeAll { $0.id == id }
                    refreshStorage()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await reload() }
        .confirmationDialog(
            "确定删除这条草稿？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { session in
            Button("删除", role: .destructive) { delete(session) }
            Button("取消", role: .cancel) { }
        } message: { _ in
            Text("横屏和竖屏文件将被一起删除，无法恢复。")
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(sessions) { session in
                    NavigationLink(value: session) {
                        DraftCard(session: session)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            pendingDelete = session
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } header: {
                StorageBar(used: totalUsed, free: deviceFree)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            }
        }
        .listStyle(.plain)
    }

    private func reload() async {
        sessions = RecordingStore.shared.loadAllSessions()
        refreshStorage()
    }

    private func refreshStorage() {
        totalUsed = RecordingStore.shared.totalUsedBytes()
        deviceFree = RecordingStore.shared.availableDeviceBytes()
    }

    private func delete(_ session: RecordingSession) {
        try? RecordingStore.shared.delete(session: session)
        sessions.removeAll { $0.id == session.id }
        refreshStorage()
    }
}

// MARK: - Card

private struct DraftCard: View {
    let session: RecordingSession
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.18))
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 54)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)

                HStack(spacing: 6) {
                    Text(session.quality.displayName)
                    Text("·").foregroundStyle(.tertiary)
                    Text(formatDuration(session.durationSeconds))
                    Text("·").foregroundStyle(.tertiary)
                    Text(formatBytes(session.totalBytes))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if session.hasLandscape {
                        OrientationBadge(symbol: "rectangle.fill", text: "横")
                    }
                    if session.hasPortrait {
                        OrientationBadge(symbol: "rectangle.portrait.fill", text: "竖")
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .task(id: session.id) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let url = RecordingStore.shared.thumbnailURL(for: session)
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            await MainActor.run { thumbnail = img }
            return
        }
        // No thumbnail on disk yet — generate one and try again.
        await RecordingStore.shared.generateThumbnail(for: session)
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            await MainActor.run { thumbnail = img }
        }
    }
}

private struct OrientationBadge: View {
    let symbol: String
    let text: LocalizedStringKey
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(.white)
        .background(Color.accentColor.opacity(0.85), in: Capsule())
    }
}

// MARK: - Storage bar

private struct StorageBar: View {
    let used: Int64
    let free: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("草稿用量")
                Spacer()
                Text("\(formatBytes(used)) · 设备剩余 \(formatBytes(free))")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)

            // Visual proportion of used vs total (approximate; capped at 1).
            let ratio = ratio()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private func ratio() -> CGFloat {
        let total = Double(used + free)
        guard total > 0 else { return 0 }
        return CGFloat(min(1.0, max(0.0, Double(used) / total)))
    }
}

// MARK: - Formatters (file-private helpers shared with detail view)

func formatDuration(_ seconds: Double) -> String {
    let total = max(0, Int(seconds))
    let h = total / 3600
    let m = (total / 60) % 60
    let s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useMB, .useGB, .useKB]
    return formatter.string(fromByteCount: bytes)
}
