import AVFoundation
import Foundation
import Observation
import UIKit

nonisolated enum GuideLineKind: CaseIterable, Sendable {
    case off
    case ruleOfThirds
    case crosshair
    case level
    case all

    var displayName: String {
        switch self {
        case .off: "关"
        case .ruleOfThirds: "九宫"
        case .crosshair: "十字"
        case .level: "水平"
        case .all: "全部"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "square"
        case .ruleOfThirds: "grid"
        case .crosshair: "plus.viewfinder"
        case .level: "level"
        case .all: "rectangle.grid.2x2"
        }
    }

    var next: GuideLineKind {
        let cases = GuideLineKind.allCases
        let i = cases.firstIndex(of: self)!
        return cases[(i + 1) % cases.count]
    }

    var showThirds: Bool { self == .ruleOfThirds || self == .all }
    var showCrosshair: Bool { self == .crosshair || self == .all }
    var showLevel: Bool { self == .level || self == .all }
}

@MainActor
@Observable
final class CaptureViewModel {
    enum State: Equatable {
        case idle
        case configuring
        case ready
        case recording(startedAt: Date)
        case finishing
        case error(String)
    }

    var state: State = .idle
    var quality: VideoQuality = .hd1080p30
    var position: CameraPosition = .back
    var guideLine: GuideLineKind = .ruleOfThirds
    var pipHidden: Bool = false
    var lastError: String?
    var elapsed: TimeInterval = 0

    /// Horizontal position of the 9:16 portrait crop within the 16:9 source.
    /// 0 = left edge, 0.5 = center (default), 1 = right edge.
    /// The recorder reads this for source-pixel cropping; the PiP view reads it
    /// directly via SwiftUI binding to translate its display layer.
    var portraitCropPosition: CGFloat = 0.5 {
        didSet {
            let clamped = max(0, min(1, portraitCropPosition))
            recorder.cropPosition = clamped
        }
    }

    let session = CameraSession()
    let recorder = DualRecorder()
    let portraitSource = PortraitFrameSource()
    let level = LevelMonitor()

    private let coordinator: SampleCoordinator
    private var timer: Timer?
    private var bootstrapped = false

    init() {
        let coord = SampleCoordinator(recorder: recorder, portraitSource: portraitSource)
        self.coordinator = coord
        recorder.delegate = self
        session.sink = coord
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        state = .configuring

        let perm = await CameraPermission.requestAll()
        guard perm.video, perm.audio else {
            state = .error("CoFrame 需要相机和麦克风权限。请在「设置 → CoFrame」中开启。")
            return
        }

        do {
            try await session.configure(quality: quality, position: position)
            session.start()
            level.start()
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func toggleRecord() {
        switch state {
        case .ready: startRecording()
        case .recording: stopRecording()
        default: break
        }
    }

    private func startRecording() {
        do {
            try recorder.start(quality: quality, into: .shared)
            UIApplication.shared.isIdleTimerDisabled = true
            let now = Date()
            state = .recording(startedAt: now)
            elapsed = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed = Date().timeIntervalSince(now)
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        state = .finishing
        recorder.stop()
    }

    func switchCamera() async {
        guard case .ready = state else { return }
        do {
            try await session.switchPosition()
            position = session.position
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setQuality(_ new: VideoQuality) async {
        guard case .ready = state else { return }
        do {
            try await session.setQuality(new)
            quality = new
        } catch {
            lastError = error.localizedDescription
        }
    }

    func togglePiP() { pipHidden.toggle() }
    func cycleGuide() { guideLine = guideLine.next }
}

extension CaptureViewModel: DualRecorderDelegate {
    nonisolated func dualRecorder(_ recorder: DualRecorder, didFinishWith session: RecordingSession) {
        Task { @MainActor in
            try? RecordingStore.shared.writeMeta(for: session)
            self.state = .ready
        }
    }

    nonisolated func dualRecorder(_ recorder: DualRecorder, didFailWith error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.state = .ready
        }
    }
}
