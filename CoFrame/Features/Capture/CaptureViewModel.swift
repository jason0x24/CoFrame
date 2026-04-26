import AVFoundation
import Foundation
import Observation
import SwiftUI
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
    let thermal = ThermalMonitor()

    /// One-shot transient banner (interruption / runtime error / thermal-stop).
    /// Auto-dismisses after a few seconds so it doesn't shadow the persistent
    /// thermal warning underneath.
    var transientBanner: TransientBanner?

    struct TransientBanner: Equatable {
        enum Severity: Sendable, Equatable { case warning, critical }
        let message: String
        let severity: Severity
    }

    private let coordinator: SampleCoordinator
    private var timer: Timer?
    private var bootstrapped = false
    private var bannerDismissTask: Task<Void, Never>?

    init() {
        let coord = SampleCoordinator(recorder: recorder, portraitSource: portraitSource)
        self.coordinator = coord
        recorder.delegate = self
        session.sink = coord

        session.onInterruption = { [weak self] reason in
            Task { @MainActor in self?.handleSessionInterruption(reason: reason) }
        }
        session.onInterruptionEnd = { [weak self] in
            Task { @MainActor in self?.transientBanner = nil }
        }
        session.onRuntimeError = { [weak self] error in
            Task { @MainActor in self?.handleSessionRuntimeError(error) }
        }

        // Observe thermal changes by polling on each access — `thermal` is
        // @Observable, so any view that reads `vm.thermal.status` re-renders
        // on change. We additionally hook into `withObservationTracking` to
        // react in the model layer (auto-stop on critical).
        observeThermalStatus()
    }

    private func observeThermalStatus() {
        withObservationTracking {
            _ = thermal.status
        } onChange: { [weak self] in
            // ThermalMonitor.update() runs on MainActor, so onChange is called
            // from a main-actor-isolated context.
            MainActor.assumeIsolated {
                self?.handleThermalChange()
                self?.observeThermalStatus()  // re-arm
            }
        }
    }

    private func handleThermalChange() {
        guard thermal.status == .critical, case .recording = state else { return }
        // Critical thermal while recording → preserve what we have and
        // surface a transient banner explaining the auto-stop.
        stopRecording()
        showTransientBanner(
            message: String(localized: "温度过高，已自动停止录制"),
            severity: .critical,
            duration: 5
        )
    }

    private func handleSessionInterruption(reason: AVCaptureSession.InterruptionReason?) {
        let message = interruptionMessage(for: reason)
        if case .recording = state {
            stopRecording()
        }
        showTransientBanner(message: message, severity: .warning, duration: 5)
    }

    private func handleSessionRuntimeError(_ error: AVError?) {
        let detail = error?.localizedDescription ?? String(localized: "未知错误")
        showTransientBanner(
            message: String(localized: "相机错误：\(detail)"),
            severity: .critical,
            duration: 5
        )
    }

    private func interruptionMessage(for reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .audioDeviceInUseByAnotherClient:
            String(localized: "通话期间已自动停止录制")
        case .videoDeviceInUseByAnotherClient:
            String(localized: "其他应用正在使用相机，已停止录制")
        case .videoDeviceNotAvailableInBackground:
            String(localized: "应用进入后台，已停止录制")
        case .videoDeviceNotAvailableDueToSystemPressure:
            String(localized: "系统资源紧张，已自动停止录制")
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            String(localized: "分屏模式下相机不可用")
        default:
            String(localized: "录制被中断")
        }
    }

    private func showTransientBanner(message: String, severity: TransientBanner.Severity, duration: TimeInterval) {
        bannerDismissTask?.cancel()
        transientBanner = TransientBanner(message: message, severity: severity)
        bannerDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            self.transientBanner = nil
        }
    }

    /// Called from `CaptureView` when the app backgrounds / becomes inactive.
    /// We can't keep recording in the background (system suspends AVCaptureSession),
    /// so wrap up gracefully and save what we have rather than risk a torn file.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if case .recording = state {
                stopRecording()
            }
            focusDismissTask?.cancel()
            focusIndicator = nil
            UIApplication.shared.isIdleTimerDisabled = false
        case .inactive, .active:
            break
        @unknown default:
            break
        }
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
