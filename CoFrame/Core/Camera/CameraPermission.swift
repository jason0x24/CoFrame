import AVFoundation

enum CameraPermissionStatus {
    case notDetermined
    case denied
    case authorized
}

enum CameraPermission {
    static func videoStatus() -> CameraPermissionStatus { map(AVCaptureDevice.authorizationStatus(for: .video)) }
    static func audioStatus() -> CameraPermissionStatus { map(AVCaptureDevice.authorizationStatus(for: .audio)) }

    static func requestVideo() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
    static func requestAudio() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    static func requestAll() async -> (video: Bool, audio: Bool) {
        async let v = requestVideo()
        async let a = requestAudio()
        return await (v, a)
    }

    private static func map(_ status: AVAuthorizationStatus) -> CameraPermissionStatus {
        switch status {
        case .authorized: .authorized
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}
