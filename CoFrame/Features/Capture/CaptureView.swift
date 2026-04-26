import SwiftUI
import UIKit

struct CaptureView: View {
    @State private var vm = CaptureViewModel()
    @State private var showDrafts = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch vm.state {
            case .idle, .configuring:
                LaunchSplash()
                    .transition(.opacity)
            case .error(let msg):
                ErrorBanner(message: msg)
            default:
                content
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: stage)
        .task { await vm.bootstrap() }
        .sheet(isPresented: $showDrafts) {
            DraftsView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    /// Coarse bucket of `vm.state` used as the animation key so SwiftUI
    /// crossfades between splash → camera content (or → error) cleanly.
    private var stage: Stage {
        switch vm.state {
        case .idle, .configuring: .loading
        case .error:              .error
        default:                  .ready
        }
    }

    private enum Stage: Hashable { case loading, ready, error }

    @ViewBuilder
    private var content: some View {
        ZStack {
            PreviewArea(vm: vm)
                .ignoresSafeArea()

            FloatingControls(vm: vm,
                             showDrafts: $showDrafts,
                             showSettings: $showSettings)

            if !vm.pipHidden {
                DraggablePiP(vm: vm)
            }
        }
    }
}

// MARK: - Preview area

private struct PreviewArea: View {
    @Bindable var vm: CaptureViewModel

    @State private var cropDragStart: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let h = min(geo.size.height, geo.size.width * 9.0 / 16.0)
            let w = h * 16.0 / 9.0
            let cropWidth = h * 9.0 / 16.0
            let track = w - cropWidth                            // total horizontal travel
            let dashOffset = (vm.portraitCropPosition - 0.5) * track

            ZStack {
                CameraPreviewView(
                    session: vm.session,
                    onTap: { layerPoint, devicePoint in
                        vm.tapToFocus(layerPoint: layerPoint, devicePoint: devicePoint)
                    },
                    onLongPress: { layerPoint, devicePoint in
                        vm.longPressToLock(layerPoint: layerPoint, devicePoint: devicePoint)
                    },
                    onPinchBegin: { vm.beginPinchZoom() },
                    onPinchChange: { scale in vm.updatePinchZoom(scale: scale) }
                )

                // Draggable 9:16 portrait crop indicator. Horizontal-only.
                Rectangle()
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: cropWidth, height: h)
                    .contentShape(Rectangle())
                    .offset(x: dashOffset)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                if cropDragStart == nil {
                                    cropDragStart = vm.portraitCropPosition
                                }
                                guard track > 0 else { return }
                                let delta = value.translation.width / track
                                vm.portraitCropPosition = max(0, min(1, cropDragStart! + delta))
                            }
                            .onEnded { _ in
                                cropDragStart = nil
                            }
                    )

                GuideOverlay(kind: vm.guideLine, rollDegrees: vm.level.rollDegrees)
                    .allowsHitTesting(false)

                if let focus = vm.focusIndicator {
                    FocusIndicatorView(locked: focus.locked)
                        .position(focus.layerPoint)
                        .allowsHitTesting(false)
                        .transition(.opacity)

                    ExposureBiasSlider(bias: vm.exposureBias) { newBias in
                        vm.setExposureBias(newBias)
                    }
                    .position(
                        x: min(focus.layerPoint.x + 64, w - 24),
                        y: min(max(focus.layerPoint.y, 60), h - 60)
                    )
                    .transition(.opacity)
                }
            }
            .frame(width: w, height: h)
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeInOut(duration: 0.18), value: vm.focusIndicator)
        }
    }
}

// MARK: - Focus indicator + exposure bias slider

private struct FocusIndicatorView: View {
    let locked: Bool

    @State private var scale: CGFloat = 1.5

    var body: some View {
        Rectangle()
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 70, height: 70)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeOut(duration: 0.22)) { scale = 1.0 }
            }
            .overlay(alignment: .top) {
                if locked {
                    Text("AE/AF 锁定")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .offset(y: -16)
                }
            }
    }
}

private struct ExposureBiasSlider: View {
    let bias: Float                       // -2 ~ +2
    let onChange: (Float) -> Void

    private let trackHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 13))
                .foregroundStyle(.yellow)

            ZStack(alignment: .center) {
                Capsule()
                    .fill(.white.opacity(0.4))
                    .frame(width: 2, height: trackHeight)

                ForEach([-2, -1, 0, 1, 2], id: \.self) { mark in
                    Rectangle()
                        .fill(.white.opacity(mark == 0 ? 0.9 : 0.4))
                        .frame(width: mark == 0 ? 10 : 6, height: 1)
                        .offset(y: -CGFloat(Float(mark) / 2.0) * (trackHeight / 2))
                }

                Circle()
                    .fill(.yellow)
                    .frame(width: 12, height: 12)
                    .offset(y: -CGFloat(bias / 2.0) * (trackHeight / 2))
            }
            .frame(width: 30, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let yFromCenter = -(value.location.y - trackHeight / 2)
                        let normalized = max(-1, min(1, yFromCenter / (trackHeight / 2)))
                        onChange(Float(normalized * 2))
                    }
            )
        }
    }
}

// MARK: - Floating controls

private struct FloatingControls: View {
    @Bindable var vm: CaptureViewModel
    @Binding var showDrafts: Bool
    @Binding var showSettings: Bool

    var body: some View {
        GeometryReader { geo in
            // Camera preview is 16:9 fit-by-height, centered in full screen.
            let h = min(geo.size.height, geo.size.width * 9.0 / 16.0)
            let w = h * 16.0 / 9.0
            let previewLeft = (geo.size.width - w) / 2
            let previewRight = previewLeft + w
            let insets = geo.safeAreaInsets

            // Where chips and the record button anchor:
            let chipsLeading = max(previewLeft, insets.leading) + 12
            let topInset = max(insets.top, 12)
            let recordX = previewRight - 40            // 40 = button half-width(32) + 8 inset from preview edge
            let rightLetterboxCenter = (previewRight + (geo.size.width - insets.trailing)) / 2
            let bottomInset = max(insets.bottom, 16)

            ZStack(alignment: .topLeading) {
                // Top-left chip cluster — anchored to preview's left edge (not screen),
                // so the leftmost chip never bleeds into the left letterbox.
                HStack(spacing: 8) {
                    ChipButton(systemImage: vm.guideLine.systemImage) {
                        vm.cycleGuide()
                    }
                    ChipButton(systemImage: "arrow.triangle.2.circlepath.camera") {
                        Task { await vm.switchCamera() }
                    }
                    ChipButton(systemImage: vm.pipHidden ? "rectangle.dashed" : "rectangle.fill") {
                        vm.togglePiP()
                    }
                    if vm.position == .back {
                        ChipButton(systemImage: vm.torchOn ? "bolt.fill" : "bolt.slash.fill",
                                   tinted: vm.torchOn) {
                            vm.toggleTorch()
                        }
                    }
                    QualityChip(vm: vm)
                    ChipButton(systemImage: "gearshape.fill") {
                        showSettings = true
                    }
                    if case .recording = vm.state {
                        RecordingTimerChip(elapsed: vm.elapsed)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, chipsLeading)
                .padding(.top, topInset)
                .animation(.easeInOut(duration: 0.2), value: isRecordingNow)

                // Record button — sits inside the preview area near its right edge,
                // never bleeds into the right letterbox or the rounded corner.
                RecordButton(isRecording: isRecordingNow) { vm.toggleRecord() }
                    .disabled(isFinishing)
                    .opacity(isFinishing ? 0.5 : 1.0)
                    .position(x: recordX, y: geo.size.height / 2)

                // Drafts entry — placed in the right letterbox black strip near the bottom.
                ChipButton(systemImage: "photo.stack") { showDrafts = true }
                    .position(x: rightLetterboxCenter,
                              y: geo.size.height - bottomInset - 18)

                // Zoom selector at the bottom of the preview, horizontally centered
                // within the camera content (not the full screen, so it always sits
                // above the camera area regardless of letterbox width).
                ZoomSelector(
                    levels: vm.zoomCapabilities.levels,
                    current: vm.userZoomFactor,
                    onSelect: { vm.setUserZoom($0, animated: true) }
                )
                .position(x: previewLeft + (previewRight - previewLeft) / 2,
                          y: geo.size.height - bottomInset - 32)
            }
        }
        .ignoresSafeArea()
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

// MARK: - Zoom selector

private struct ZoomSelector: View {
    let levels: [CGFloat]
    let current: CGFloat
    let onSelect: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(levels, id: \.self) { level in
                ZoomLevelButton(
                    level: level,
                    isCurrent: isClosest(level),
                    onTap: { onSelect(level) }
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// Highlight the preset closest to the current continuous zoom value, so pinch
    /// zooming smoothly "snaps" the active highlight as the user crosses thresholds.
    private func isClosest(_ level: CGFloat) -> Bool {
        guard let closest = levels.min(by: {
            abs($0 - current) < abs($1 - current)
        }) else { return false }
        return closest == level
    }
}

private struct ZoomLevelButton: View {
    let level: CGFloat
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(isCurrent ? 0.5 : 0))
                    .frame(width: 30, height: 30)
                Text(label)
                    .font(.system(size: isCurrent ? 12 : 10,
                                  weight: isCurrent ? .bold : .medium,
                                  design: .rounded))
                    .foregroundStyle(isCurrent ? Color.yellow : Color.white.opacity(0.9))
            }
            // Hit area is the whole 44×40 frame (Apple's 44pt touch-target rule).
            // Without an explicit contentShape, only the text glyphs catch taps and
            // misses leak through to the underlying camera tap-to-focus.
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.16), value: isCurrent)
    }

    private var label: String {
        // Match iPhone Camera convention: ".5" when inactive, ".5×" when active;
        // "1" inactive, "1×" active; etc.
        let suffix = isCurrent ? "×" : ""
        if abs(level - 0.5) < 0.05 { return ".5\(suffix)" }
        if level == floor(level) {
            return "\(Int(level))\(suffix)"
        }
        return String(format: "%.1f\(suffix)", level)
    }
}

private struct RecordingTimerChip: View {
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
            Text(formatElapsed(elapsed))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.85), in: Capsule())
    }
}

private struct ChipButton: View {
    let systemImage: String
    var label: String? = nil
    var tinted: Bool = false
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
            .foregroundStyle(tinted ? Color.yellow : .white)
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
                    // Lock width so swapping 1080p ↔ 4K30 ↔ 4K60 doesn't reflow.
                    .frame(minWidth: 36, alignment: .center)
                    .contentTransition(.identity)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            // Don't let any ambient implicit animation interpolate the capsule's size
            // when the user swaps quality.
            .animation(nil, value: vm.quality)
        }
    }
}

// MARK: - Draggable, pinch-to-zoom PiP

/// Floating portrait preview the user can drag and pinch-zoom anywhere on screen.
///
/// - Drag tracking is done with plain `@State` (not `@GestureState`) so the position
///   updates live under the finger and stays put on release — no spring-back artefact.
/// - Pinch scales between `minScale` and `maxScale`. The PiP center is re-clamped on
///   scale change so the resized box never escapes the safe area.
/// - Default rest position: bottom-left of the screen.
/// - Double-tap hides the PiP (re-shown via the toolbar chip, which resets to default).
private struct DraggablePiP: View {
    @Bindable var vm: CaptureViewModel

    private static let baseSize = CGSize(width: 120, height: 213)  // 9:16, matches user's preferred default
    private static let edgeMargin: CGFloat = 12
    private static let minScale: CGFloat = 0.6
    private static let maxScale: CGFloat = 1.5

    @State private var center: CGPoint?           // committed center (nil = use default)
    @State private var dragAnchor: CGPoint?       // center at drag start
    @State private var scale: CGFloat = 1.0       // current scale
    @State private var pinchAnchorScale: CGFloat = 1.0  // scale at pinch start

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets

            PortraitPiPView(source: vm.portraitSource,
                            mirrored: vm.position == .front,
                            cropPosition: vm.effectiveCropPosition)
                .frame(width: Self.baseSize.width * scale,
                       height: Self.baseSize.height * scale)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .position(center ?? defaultCenter(in: geo.size, insets: insets))
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if dragAnchor == nil {
                                dragAnchor = center ?? defaultCenter(in: geo.size, insets: insets)
                            }
                            let proposed = CGPoint(
                                x: dragAnchor!.x + value.translation.width,
                                y: dragAnchor!.y + value.translation.height
                            )
                            center = clamped(proposed, in: geo.size, insets: insets)
                        }
                        .onEnded { _ in
                            dragAnchor = nil
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            // Cap scale dynamically to whatever fits inside the preview area.
                            let cap = effectiveMaxScale(in: geo.size, insets: insets)
                            scale = min(max(pinchAnchorScale * value.magnification,
                                            Self.minScale),
                                        cap)
                            if let c = center {
                                center = clamped(c, in: geo.size, insets: insets)
                            }
                        }
                        .onEnded { _ in
                            pinchAnchorScale = scale
                        }
                )
                .onTapGesture(count: 2) { vm.togglePiP() }
        }
        .ignoresSafeArea()
    }

    private var currentSize: CGSize {
        CGSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
    }

    /// The 16:9 preview content rectangle within the screen — PiP is constrained to this.
    private func previewRect(in size: CGSize) -> CGRect {
        let h = min(size.height, size.width * 9.0 / 16.0)
        let w = h * 16.0 / 9.0
        let x = (size.width - w) / 2
        let y = (size.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func defaultCenter(in size: CGSize, insets: EdgeInsets) -> CGPoint {
        let preview = previewRect(in: size)
        let s = currentSize
        // Bottom-left of preview area, with extra inset for home indicator on bottom.
        let bottomGuard = max(insets.bottom, 0)
        return CGPoint(
            x: preview.minX + Self.edgeMargin + s.width / 2,
            y: preview.maxY - bottomGuard - Self.edgeMargin - s.height / 2
        )
    }

    private func clamped(_ point: CGPoint, in size: CGSize, insets: EdgeInsets) -> CGPoint {
        let preview = previewRect(in: size)
        let s = currentSize
        let halfW = s.width / 2
        let halfH = s.height / 2
        let m = Self.edgeMargin
        // Horizontal: stay inside preview's 16:9 box.
        let xMin = preview.minX + halfW + m
        let xMax = preview.maxX - halfW - m
        // Vertical: inside preview & away from DI/home indicator.
        let yMin = preview.minY + max(insets.top, 0) + halfH + m
        let yMax = preview.maxY - max(insets.bottom, 0) - halfH - m
        return CGPoint(
            x: min(max(point.x, xMin), xMax),
            y: min(max(point.y, yMin), yMax)
        )
    }

    /// Largest scale where the PiP still fits inside the preview area minus safe insets.
    private func effectiveMaxScale(in size: CGSize, insets: EdgeInsets) -> CGFloat {
        let preview = previewRect(in: size)
        let availW = preview.width - 2 * Self.edgeMargin
        let availH = preview.height - max(insets.top, 0) - max(insets.bottom, 0) - 2 * Self.edgeMargin
        let fitScale = min(availW / Self.baseSize.width, availH / Self.baseSize.height)
        return min(fitScale, Self.maxScale)
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
