import CoreMedia
import Foundation

/// Fans out the camera's single sample-buffer stream to multiple consumers
/// (the recorder writes both files, the portrait source feeds the PiP layer).
nonisolated final class SampleCoordinator: CameraSampleSink, @unchecked Sendable {
    private let recorder: DualRecorder
    private let portraitSource: PortraitFrameSource

    init(recorder: DualRecorder, portraitSource: PortraitFrameSource) {
        self.recorder = recorder
        self.portraitSource = portraitSource
    }

    func handle(videoSampleBuffer: CMSampleBuffer) {
        recorder.handle(videoSampleBuffer: videoSampleBuffer)
        portraitSource.handle(videoSampleBuffer: videoSampleBuffer)
    }

    func handle(audioSampleBuffer: CMSampleBuffer) {
        recorder.handle(audioSampleBuffer: audioSampleBuffer)
    }
}
