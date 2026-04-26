import SwiftUI

@main
struct CoFrameApp: App {
    @AppStorage(AppPreferences.Key.language)
    private var languageRaw: String = LanguageOption.system.rawValue

    var body: some Scene {
        WindowGroup {
            CaptureView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .environment(\.locale, currentLocale)
        }
    }

    private var currentLocale: Locale {
        LanguageOption(rawValue: languageRaw)?.locale ?? .current
    }
}
