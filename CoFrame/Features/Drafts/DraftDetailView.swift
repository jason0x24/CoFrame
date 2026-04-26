import AVKit
import SwiftUI
import UIKit

struct DraftDetailView: View {
    let session: RecordingSession
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var orientation: Orientation
    @State private var player: AVPlayer?
    @State private var showDeleteConfirm = false
    @State private var exportChoiceShown = false
    @State private var exportToast: ExportToast?
    @State private var permissionAlert = false

    init(session: RecordingSession, onDelete: @escaping (UUID) -> Void) {
        self.session = session
        self.onDelete = onDelete
        // Default tab: prefer landscape if both exist
        let initial: Orientation = session.hasLandscape ? .landscape
            : (session.hasPortrait ? .portrait : .landscape)
        _orientation = State(initialValue: initial)
    }

    enum Orientation: String, CaseIterable, Identifiable {
        case landscape, portrait
        var id: String { rawValue }
        /// LocalizedStringKey so the SwiftUI Picker re-evaluates with the
        /// current locale environment (kept separate from `rawValue` which
        /// is used as the persistence/tag id).
        var displayName: LocalizedStringKey {
            switch self {
            case .landscape: "横屏"
            case .portrait:  "竖屏"
            }
        }
    }

    private var availableOrientations: [Orientation] {
        var result: [Orientation] = []
        if session.hasLandscape { result.append(.landscape) }
        if session.hasPortrait { result.append(.portrait) }
        return result
    }

    private var currentURL: URL? {
        switch orientation {
        case .landscape: RecordingStore.shared.landscapeURL(for: session)
        case .portrait:  RecordingStore.shared.portraitURL(for: session)
        }
    }

    /// `navigationTitle` takes a `String`, not a SwiftUI Text, so we have to
    /// build the string with the current environment locale ourselves —
    /// otherwise `.formatted(date:time:)` would freeze the system locale at
    /// call-time and ignore the in-app language override.
    private var localizedTitle: String {
        session.createdAt.formatted(
            Date.FormatStyle.dateTime
                .year().month().day().hour().minute()
                .locale(locale)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if availableOrientations.count > 1 {
                Picker("", selection: $orientation) {
                    ForEach(availableOrientations) { o in
                        Text(o.displayName).tag(o)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
            }

            playerSection

            metaSection
        }
        .navigationTitle(localizedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { trailingMenu }
        .confirmationDialog(
            "导出到相册",
            isPresented: $exportChoiceShown,
            titleVisibility: .visible
        ) {
            if session.hasLandscape && session.hasPortrait {
                Button("仅横屏") { exportLandscape() }
                Button("仅竖屏") { exportPortrait() }
                Button("两个都导") { exportBoth() }
            } else if session.hasLandscape {
                Button("导出横屏") { exportLandscape() }
            } else if session.hasPortrait {
                Button("导出竖屏") { exportPortrait() }
            }
            Button("取消", role: .cancel) { }
        }
        .confirmationDialog(
            "确定删除这条草稿？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { performDelete() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("横屏和竖屏文件将被一起删除，无法恢复。")
        }
        .alert("没有相册权限", isPresented: $permissionAlert) {
            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("请在「设置 → CoFrame → 照片」中开启「仅添加照片」权限。")
        }
        .overlay(alignment: .top) { toastView }
        .onChange(of: orientation) { _, _ in reloadPlayer() }
        .onAppear { reloadPlayer() }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var playerSection: some View {
        if let url = currentURL {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity)
                .aspectRatio(orientation == .landscape ? 16.0/9.0 : 9.0/16.0,
                             contentMode: .fit)
                .background(Color.black)
                .id(url)
        } else {
            ContentUnavailableView("视频文件丢失",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text("草稿文件可能已被移除。"))
        }
    }

    private var metaSection: some View {
        VStack(spacing: 6) {
            HStack {
                Label(session.quality.displayName, systemImage: "video")
                Spacer()
                Label(formatDuration(session.durationSeconds), systemImage: "clock")
                Spacer()
                Label(formatBytes(session.totalBytes), systemImage: "internaldrive")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var trailingMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    exportChoiceShown = true
                } label: {
                    Label("导出到相册", systemImage: "square.and.arrow.down")
                }

                Divider()

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = exportToast {
            Text(toast.message)
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(toast.style.background, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Player

    private func reloadPlayer() {
        guard let url = currentURL else { player = nil; return }
        let p = AVPlayer(url: url)
        p.actionAtItemEnd = .pause
        player = p
        p.play()
    }

    // MARK: - Export actions

    private func exportLandscape() {
        guard let url = RecordingStore.shared.landscapeURL(for: session) else { return }
        runExport(urls: [url], single: true)
    }

    private func exportPortrait() {
        guard let url = RecordingStore.shared.portraitURL(for: session) else { return }
        runExport(urls: [url], single: true)
    }

    private func exportBoth() {
        let urls = [
            RecordingStore.shared.landscapeURL(for: session),
            RecordingStore.shared.portraitURL(for: session)
        ].compactMap { $0 }
        runExport(urls: urls, single: false)
    }

    private func runExport(urls: [URL], single: Bool) {
        Task {
            let granted = await PhotoExporter.ensurePermission()
            guard granted else {
                permissionAlert = true
                return
            }
            showToast(.init(message: String(localized: "导出中…"), style: .info))
            let result = await PhotoExporter.saveVideos(urls)
            if result.errors.isEmpty {
                let msg = single
                    ? String(localized: "已导出到相册")
                    : String(localized: "已导出 \(result.succeeded)/\(urls.count) 到相册")
                showToast(.init(message: msg, style: .success))
            } else if result.succeeded > 0 {
                showToast(.init(message: String(localized: "部分导出成功（\(result.succeeded)/\(urls.count)）"),
                                style: .warning))
            } else {
                let msg = result.errors.first?.localizedDescription ?? String(localized: "导出失败")
                showToast(.init(message: msg, style: .error))
            }
        }
    }

    private func performDelete() {
        try? RecordingStore.shared.delete(session: session)
        onDelete(session.id)
        dismiss()
    }

    private func showToast(_ toast: ExportToast) {
        withAnimation(.easeInOut(duration: 0.2)) { exportToast = toast }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { exportToast = nil }
            }
        }
    }
}

private struct ExportToast: Equatable {
    let message: String
    let style: Style

    enum Style {
        case info, success, warning, error
        var background: Color {
            switch self {
            case .info:    .black.opacity(0.7)
            case .success: .green.opacity(0.85)
            case .warning: .orange.opacity(0.85)
            case .error:   .red.opacity(0.85)
            }
        }
    }
}
