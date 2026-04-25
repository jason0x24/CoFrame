import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: CameraSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session.captureSession
        view.previewLayer.videoGravity = .resizeAspect
        view.applyLandscapeRotation()
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.applyLandscapeRotation()
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        /// The preview layer's `connection` is created asynchronously after `session` is set.
        /// Try immediately, then retry on the next runloop tick to catch the late-arriving connection.
        func applyLandscapeRotation() {
            setRotationIfPossible()
            DispatchQueue.main.async { [weak self] in self?.setRotationIfPossible() }
        }

        private func setRotationIfPossible() {
            guard let conn = previewLayer.connection else { return }
            if conn.isVideoRotationAngleSupported(0) {
                conn.videoRotationAngle = 0
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            setRotationIfPossible()
        }
    }
}
