import SwiftUI
import SwiftData

@main
struct ScreenshotForgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        // Persists the app library on disk automatically.
        .modelContainer(for: [AppProject.self, Asset.self])

        // Preferences window (⌘,) — App Store Connect credentials.
        Settings {
            SettingsView()
        }
    }
}
