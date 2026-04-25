import SwiftUI
import UIKit

struct CaptureView: View {
    @State private var vm = CaptureViewModel()
    @State private var showDrafts = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch vm.state {
            case .idle, .configuring:
                ProgressView("正在初始化相机…")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .error(let msg):
                ErrorBanner(message: msg)
            default:
                content
            }
        }
        .task { await vm.bootstrap() }
        .sheet(isPresented: $showDrafts) {
            DraftsView()
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            PreviewArea(vm: vm)
                .ignoresSafeArea()

            FloatingControls(vm: vm, showDrafts: $showDrafts)

            if !vm.pipHidden {
                VStack {
                    HStack {
                        Spacer()
                        PortraitPiPView(source: vm.portraitSource, mirrored: vm.position == .front)
                            .frame(width: 92, height: 164)
                            .onTapGesture(count: 2) { vm.togglePiP() }
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - Preview area

private struct PreviewArea: View {
    @Bindable var vm: CaptureViewModel

    var body: some View {
        GeometryReader { geo in
            let h = min(geo.size.height, geo.size.width * 9.0 / 16.0)
            let w = h * 16.0 / 9.0
            let cropWidth = h * 9.0 / 16.0

            ZStack {
                CameraPreviewView(session: vm.session)
                    .frame(width: w, height: h)

                Rectangle()
                    .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: cropWidth, height: h)

                GuideOverlay(kind: vm.guideLine, rollDegrees: vm.level.rollDegrees)
                    .frame(width: w, height: h)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Floating controls

private struct FloatingControls: View {
    @Bindable var vm: CaptureViewModel
    @Binding var showDrafts: Bool

    var body: some View {
        ZStack {
            // Top-left: chip cluster
            VStack {
                HStack(spacing: 8) {
                    ChipButton(systemImage: vm.guideLine.systemImage, label: vm.guideLine.displayName) {
                        vm.cycleGuide()
                    }
                    ChipButton(systemImage: "arrow.triangle.2.circlepath.camera") {
                        Task { await vm.switchCamera() }
                    }
                    ChipButton(systemImage: vm.pipHidden ? "rectangle.dashed" : "rectangle.fill") {
                        vm.togglePiP()
                    }
                    QualityChip(vm: vm)
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 16)

            // Top-center: recording timer
            if case .recording = vm.state {
                VStack {
                    HStack(spacing: 8) {
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                        Text(formatElapsed(vm.elapsed))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 16)
                    Spacer()
                }
            }

            // Right-center: record button (sits in the letterbox strip, aligned with camera content vertical center)
            HStack {
                Spacer()
                RecordButton(isRecording: isRecordingNow) { vm.toggleRecord() }
                    .disabled(isFinishing)
                    .opacity(isFinishing ? 0.5 : 1.0)
            }
            .padding(.trailing, 24)

            // Bottom-right: drafts entry
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ChipButton(systemImage: "photo.stack") {
                        showDrafts = true
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
    }

    private var isRecordingNow: Bool {
        if case .recording = vm.state { return true }
        return false
    }

    private var isFinishing: Bool {
        if case .finishing = vm.state { return true }
        return false
    }
}

// MARK: - Chips

private struct ChipButton: View {
    let systemImage: String
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                if let label, !label.isEmpty {
                    Text(label).font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct QualityChip: View {
    @Bindable var vm: CaptureViewModel

    var body: some View {
        Menu {
            ForEach(VideoQuality.allCases) { q in
                Button {
                    Task { await vm.setQuality(q) }
                } label: {
                    if vm.quality == q {
                        Label(q.displayName, systemImage: "checkmark")
                    } else {
                        Text(q.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "video")
                    .font(.system(size: 14, weight: .semibold))
                Text(vm.quality.displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - Error banner

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
            Button("打开系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private func formatElapsed(_ t: TimeInterval) -> String {
    let total = Int(t)
    let h = total / 3600
    let m = (total / 60) % 60
    let s = total % 60
    return String(format: "%02d:%02d:%02d", h, m, s)
}
