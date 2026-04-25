import Foundation
import Photos

/// Wraps `PHPhotoLibrary` for adding finished CoFrame recordings to the system Photos
/// app. Uses the `addOnly` permission level (iOS 14+) so we never request read access.
nonisolated enum PhotoExporter {
    enum ExporterError: LocalizedError {
        case unauthorized
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "无法导出：未授予相册添加权限。请在「设置 → CoFrame → 照片」中开启。"
            case .writeFailed(let msg): "导出失败：\(msg)"
            }
        }
    }

    static func currentStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    static func ensurePermission() async -> Bool {
        switch currentStatus() {
        case .authorized, .limited:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    cont.resume(returning: status == .authorized || status == .limited)
                }
            }
        @unknown default:
            return false
        }
    }

    /// Adds the file at `url` to the user's Photos library. Throws on permission denial
    /// or library write failure.
    static func saveVideo(at url: URL) async throws {
        guard await ensurePermission() else { throw ExporterError.unauthorized }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { success, error in
                if success {
                    cont.resume()
                } else {
                    let message = error?.localizedDescription ?? "未知错误"
                    cont.resume(throwing: ExporterError.writeFailed(message))
                }
            })
        }
    }

    /// Save several videos in sequence; collects per-file errors and returns the count
    /// that succeeded so the UI can report partial success.
    static func saveVideos(_ urls: [URL]) async -> (succeeded: Int, errors: [Error]) {
        var ok = 0
        var errors: [Error] = []
        for url in urls {
            do {
                try await saveVideo(at: url)
                ok += 1
            } catch {
                errors.append(error)
            }
        }
        return (ok, errors)
    }
}
