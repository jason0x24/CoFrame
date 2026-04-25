import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import Metal

protocol DualRecorderDelegate: AnyObject, Sendable {
    nonisolated func dualRecorder(_ recorder: DualRecorder, didFinishWith session: RecordingSession)
    nonisolated func dualRecorder(_ recorder: DualRecorder, didFailWith error: Error)
}

/// Receives the camera's single landscape sample-buffer stream and writes two MOV files in parallel:
///  - landscape.mov — the original buffers, untouched
///  - portrait.mov  — a center 9:16 crop, re-encoded via Metal-backed Core Image
nonisolated final class DualRecorder: CameraSampleSink, @unchecked Sendable {
    weak var delegate: DualRecorderDelegate?

    private let queue = DispatchQueue(label: "com.gnwl.CoFrame.recorder")
    private let ciContext: CIContext

    private var landscapeWriter: AVAssetWriter?
    private var landscapeVideoInput: AVAssetWriterInput?
    private var landscapeAudioInput: AVAssetWriterInput?

    private var portraitWriter: AVAssetWriter?
    private var portraitVideoInput: AVAssetWriterInput?
    private var portraitAudioInput: AVAssetWriterInput?
    private var portraitAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var sessionStarted = false
    private var startPTS: CMTime = .zero
    private var lastPTS: CMTime = .zero
    private var quality: VideoQuality = .hd1080p30
    private var landscapeURL: URL?
    private var portraitURL: URL?
    private var sessionId: UUID = UUID()
    private var startedAt: Date = Date()

    private(set) var isRecording: Bool = false

    init() {
        if let metal = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metal)
        } else {
            self.ciContext = CIContext()
        }
    }

    func start(quality: VideoQuality, into store: RecordingStore) throws {
        try queue.sync {
            guard !isRecording else { return }
            self.quality = quality
            self.sessionId = UUID()
            self.startedAt = Date()
            let urls = try store.allocateSession(id: sessionId)
            self.landscapeURL = urls.landscape
            self.portraitURL = urls.portrait

            try setupLandscape(at: urls.landscape)
            try setupPortrait(at: urls.portrait)

            sessionStarted = false
            isRecording = true
        }
    }

    func stop() {
        queue.async {
            guard self.isRecording else { return }
            self.isRecording = false
            self.finishWriters()
        }
    }

    // MARK: - CameraSampleSink

    func handle(videoSampleBuffer: CMSampleBuffer) {
        nonisolated(unsafe) let buffer = videoSampleBuffer
        queue.async { [weak self] in self?.processVideo(buffer) }
    }

    func handle(audioSampleBuffer: CMSampleBuffer) {
        nonisolated(unsafe) let buffer = audioSampleBuffer
        queue.async { [weak self] in self?.processAudio(buffer) }
    }

    // MARK: - Sample processing

    private func processVideo(_ sb: CMSampleBuffer) {
        guard isRecording,
              let lWriter = landscapeWriter, let lVideo = landscapeVideoInput,
              let pWriter = portraitWriter, let pVideo = portraitVideoInput,
              let adaptor = portraitAdaptor,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sb)
        else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sb)

        if !sessionStarted {
            if lWriter.status == .unknown {
                lWriter.startWriting()
                lWriter.startSession(atSourceTime: pts)
            }
            if pWriter.status == .unknown {
                pWriter.startWriting()
                pWriter.startSession(atSourceTime: pts)
            }
            startPTS = pts
            sessionStarted = true
        }
        lastPTS = pts

        if lVideo.isReadyForMoreMediaData {
            lVideo.append(sb)
        }

        guard pVideo.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var outBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        guard let outBuffer else { return }

        let srcImage = CIImage(cvPixelBuffer: pixelBuffer)
        let srcExtent = srcImage.extent
        let target = quality.portraitSize
        let cropX = ((srcExtent.width - target.width) / 2.0).rounded(.down)
        let cropRect = CGRect(x: cropX, y: 0, width: target.width, height: target.height)
        let cropped = srcImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropX, y: 0))
        ciContext.render(cropped, to: outBuffer)
        adaptor.append(outBuffer, withPresentationTime: pts)
    }

    private func processAudio(_ sb: CMSampleBuffer) {
        guard isRecording, sessionStarted else { return }
        if let lInput = landscapeAudioInput, lInput.isReadyForMoreMediaData {
            lInput.append(sb)
        }
        if let pInput = portraitAudioInput, pInput.isReadyForMoreMediaData {
            pInput.append(sb)
        }
    }

    // MARK: - Writer setup

    private func setupLandscape(at url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let size = quality.landscapeSize

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.landscapeBitrate,
                AVVideoExpectedSourceFrameRateKey: Int(quality.frameRate),
                AVVideoMaxKeyFrameIntervalKey: Int(quality.frameRate * 2)
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        if writer.canAdd(videoInput) { writer.add(videoInput) }

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        if writer.canAdd(audioInput) { writer.add(audioInput) }

        landscapeWriter = writer
        landscapeVideoInput = videoInput
        landscapeAudioInput = audioInput
    }

    private func setupPortrait(at url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let size = quality.portraitSize

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.portraitBitrate,
                AVVideoExpectedSourceFrameRateKey: Int(quality.frameRate),
                AVVideoMaxKeyFrameIntervalKey: Int(quality.frameRate * 2)
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        if writer.canAdd(videoInput) { writer.add(videoInput) }

        let pixelAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: pixelAttrs)

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
        audioInput.expectsMediaDataInRealTime = true
        if writer.canAdd(audioInput) { writer.add(audioInput) }

        portraitWriter = writer
        portraitVideoInput = videoInput
        portraitAudioInput = audioInput
        portraitAdaptor = adaptor
    }

    private static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: 1,
        AVSampleRateKey: 44_100,
        AVEncoderBitRateKey: 96_000
    ]

    private func finishWriters() {
        landscapeVideoInput?.markAsFinished()
        landscapeAudioInput?.markAsFinished()
        portraitVideoInput?.markAsFinished()
        portraitAudioInput?.markAsFinished()

        let lWriter = landscapeWriter
        let pWriter = portraitWriter
        let lURL = landscapeURL
        let pURL = portraitURL
        let id = sessionId
        let started = startedAt
        let q = quality
        let durationSeconds = sessionStarted ? CMTimeGetSeconds(CMTimeSubtract(lastPTS, startPTS)) : 0

        let group = DispatchGroup()
        if let lWriter, lWriter.status == .writing {
            group.enter()
            lWriter.finishWriting { group.leave() }
        }
        if let pWriter, pWriter.status == .writing {
            group.enter()
            pWriter.finishWriting { group.leave() }
        }

        group.notify(queue: queue) { [weak self] in
            guard let self else { return }
            self.landscapeWriter = nil
            self.portraitWriter = nil
            self.landscapeVideoInput = nil
            self.portraitVideoInput = nil
            self.landscapeAudioInput = nil
            self.portraitAudioInput = nil
            self.portraitAdaptor = nil
            self.sessionStarted = false

            let lOK = (lWriter?.status == .completed)
            let pOK = (pWriter?.status == .completed)

            if (lOK || pOK), let lURL, let pURL {
                let session = RecordingSession(
                    id: id,
                    createdAt: started,
                    quality: q,
                    landscapeURL: lOK ? lURL : nil,
                    portraitURL: pOK ? pURL : nil,
                    durationSeconds: durationSeconds
                )
                self.delegate?.dualRecorder(self, didFinishWith: session)
            } else {
                let err = lWriter?.error ?? pWriter?.error ?? NSError(
                    domain: "CoFrame.DualRecorder",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "录制失败"]
                )
                self.delegate?.dualRecorder(self, didFailWith: err)
            }
        }
    }
}
