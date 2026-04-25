import AVFoundation
import SwiftUI
import UIKit

/// Hosts the portrait frame source's `AVSampleBufferDisplayLayer` inside a small 9:16 box.
/// We deliberately avoid a second `AVCaptureVideoPreviewLayer` here — sharing one
/// `AVCaptureSession` between two preview layers causes connection contention on a
/// single-camera (non-MultiCam) session, where one layer renders and the other goes black.
struct PortraitPiPView: UIViewRepresentable {
    let source: PortraitFrameSource
    let mirrored: Bool

    func makeUIView(context: Context) -> ContainerView {
        let view = ContainerView()
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        view.layer.borderWidth = 1.5
        view.layer.cornerRadius = 8
        view.clipsToBounds = true
        view.attach(displayLayer: source.displayLayer)
        view.applyMirror(mirrored)
        return view
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        uiView.attach(displayLayer: source.displayLayer)
        uiView.applyMirror(mirrored)
    }

    final class ContainerView: UIView {
        private weak var hostedLayer: AVSampleBufferDisplayLayer?

        func attach(displayLayer: AVSampleBufferDisplayLayer) {
            guard hostedLayer !== displayLayer else { return }
            displayLayer.removeFromSuperlayer()
            layer.addSublayer(displayLayer)
            displayLayer.frame = bounds
            hostedLayer = displayLayer
        }

        /// Apply mirror as a UIView transform — `AVSampleBufferDisplayLayer` does not
        /// reliably honor a transform set on itself, but it does follow its host UIView's transform.
        func applyMirror(_ mirrored: Bool) {
            transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            hostedLayer?.frame = bounds
        }
    }
}
