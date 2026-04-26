import Foundation
import Observation

/// Watches `ProcessInfo.thermalState` and exposes a coarse 3-stage status.
/// 4K30/4K60 dual-recording can push iPhone into `.serious` or `.critical`
/// after 10–20 minutes; we surface this so the UI can warn (and stop
/// recording at `.critical` to preserve the file & battery).
@Observable
@MainActor
final class ThermalMonitor {
    enum Status: Sendable, Equatable {
        case ok          // .nominal, .fair
        case warning     // .serious
        case critical    // .critical
    }

    private(set) var status: Status = .ok

    init() {
        update()
        // Permanent observer — `ThermalMonitor` lives for the app's lifetime
        // (one per `CaptureViewModel`, which is held by the root view), so we
        // don't bother tracking the token for cleanup. The `[weak self]`
        // capture means the callback safely no-ops if the monitor ever does
        // get deallocated.
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update()
            }
        }
    }

    private func update() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair: status = .ok
        case .serious:        status = .warning
        case .critical:       status = .critical
        @unknown default:     status = .ok
        }
    }
}
