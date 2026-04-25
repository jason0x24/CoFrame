import CoreMotion
import Foundation
import Observation

/// Surfaces a single value: how many degrees the device is tilted away from level
/// when held in landscape orientation. Zero means perfectly horizontal.
@Observable
nonisolated final class LevelMonitor: @unchecked Sendable {
    private let manager = CMMotionManager()
    var rollDegrees: Double = 0

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            // Reduces gravity to a 2D in-plane angle for a phone held in landscape.
            // (We negate gravity.x so that landscape-right "level" reads as 0°.)
            let angle = atan2(m.gravity.y, -m.gravity.x) * 180.0 / .pi
            self.rollDegrees = angle
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
