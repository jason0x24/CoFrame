import AVFoundation
import CoreMedia
import Foundation
import QuartzCore

/// Owns an `AVSampleBufferDisplayLayer` that the PiP view hosts and feeds it the
/// camera's raw landscape sample buffers. Cropping for the visible 9:16 strip is
/// done by the host view (it sizes the layer wider than its bounds and translates
/// horizontally), so this class is a thin passthrough.
nonisolated final class PortraitFrameSource: CameraSampleSink, @unchecked Sendable {
    let displayLayer: AVSampleBufferDisplayLayer

    /// Dedicated queue for enqueueing buffers to the display layer. Apple's
    /// `AVSampleBufferRenderer.enqueue(_:)` is thread-safe, so we deliberately
    /// stay off the main queue — at 30/60 fps, hammering main here would
    /// delay gesture recognition and SwiftUI tick.
    private let renderQueue = DispatchQueue(
        label: "com.gnwl.CoFrame.pip.render",
        qos: .userInteractive
    )

    init() {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        self.displayLayer = layer
    }

    func handle(videoSampleBuffer: CMSampleBuffer) {
        nonisolated(unsafe) let buf = videoSampleBuffer
        renderQueue.async { [weak self] in
            guard let self else { return }
            let renderer = self.displayLayer.sampleBufferRenderer
            // If the layer entered a failed state (e.g. after backgrounding), recover.
            if renderer.status == .failed {
                renderer.flush()
            }
            renderer.enqueue(buf)
        }
    }

    func handle(audioSampleBuffer: CMSampleBuffer) {}
}
