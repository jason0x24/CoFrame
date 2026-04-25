import SwiftUI

@main
struct CoFrameApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
