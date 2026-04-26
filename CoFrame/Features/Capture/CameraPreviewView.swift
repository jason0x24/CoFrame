import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: CameraSession
    /// Tap → (layerPoint in view coords, devicePoint in 0..1 capture-space coords).
    var onTap: ((CGPoint, CGPoint) -> Void)?
    /// Long-press → (layerPoint, devicePoint). Fires once on `.began`.
    var onLongPress: ((CGPoint, CGPoint) -> Void)?
    /// Pinch lifecycle for continuous zoom.
    var onPinchBegin: (() -> Void)?
    var onPinchChange: ((CGFloat) -> Void)?  // cumulative scale since gesture start

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session.captureSession
        view.previewLayer.videoGravity = .resizeAspect
        view.applyLandscapeRotation()
        view.installGestures()
        view.onTap = onTap
        view.onLongPress = onLongPress
        view.onPinchBegin = onPinchBegin
        view.onPinchChange = onPinchChange
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.onTap = onTap
        uiView.onLongPress = onLongPress
        uiView.onPinchBegin = onPinchBegin
        uiView.onPinchChange = onPinchChange
    }

    final class PreviewUIView: UIView {
        var onTap: ((CGPoint, CGPoint) -> Void)?
        var onLongPress: ((CGPoint, CGPoint) -> Void)?
        var onPinchBegin: (() -> Void)?
        var onPinchChange: ((CGFloat) -> Void)?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private var gesturesInstalled = false

        func installGestures() {
            guard !gesturesInstalled else { return }
            gesturesInstalled = true

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.numberOfTapsRequired = 1
            addGestureRecognizer(tap)

            let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            long.minimumPressDuration = 0.5
            addGestureRecognizer(long)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            addGestureRecognizer(pinch)
        }

        @objc private func handleTap(_ gr: UITapGestureRecognizer) {
            let layerPoint = gr.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            onTap?(layerPoint, devicePoint)
        }

        @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began else { return }
            let layerPoint = gr.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            onLongPress?(layerPoint, devicePoint)
        }

        @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
            switch gr.state {
            case .began:
                onPinchBegin?()
            case .changed:
                onPinchChange?(gr.scale)
            default:
                break
            }
        }

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
