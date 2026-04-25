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
        case .deviceUnavailable: "无法找到可用的相机"
        case .audioUnavailable:  "无法找到可用的麦克风"
        case .cannotAddInput:    "无法将相机或麦克风加入采集会话"
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

    private(set) var position: CameraPosition = .back
    private(set) var quality: VideoQuality = .hd1080p30

    weak var sink: CameraSampleSink?

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
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position.avPosition) else {
            throw CameraError.deviceUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        videoInput = input
        applyFrameRate(on: device, fps: quality.frameRate)
        setupRotationCoordinator(for: device)
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
        do {
            try device.lockForConfiguration()
            // Try to pick a format whose dimensions and frame-rate range cover the target.
            let want = quality.landscapeSize
            let candidates = device.formats.filter { fmt in
                let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                let okSize = dims.width == Int32(want.width) && dims.height == Int32(want.height)
                let okRate = fmt.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Float64(fps) }
                return okSize && okRate
            }
            if let best = candidates.first {
                device.activeFormat = best
            }
            device.activeVideoMinFrameDuration = target
            device.activeVideoMaxFrameDuration = target
            device.unlockForConfiguration()
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
