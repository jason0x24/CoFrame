import AVFoundation
import SwiftUI
import UIKit

/// Hosts the portrait frame source's `AVSampleBufferDisplayLayer` inside a 9:16 box.
///
/// We deliberately avoid a second `AVCaptureVideoPreviewLayer` here — sharing one
/// `AVCaptureSession` between two preview layers causes connection contention on a
/// single-camera (non-MultiCam) session, where one layer renders and the other goes black.
///
/// The visible 9:16 region is selected by sizing the display layer **wider than the
/// container** (matching the source's 16:9 aspect at the container's height) and
/// translating it horizontally based on `cropPosition` (0 = left, 1 = right). The
/// container's `clipsToBounds` cuts off the off-screen sides. This works reliably on
/// `AVSampleBufferDisplayLayer`, which ignores `contentsRect`.
struct PortraitPiPView: UIViewRepresentable {
    let source: PortraitFrameSource
    let mirrored: Bool
    let cropPosition: CGFloat

    func makeUIView(context: Context) -> ContainerView {
        let view = ContainerView()
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        view.layer.borderWidth = 1.5
        view.layer.cornerRadius = 8
        view.clipsToBounds = true
        view.attach(displayLayer: source.displayLayer)
        view.applyMirror(mirrored)
        view.cropPosition = cropPosition
        return view
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        uiView.attach(displayLayer: source.displayLayer)
        uiView.applyMirror(mirrored)
        uiView.cropPosition = cropPosition
    }

    final class ContainerView: UIView {
        private weak var hostedLayer: AVSampleBufferDisplayLayer?

        var cropPosition: CGFloat = 0.5 {
            didSet {
                if cropPosition != oldValue { updateLayerFrame() }
            }
        }

        func attach(displayLayer: AVSampleBufferDisplayLayer) {
            guard hostedLayer !== displayLayer else { return }
            displayLayer.removeFromSuperlayer()
            layer.addSublayer(displayLayer)
            hostedLayer = displayLayer
            updateLayerFrame()
        }

        /// Apply mirror as a UIView transform — `AVSampleBufferDisplayLayer` does not
        /// reliably honor a transform set on itself, but it does follow its host UIView's transform.
        func applyMirror(_ mirrored: Bool) {
            transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateLayerFrame()
        }

        private func updateLayerFrame() {
            guard let layer = hostedLayer, bounds.height > 0 else { return }
            let containerH = bounds.height
            let containerW = bounds.width
            // Source is 16:9. Lay the layer out to that aspect at the container's height,
            // making it wider than the container; horizontal travel = layerW - containerW.
            let layerW = containerH * 16.0 / 9.0
            let travel = max(0, layerW - containerW)
            let offsetX = -cropPosition * travel

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = CGRect(x: offsetX, y: 0, width: layerW, height: containerH)
            CATransaction.commit()
        }
    }
}
