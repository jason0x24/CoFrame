import AVFoundation
import Foundation

protocol CameraSampleSink: AnyObject, Sendable {
    nonisolated func handle(videoSampleBuffer: CMSampleBuffer)
    nonisolated func handle(audioSampleBuffer: CMSampleBuffer)
}

nonisolated enum CameraPosition: Sendable {
    case back, front

    var avPosition: AVCaptureDevice.Position {
        self == .back ? .back : .front
    }

    func toggled() -> CameraPosition { self == .back ? .front : .back }
}

nonisolated enum CameraError: LocalizedError {
    case deviceUnavailable
    case audioUnavailable
    case cannotAddInput

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: String(localized: "无法找到可用的相机")
        case .audioUnavailable:  String(localized: "无法找到可用的麦克风")
        case .cannotAddInput:    String(localized: "无法将相机或麦克风加入采集会话")
        }
    }
}

nonisolated final class CameraSession: NSObject, @unchecked Sendable {
    private let session = AVCaptureSession()
    var captureSession: AVCaptureSession { session }

    private let sessionQueue = DispatchQueue(label: "com.gnwl.CoFrame.session")
    private let videoQueue = DispatchQueue(label: "com.gnwl.CoFrame.video")
    private let audioQueue = DispatchQueue(label: "com.gnwl.CoFrame.audio")

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []

    private(set) var position: CameraPosition = .back
    private(set) var quality: VideoQuality = .hd1080p30

    weak var sink: CameraSampleSink?

    // Lifecycle callbacks fired from `AVCaptureSession`'s notifications.
    // All callbacks fire on the main queue (NotificationCenter setup uses .main).
    var onInterruption: ((AVCaptureSession.InterruptionReason?) -> Void)?
    var onInterruptionEnd: (() -> Void)?
    var onRuntimeError: ((AVError?) -> Void)?

    override init() {
        super.init()
        registerSessionObservers()
    }

    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func registerSessionObservers() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                               object: session, queue: .main) { [weak self] notif in
                let raw = notif.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
                let reason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
                self?.onInterruption?(reason)
            }
        )
        notificationTokens.append(
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
                               object: session, queue: .main) { [weak self] _ in
                self?.onInterruptionEnd?()
            }
        )
        notificationTokens.append(
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                               object: session, queue: .main) { [weak self] notif in
                let error = notif.userInfo?[AVCaptureSessionErrorKey] as? AVError
                self?.onRuntimeError?(error)
            }
        )
    }

    func configure(quality: VideoQuality, position: CameraPosition) async throws {
        self.quality = quality
        self.position = position
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.applyInitialConfiguration()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func start() {
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func switchPosition() async throws {
        let new = position.toggled()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                if let oldVideo = self.videoInput {
                    self.session.removeInput(oldVideo)
                }
                do {
                    try self.addVideoInput(position: new)
                    self.session.commitConfiguration()
                    self.applyCurrentRotation()
                    self.position = new
                    cont.resume()
                } catch {
                    self.session.commitConfiguration()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func setQuality(_ new: VideoQuality) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                if self.session.canSetSessionPreset(new.sessionPreset) {
                    self.session.sessionPreset = new.sessionPreset
                }
                self.session.commitConfiguration()
                self.quality = new
                if let device = self.videoInput?.device {
                    self.applyFrameRate(on: device, fps: new.frameRate)
                }
                cont.resume()
            }
        }
    }

    // MARK: - Focus / exposure / torch

    private var lockWorkItem: DispatchWorkItem?

    /// One-shot autofocus + auto-exposure at the given normalized device point. Settles
    /// to a stable focus then keeps subject-area-change tracking active so re-framing
    /// triggers a refocus. Cancels any pending lock from a prior long-press.
    func tapToFocus(at devicePoint: CGPoint) {
        sessionQueue.async {
            self.lockWorkItem?.cancel()
            self.lockWorkItem = nil
            self.applyPointOfInterest(devicePoint, lockAfterSettle: false)
        }
    }

    /// Long-press behavior: autofocus + auto-exposure at the given point, then **lock**
    /// both modes so re-framing or lighting changes don't cause re-adjustment.
    func lockFocusAndExposure(at devicePoint: CGPoint) {
        sessionQueue.async {
            self.lockWorkItem?.cancel()
            self.applyPointOfInterest(devicePoint, lockAfterSettle: true)
        }
    }

    /// Restore continuous auto behavior and reset exposure bias to 0.
    func resumeContinuousAutoFocus() {
        sessionQueue.async {
            self.lockWorkItem?.cancel()
            self.lockWorkItem = nil
            guard let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.setExposureTargetBias(0, completionHandler: nil)
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch { }
        }
    }

    /// Adjust exposure compensation in EV. Clamped to the device's supported range.
    func setExposureBias(_ ev: Float) {
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            let clamped = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, ev))
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch { }
        }
    }

    // MARK: - Zoom

    /// Preferred user-facing zoom levels surfaced in the UI. Filtered against the
    /// active device's actual range when read.
    private static let preferredUserLevels: [CGFloat] = [0.5, 1.0, 2.0, 5.0]

    /// Internal zoom factor that corresponds to the wide-angle lens (= user 1×).
    /// For virtual cameras this is the first switch-over factor (UW = internal 1.0,
    /// wide = internal 2.0, etc.). For single-lens devices it's just 1.0.
    private var wideZoomMultiplier: CGFloat {
        guard let device = videoInput?.device else { return 1.0 }
        if let first = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            return CGFloat(truncating: first)
        }
        return 1.0
    }

    /// Snapshot of the active device's zoom range, ready to feed the UI.
    struct ZoomCapabilities: Equatable {
        var levels: [CGFloat] = [1.0]
        var minUser: CGFloat = 1.0
        var maxUser: CGFloat = 1.0
    }

    var zoomCapabilities: ZoomCapabilities {
        guard let device = videoInput?.device else { return .init() }
        let multiplier = wideZoomMultiplier
        let minUser = device.minAvailableVideoZoomFactor / multiplier
        let maxUser = device.maxAvailableVideoZoomFactor / multiplier
        let levels = Self.preferredUserLevels.filter { $0 >= minUser - 0.01 && $0 <= maxUser + 0.01 }
        return ZoomCapabilities(
            levels: levels.isEmpty ? [1.0] : levels,
            minUser: minUser,
            maxUser: min(maxUser, 8.0)  // soft cap UI exposure at 8×; prevents wild digital zoom
        )
    }

    /// Set the zoom to a user-facing factor (0.5×, 1×, 2×, …). When `animated` is
    /// true, uses `ramp(toVideoZoomFactor:)` for a smooth tap-to-zoom transition.
    func setUserZoom(_ user: CGFloat, animated: Bool) {
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            let multiplier = self.wideZoomMultiplier
            let target = user * multiplier
            let clamped = max(device.minAvailableVideoZoomFactor,
                              min(device.maxAvailableVideoZoomFactor, target))
            do {
                try device.lockForConfiguration()
                device.cancelVideoZoomRamp()
                if animated {
                    device.ramp(toVideoZoomFactor: clamped, withRate: 4.0)
                } else {
                    device.videoZoomFactor = clamped
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    /// Toggle the camera's torch (rear LED). No-op if the active device has no torch.
    func setTorch(_ on: Bool) {
        sessionQueue.async {
            guard let device = self.videoInput?.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch { }
        }
    }

    /// Whether the active capture device has a torch (front cameras don't).
    var hasTorch: Bool {
        videoInput?.device.hasTorch ?? false
    }

    private func applyPointOfInterest(_ devicePoint: CGPoint, lockAfterSettle: Bool) {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.setExposureTargetBias(0, completionHandler: nil)
            // When locking, disable subject-area monitoring so the device doesn't
            // re-trigger autofocus on its own.
            device.isSubjectAreaChangeMonitoringEnabled = !lockAfterSettle
            device.unlockForConfiguration()
        } catch { return }

        if lockAfterSettle {
            // After ~0.4s the device has typically settled; freeze focus & exposure
            // at the current values. We keep this short so the lock feels responsive.
            let work = DispatchWorkItem { [weak self] in
                self?.lockCurrentFocusAndExposure()
            }
            lockWorkItem = work
            sessionQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    private func lockCurrentFocusAndExposure() {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            device.unlockForConfiguration()
        } catch { }
    }

    // MARK: - Private

    private func applyInitialConfiguration() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(quality.sessionPreset) {
            session.sessionPreset = quality.sessionPreset
        }

        try addVideoInput(position: position)
        try addAudioInput()

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        applyCurrentRotation()
    }

    private func addVideoInput(position: CameraPosition) throws {
        guard let device = Self.preferredVideoDevice(for: position) else {
            throw CameraError.deviceUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        videoInput = input
        applyFrameRate(on: device, fps: quality.frameRate)
        applyQualityEnhancements(on: device)
        setupRotationCoordinator(for: device)
    }

    /// Match the system Camera's defaults for cleaner low-light video:
    /// Video HDR (Smart HDR for video) gives better dynamic range and less
    /// shadow noise; low-light boost lifts sensor gain on dim scenes; both
    /// are off-by-default when you drive the device through `AVCaptureVideoDataOutput`
    /// instead of `AVCaptureMovieFileOutput`. Best-effort — silently ignore
    /// devices/formats that don't support a feature.
    private func applyQualityEnhancements(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.activeFormat.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = true
            }
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
        } catch {
            // tolerate
        }
    }

    /// Prefer a virtual multi-lens device (UW + W + T) when available so the user can
    /// zoom out to 0.5× and across optical tele lenses transparently. Front camera
    /// always falls back to the single wide-angle.
    private static func preferredVideoDevice(for position: CameraPosition) -> AVCaptureDevice? {
        let avPos = position.avPosition
        if position == .back {
            let preferred: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
            for type in preferred {
                if let device = AVCaptureDevice.default(type, for: .video, position: avPos) {
                    return device
                }
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPos)
    }

    private func addAudioInput() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw CameraError.audioUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        audioInput = input
    }

    private func applyFrameRate(on device: AVCaptureDevice, fps: Int32) {
        let target = CMTime(value: 1, timescale: fps)

        // Helper: does this format have a frame-rate range that covers `target`?
        func supports(_ format: AVCaptureDevice.Format) -> Bool {
            format.videoSupportedFrameRateRanges.contains { range in
                target >= range.minFrameDuration && target <= range.maxFrameDuration
            }
        }

        // Helper: does this format also match our target landscape dimensions?
        func matchesQuality(_ format: AVCaptureDevice.Format) -> Bool {
            let want = quality.landscapeSize
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width == Int32(want.width) && dims.height == Int32(want.height) && supports(format)
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // Only switch activeFormat if the current one can't reach the target fps.
            // For virtual (multi-lens) devices, leaving activeFormat alone preserves
            // lens switching; we touch it only when we have to (e.g., asked for 4K60
            // on a default 4K30 format that would otherwise crash on assignment).
            if !supports(device.activeFormat) {
                if let best = device.formats.first(where: matchesQuality) {
                    device.activeFormat = best
                }
            }

            // Final guard: AVFoundation throws an NSInvalidArgumentException
            // (uncatchable by `try?`) if the active format doesn't include the
            // requested frame duration. Skip silently — the user gets the
            // format's default fps rather than a crash.
            guard supports(device.activeFormat) else { return }

            device.activeVideoMinFrameDuration = target
            device.activeVideoMaxFrameDuration = target
        } catch {
            // Frame rate locking is best-effort; tolerate failure.
        }
    }

    /// Wires up an `AVCaptureDevice.RotationCoordinator` for the active camera so the
    /// recording connection always uses the right rotation for the device's physical
    /// orientation × camera position. This matters most for the front camera, whose
    /// natural sensor orientation is opposite to the back camera — hardcoding 0° would
    /// produce upside-down recordings.
    private func setupRotationCoordinator(for device: AVCaptureDevice) {
        rotationObservation?.invalidate()
        rotationObservation = nil

        let coord = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coord
        rotationObservation = coord.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] _, change in
            guard let self, let angle = change.newValue else { return }
            self.sessionQueue.async {
                self.applyVideoRotation(angle)
            }
        }
    }

    private func applyCurrentRotation() {
        guard let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture else { return }
        applyVideoRotation(angle)
    }

    /// Sets the rotation angle on the recording-output connections and force-disables
    /// mirroring on the recorded file (system Camera mirrors the front-camera *preview*
    /// but not the *recorded* video — we mirror only the PiP preview at the UI layer.)
    private func applyVideoRotation(_ angle: CGFloat) {
        for output in [videoOutput as AVCaptureOutput, audioOutput] {
            for connection in output.connections {
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
                // Auto stabilization smooths handheld jitter and applies
                // temporal denoising as a side-effect. Only valid on the
                // video output's connection.
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }
    }
}

nonisolated extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            sink?.handle(videoSampleBuffer: sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            sink?.handle(audioSampleBuffer: sampleBuffer)
        }
    }
}
