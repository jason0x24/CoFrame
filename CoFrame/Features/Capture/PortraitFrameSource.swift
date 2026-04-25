import AVFoundation
import CoreMedia
import Foundation
import QuartzCore

/// Owns an `AVSampleBufferDisplayLayer` that the PiP view hosts, and feeds it the
/// camera's raw landscape sample buffers. The layer's `videoGravity = .resizeAspectFill`
/// inside a 9:16 host frame produces the same center-crop as the recorder's portrait writer.
nonisolated final class PortraitFrameSource: CameraSampleSink, @unchecked Sendable {
    let displayLayer: AVSampleBufferDisplayLayer

    init() {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspectFill
        self.displayLayer = layer
    }

    func handle(videoSampleBuffer: CMSampleBuffer) {
        nonisolated(unsafe) let buf = videoSampleBuffer
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // If the layer entered a failed state (e.g. after backgrounding), recover.
            if self.displayLayer.status == .failed {
                self.displayLayer.flush()
            }
            self.displayLayer.sampleBufferRenderer.enqueue(buf)
        }
    }

    func handle(audioSampleBuffer: CMSampleBuffer) {}
}
