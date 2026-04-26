import AVFoundation
import Foundation
import Observation
import UIKit

nonisolated enum GuideLineKind: String, CaseIterable, Sendable {
    case off
    case ruleOfThirds
    case crosshair
    case level
    case all

    var displayName: String {
        switch self {
        case .off:          String(localized: "关")
        case .ruleOfThirds: String(localized: "九宫")
        case .crosshair:    String(localized: "十字")
        case .level:        String(localized: "水平")
        case .all:          String(localized: "全部")
        }
    }

    var systemImage: String {
        switch self {
        case .off: "square"
        case .ruleOfThirds: "grid"
        case .crosshair: "plus.viewfinder"
        case .level: "level"
        case .all: "rectangle.grid.2x2"
        }
    }

    var next: GuideLineKind {
        let cases = GuideLineKind.allCases
        let i = cases.firstIndex(of: self)!
        return cases[(i + 1) % cases.count]
    }

    var showThirds: Bool { self == .ruleOfThirds || self == .all }
    var showCrosshair: Bool { self == .crosshair || self == .all }
    var showLevel: Bool { self == .level || self == .all }
}

@MainActor
@Observable
final class CaptureViewModel {
    enum State: Equatable {
        case idle
        case configuring
        case ready
        case recording(startedAt: Date)
        case finishing
        case error(String)
    }

    var state: State = .idle
    var quality: VideoQuality = AppPreferences.defaultQuality {
        didSet { AppPreferences.defaultQuality = quality }
    }
    var position: CameraPosition = .back
    var guideLine: GuideLineKind = AppPreferences.defaultGuideLine {
        didSet { AppPreferences.defaultGuideLine = guideLine }
    }
    var pipHidden: Bool = false
    var lastError: String?
    var elapsed: TimeInterval = 0

    /// User-facing horizontal position of the 9:16 portrait crop, expressed in
    /// **preview-space** (what the user sees on screen).
    /// 0 = preview left edge, 0.5 = center (default), 1 = preview right edge.
    var portraitCropPosition: CGFloat = 0.5 {
        didSet { recorder.cropPosition = effectiveCropPosition }
    }

    /// The same crop position translated into **buffer-space** (the un-mirrored sensor
    /// frame). For the back camera, preview-space and buffer-space are aligned.
    /// For the front camera, the preview is auto-mirrored by AVCaptureVideoPreviewLayer
    /// while the recorder/PiP work on the un-mirrored buffer — so we invert.
    var effectiveCropPosition: CGFloat {
        let clamped = max(0, min(1, portraitCropPosition))
        return position == .front ? (1 - clamped) : clamped
    }

    // MARK: - Focus / exposure / torch

    struct FocusIndicator: Equatable {
        let layerPoint: CGPoint    // in PreviewUIView coord space (0..w, 0..h)
        var locked: Bool
    }

    var focusIndicator: FocusIndicator?
    var exposureBias: Float = 0
    var torchOn: Bool = false

    // MARK: - Zoom

    var userZoomFactor: CGFloat = 1.0
    var zoomCapabilities: CameraSession.ZoomCapabilities = .init()
    private var pinchAnchorZoom: CGFloat = 1.0

    private var focusDismissTask: Task<Void, Never>?

    let session = CameraSession()
    let recorder = DualRecorder()
    let portraitSource = PortraitFrameSource()
    let level = LevelMonitor()

    private let coordinator: SampleCoordinator
    private var timer: Timer?
    private var bootstrapped = false

    init() {
        let coord = SampleCoordinator(recorder: recorder, portraitSource: portraitSource)
        self.coordinator = coord
        recorder.delegate = self
        session.sink = coord
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        state = .configuring

        let perm = await CameraPermission.requestAll()
        guard perm.video, perm.audio else {
            state = .error(String(localized: "CoFrame 需要相机和麦克风权限。请在「设置 → CoFrame」中开启。"))
            return
        }

        do {
            try await session.configure(quality: quality, position: position)
            session.start()
            level.start()
            zoomCapabilities = session.zoomCapabilities
            userZoomFactor = 1.0
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func toggleRecord() {
        switch state {
        case .ready: startRecording()
        case .recording: stopRecording()
        default: break
        }
    }

    private func startRecording() {
        do {
            try recorder.start(quality: quality, into: .shared)
            UIApplication.shared.isIdleTimerDisabled = true
            let now = Date()
            state = .recording(startedAt: now)
            elapsed = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.elapsed = Date().timeIntervalSince(now)
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        state = .finishing
        recorder.stop()
    }

    func switchCamera() async {
        guard case .ready = state else { return }
        do {
            try await session.switchPosition()
            position = session.position
            // New device → reset focus / exposure / torch / zoom UI state.
            focusDismissTask?.cancel()
            focusIndicator = nil
            exposureBias = 0
            torchOn = false
            zoomCapabilities = session.zoomCapabilities
            userZoomFactor = 1.0
            // Re-apply crop in buffer-space — it inverts when switching front/back.
            recorder.cropPosition = effectiveCropPosition
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setUserZoom(_ user: CGFloat, animated: Bool = false) {
        let clamped = max(zoomCapabilities.minUser,
                          min(zoomCapabilities.maxUser, user))
        userZoomFactor = clamped
        session.setUserZoom(clamped, animated: animated)
    }

    func beginPinchZoom() {
        pinchAnchorZoom = userZoomFactor
    }

    func updatePinchZoom(scale: CGFloat) {
        setUserZoom(pinchAnchorZoom * scale, animated: false)
    }

    func tapToFocus(layerPoint: CGPoint, devicePoint: CGPoint) {
        session.tapToFocus(at: devicePoint)
        exposureBias = 0
        focusIndicator = FocusIndicator(layerPoint: layerPoint, locked: false)
        scheduleFocusDismiss()
    }

    func longPressToLock(layerPoint: CGPoint, devicePoint: CGPoint) {
        session.lockFocusAndExposure(at: devicePoint)
        focusIndicator = FocusIndicator(layerPoint: layerPoint, locked: true)
        focusDismissTask?.cancel()  // locked indicator stays visible
    }

    func setExposureBias(_ value: Float) {
        let clamped = max(-2, min(2, value))
        exposureBias = clamped
        session.setExposureBias(clamped)
        scheduleFocusDismiss()
    }

    func toggleTorch() {
        guard session.hasTorch else { return }
        torchOn.toggle()
        session.setTorch(torchOn)
    }

    private func scheduleFocusDismiss() {
        focusDismissTask?.cancel()
        guard focusIndicator?.locked == false else { return }
        focusDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            if self.focusIndicator?.locked == false {
                self.focusIndicator = nil
            }
        }
    }

    func setQuality(_ new: VideoQuality) async {
        guard case .ready = state else { return }
        do {
            try await session.setQuality(new)
            quality = new
        } catch {
            lastError = error.localizedDescription
        }
    }

    func togglePiP() { pipHidden.toggle() }
    func cycleGuide() { guideLine = guideLine.next }
}

extension CaptureViewModel: DualRecorderDelegate {
    nonisolated func dualRecorder(_ recorder: DualRecorder, didFinishWith session: RecordingSession) {
        Task { @MainActor in
            try? RecordingStore.shared.writeMeta(for: session)
            self.state = .ready
        }
        // Thumbnail generation is best-effort and off the main path.
        Task.detached(priority: .background) {
            await RecordingStore.shared.generateThumbnail(for: session)
        }
    }

    nonisolated func dualRecorder(_ recorder: DualRecorder, didFailWith error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.state = .ready
        }
    }
}
